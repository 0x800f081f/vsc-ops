#requires -Version 5.1
<#
.SYNOPSIS
  Einmalige GitOps-Einrichtung auf DigitalOcean fuer ZWEI Umgebungen (staging + prod):
  nginx-Ingress + ArgoCD installieren, Secrets anlegen (App + Grafana-Login),
  alle ArgoCD-Applications anwenden (staging, prod, monitoring).

.BEISPIELE
  .\setup-gitops.ps1 -ClusterName teko-doks -CreateCluster -NodeCount 3
  .\setup-gitops.ps1 -ClusterName teko-doks
#>
param(
  [string]$ClusterName  = "",
  [switch]$CreateCluster,
  [string]$Region       = "fra1",
  [string]$NodeSize     = "s-2vcpu-4gb",
  [int]   $NodeCount    = 3,
  [switch]$Force
)
$ErrorActionPreference = "Stop"
function Need($c){ if(-not(Get-Command $c -ErrorAction SilentlyContinue)){ throw "Werkzeug '$c' fehlt auf dem PATH." } }
Need doctl; Need kubectl; Need helm

# Beide Umgebungen: Namespace + zugehoeriges Application-Manifest
$envs = @(
  @{ ns = "user-mgmt-staging"; app = ".\application-staging.yaml" },
  @{ ns = "user-mgmt-prod";    app = ".\application-prod.yaml" }
)

# 1) Cluster
if ($CreateCluster) {
  if ($ClusterName -eq "") { throw "-CreateCluster benoetigt -ClusterName." }
  Write-Host "==> Erstelle DOKS-Cluster '$ClusterName' ($NodeCount x $NodeSize)..." -ForegroundColor Cyan
  doctl kubernetes cluster create $ClusterName --region $Region `
    --node-pool "name=worker-pool;size=$NodeSize;count=$NodeCount" --1-clicks metrics-server --wait | Out-Host
} elseif ($ClusterName -ne "") {
  doctl kubernetes cluster kubeconfig save $ClusterName | Out-Host
}
Write-Host "==> Kontext: $(kubectl config current-context)" -ForegroundColor Yellow
kubectl get nodes | Out-Host
if (-not $Force) { if ((Read-Host "Auf DIESEM Cluster einrichten? (y/n)") -ne "y") { return } }

# 2) nginx Ingress-Controller
Write-Host "==> nginx Ingress-Controller..." -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null | Out-Null
helm repo update ingress-nginx 2>$null | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.publishService.enabled=true | Out-Host
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s | Out-Host

# 2b) metrics-server (Aufgabe 6: Messwerte fuer den HPA)
Write-Host "==> metrics-server installieren (fuer HPA)..." -ForegroundColor Cyan
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml | Out-Host
# Auf DOKS: Kubelet-Zertifikate nicht strikt pruefen, sonst wird der Server nicht 'ready'
kubectl patch deployment metrics-server -n kube-system --type=json `
  -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]' | Out-Host
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s | Out-Host

# 3) ArgoCD
Write-Host "==> ArgoCD installieren..." -ForegroundColor Cyan
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - | Out-Host
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml | Out-Host
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s | Out-Host

# 3b) Orchestrierung & Observability / Aufgabe 1: Monitoring vorbereiten
# Helm-Repository prometheus-community in ArgoCD registrieren (Chart-Quelle
# fuer den kube-prometheus-stack, siehe application-monitoring.yaml).
Write-Host "==> ArgoCD Helm-Repository (prometheus-community) registrieren..." -ForegroundColor Cyan
kubectl apply -f .\argocd-repository-prometheus-community.yaml | Out-Host

# 4) Secrets (einmalig erzeugt/gespeichert) je Namespace anlegen
$secretFile = ".\do-secrets.json"
if (Test-Path $secretFile) {
  $s = Get-Content $secretFile -Raw | ConvertFrom-Json
} else {
  $jwt  = -join ((1..64) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
  $dbpw = -join ((1..24) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
  $s = [pscustomobject]@{ JWT_SECRET=$jwt; DB_PASSWORD=$dbpw }
  $s | ConvertTo-Json | Set-Content $secretFile -Encoding utf8
  Write-Host "   do-secrets.json erzeugt -> NICHT committen (.gitignore)!" -ForegroundColor Yellow
}
# Grafana-Passwort: einmalig erzeugen und in do-secrets.json nachtragen,
# damit es bei spaeteren Laeufen wiederverwendet wird (kein Plaintext im Repo).
if (-not $s.PSObject.Properties['GRAFANA_PASSWORD']) {
  $s | Add-Member -NotePropertyName GRAFANA_PASSWORD `
    -NotePropertyValue (-join ((1..24) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) }))
  $s | ConvertTo-Json | Set-Content $secretFile -Encoding utf8
  Write-Host "   do-secrets.json um GRAFANA_PASSWORD erweitert." -ForegroundColor Yellow
}
foreach ($e in $envs) {
  kubectl create namespace $e.ns --dry-run=client -o yaml | kubectl apply -f - | Out-Host
  kubectl create secret generic app-secret -n $e.ns `
    --from-literal=SPRING_DATASOURCE_PASSWORD="$($s.DB_PASSWORD)" `
    --from-literal=JWT_SECRET="$($s.JWT_SECRET)" `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Host
}

# 4b) Orchestrierung & Observability / Aufgabe 1: Grafana-Login als Kubernetes-Secret.
# Kein Plaintext in values.yaml; der kube-prometheus-stack liest die Zugangsdaten
# ueber grafana.admin.existingSecret (monitoring/values.yaml). Das Secret muss VOR
# dem Start der Grafana-Pods existieren, deshalb hier (vor Schritt 5) anlegen.
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - | Out-Host
kubectl create secret generic grafana-admin-credentials -n monitoring `
  --from-literal=admin-user="admin" `
  --from-literal=admin-password="$($s.GRAFANA_PASSWORD)" `
  --dry-run=client -o yaml | kubectl apply -f - | Out-Host

# 4c) Aufgabe 1: ntfy-Token fuer den Alertmanager (Benachrichtigungskanal).
# Wird NICHT im Repo gespeichert: einmalig abfragen und in do-secrets.json
# (gitignored) ablegen. Ohne dieses Secret startet der Alertmanager-Pod nicht,
# weil monitoring/values.yaml es per alertmanagerSpec.secrets einbindet.
if (-not $s.PSObject.Properties['NTFY_TOKEN']) {
  $tok = Read-Host "ntfy-Access-Token eingeben (tk_...)"
  $s | Add-Member -NotePropertyName NTFY_TOKEN -NotePropertyValue $tok
  $s | ConvertTo-Json | Set-Content $secretFile -Encoding utf8
  Write-Host "   do-secrets.json um NTFY_TOKEN erweitert." -ForegroundColor Yellow
}
kubectl create secret generic ntfy-token -n monitoring `
  --from-literal=token="$($s.NTFY_TOKEN)" `
  --dry-run=client -o yaml | kubectl apply -f - | Out-Host

# Optional: Zugangsdaten zusaetzlich als GitHub-Secrets im Ops-Repo ablegen
# (benoetigt eine eingeloggte gh-CLI). Damit sind sie auch ueber GitHub verfuegbar.
if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh secret set GRAFANA_ADMIN_USER     --repo MikeGarda/vsc-ops --body "admin"                  2>$null | Out-Null
  gh secret set GRAFANA_ADMIN_PASSWORD --repo MikeGarda/vsc-ops --body "$($s.GRAFANA_PASSWORD)" 2>$null | Out-Null
  Write-Host "   GitHub-Secrets GRAFANA_ADMIN_USER/GRAFANA_ADMIN_PASSWORD gesetzt (MikeGarda/vsc-ops)." -ForegroundColor Yellow
} else {
  Write-Host "   Hinweis: gh-CLI fehlt -> GitHub-Secrets nicht gesetzt (optional)." -ForegroundColor DarkGray
}

# 5) ArgoCD-Applications (staging + prod + monitoring) anwenden
Write-Host "==> ArgoCD-Applications (staging + prod + monitoring) anwenden..." -ForegroundColor Cyan
foreach ($e in $envs) { kubectl apply -f $e.app | Out-Host }
# Orchestrierung & Observability / Aufgabe 1: kube-prometheus-stack (Namespace "monitoring")
kubectl apply -f .\application-monitoring.yaml | Out-Host

# 6) Zugang ausgeben
Write-Host "`n===================== FERTIG =====================" -ForegroundColor Green
$pw = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$pw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pw))
Write-Host "ArgoCD Login:  admin  /  $pw" -ForegroundColor Cyan
Write-Host "Dashboard:     kubectl port-forward svc/argocd-server -n argocd 8080:443  -> https://localhost:8080" -ForegroundColor Cyan
Write-Host "App-URL:       kubectl get svc ingress-nginx-controller -n ingress-nginx  (EXTERNAL-IP)" -ForegroundColor Cyan
Write-Host "Namespaces:    user-mgmt-staging  &  user-mgmt-prod" -ForegroundColor Cyan
Write-Host "Grafana:       kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80" -ForegroundColor Cyan
Write-Host "               Login: admin / $($s.GRAFANA_PASSWORD)  (Secret: grafana-admin-credentials)" -ForegroundColor Cyan
Write-Host "               Passwort erneut anzeigen: kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d" -ForegroundColor Cyan
Write-Host "Prometheus:    kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090" -ForegroundColor Cyan
Write-Host "=================================================`n" -ForegroundColor Green
