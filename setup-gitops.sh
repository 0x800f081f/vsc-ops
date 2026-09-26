#!/usr/bin/env bash
#
# setup-gitops.sh
#
# Einmalige GitOps-Einrichtung auf EINEM lokalen Minikube-Cluster fuer
# ZWEI Umgebungen (staging + prod): nginx-Ingress + ArgoCD installieren,
# Secrets anlegen (App + Grafana-Login), alle ArgoCD-Applications anwenden
# (staging, prod, monitoring).
#
# Lokale Bash-Variante von setup-gitops.ps1: statt DigitalOcean (doctl/DOKS)
# wird ein lokaler Minikube-Cluster verwendet (Single-Node).
#
# BEISPIEL
#   ./setup-gitops.sh
#
set -euo pipefail

# Secrets fuer App + Monitoring: NICHT im Repo. Werte kommen aus einer lokalen,
# gitignorten Datei "secrets.env" (Vorlage: siehe README) oder aus Umgebungsvariablen.
[ -f "$(dirname "${BASH_SOURCE[0]}")/secrets.env" ] && source "$(dirname "${BASH_SOURCE[0]}")/secrets.env"
: "${JWT_SECRET:?JWT_SECRET fehlt (secrets.env oder export)}"
: "${DB_PASSWORD:?DB_PASSWORD fehlt (secrets.env oder export)}"
: "${GRAFANA_PASSWORD:?GRAFANA_PASSWORD fehlt (secrets.env oder export)}"
: "${NTFY_TOKEN:?NTFY_TOKEN fehlt (secrets.env oder export)}"


# Pfade relativ zum Skript-Verzeichnis (funktioniert also aus jedem CWD)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Werkzeug-Check
# ---------------------------------------------------------------------------
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Werkzeug '$1' fehlt auf dem PATH." >&2
    exit 1
  fi
}
need minikube
need kubectl
need helm

# Beide Umgebungen: Namespace + zugehoeriges Application-Manifest
ENV_NS=("user-mgmt-staging" "user-mgmt-prod")
ENV_APP=("$SCRIPT_DIR/application-staging.yaml" "$SCRIPT_DIR/application-prod.yaml")


echo "==> Kontext: $(kubectl config current-context)"
kubectl get nodes
read -r -p "Auf DIESEM Cluster einrichten? (y/n) " answer
if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
  exit 0
fi


# ---------------------------------------------------------------------------
# nginx Ingress-Controller
# ---------------------------------------------------------------------------
# Minikube: ingress-Addon (metallb) aktivieren, damit der LoadBalancer-Service
# einen EXTERNAL-IP bekommt (auf DOKS passiert das nativ, auf Minikube nicht).
echo "==> Minikube ingress-Addon (metallb) aktivieren..."
minikube addons enable ingress

echo "==> nginx Ingress-Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx 2>/dev/null || true
# Orphan-Ressourcen (z. B. aus einem abgebrochenen Install) haben kein
# Helm-Eigentums-Label und blockieren das Install ("invalid ownership
# metadata"). Ohne Helm-Release werden die verwaisten Chart-Ressourcen
# per Chart-Label geraeumt: alle cluster-scoped Typen des Charts
# (ClusterRole, ClusterRoleBinding, (Mutating|Validating)WebhookConfiguration,
# IngressClass) sowie der ganze Namespace (deckt alle namespaced Typen ab).
if ! helm list -n ingress-nginx -q 2>/dev/null | grep -qx "ingress-nginx"; then
  orphans="$(kubectl get clusterrole,clusterrolebinding,mutatingwebhookconfiguration,validatingwebhookconfiguration,ingressclass \
    -l app.kubernetes.io/instance=ingress-nginx -o name 2>/dev/null || true)"
  if kubectl get namespace ingress-nginx >/dev/null 2>&1 || [[ -n "$orphans" ]]; then
    echo "   Kein Helm-Release, aber verwaiste Chart-Ressourcen -> raeume auf..."
    kubectl delete clusterrole,clusterrolebinding,mutatingwebhookconfiguration,validatingwebhookconfiguration,ingressclass \
      -l app.kubernetes.io/instance=ingress-nginx --ignore-not-found
    kubectl delete namespace ingress-nginx --ignore-not-found --timeout=180s
  fi
fi
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.publishService.enabled=true
kubectl rollout status deployment/ingress-nginx-controller \
  --namespace ingress-nginx \
  --timeout=180s

# ---------------------------------------------------------------------------
# metrics-server fuer den HPA
# ---------------------------------------------------------------------------
# Minikube bringt den metrics-server als Addon mit (Default: aktiv).
# Anders als auf DOKS ist hier KEIN '--kubelet-insecure-tls'-Patch noetig:
# Minikube regelt die Kubelet-Zertifikate selbst.
# 'addons enable' ist idempotent (No-Op, wenn das Addon bereits aktiv ist).
echo "==> metrics-server sicherstellen (fuer HPA)..."
minikube addons enable metrics-server
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s


# ---------------------------------------------------------------------------
# ArgoCD
# ---------------------------------------------------------------------------
echo "==> ArgoCD installieren..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
echo "==> ArgoCD Helm-Repository (prometheus-community) registrieren..."
kubectl apply -f "$SCRIPT_DIR/argocd-repository-prometheus-community.yaml"


# ---------------------------------------------------------------------------
# Secrets je Namespace anlegen (Werte oben hartkodiert)
# ---------------------------------------------------------------------------

# Namespaces fuer staging und prod + zugehoeriges app-secret
for i in "${!ENV_NS[@]}"; do
  ns="${ENV_NS[$i]}"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic app-secret -n "$ns" \
    --from-literal=SPRING_DATASOURCE_PASSWORD="$DB_PASSWORD" \
    --from-literal=JWT_SECRET="$JWT_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -
done
# Namespace für monitoring
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic grafana-admin-credentials -n monitoring \
  --from-literal=admin-user="admin" \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic ntfy-token -n monitoring \
  --from-literal=token="$NTFY_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -


# ---------------------------------------------------------------------------
# ArgoCD-Applications (staging + prod + monitoring) anwenden
# ---------------------------------------------------------------------------
echo "==> ArgoCD-Applications (staging + prod + monitoring) anwenden..."
for i in "${!ENV_APP[@]}"; do
  kubectl apply -f "${ENV_APP[$i]}"
done
# Orchestrierung & Observability / Aufgabe 1: kube-prometheus-stack
kubectl apply -f "$SCRIPT_DIR/application-monitoring.yaml"


# ---------------------------------------------------------------------------
# Zugang ausgeben
# ---------------------------------------------------------------------------
echo ""
echo "===================== FERTIG ====================="
pw="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo "ArgoCD Login:  admin  /  $pw"
echo "Dashboard:     kubectl port-forward svc/argocd-server -n argocd 8080:443  -> https://localhost:8080"
echo "App-URL:       kubectl get svc ingress-nginx-controller -n ingress-nginx  (EXTERNAL-IP)"
echo "Namespaces:    user-mgmt-staging  &  user-mgmt-prod"
echo "Grafana:       kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "               Login: admin / $GRAFANA_PASSWORD  (Secret: grafana-admin-credentials)"
echo "               Passwort erneut anzeigen: kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d"
echo "Prometheus:    kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
echo "================================================="
echo ""
