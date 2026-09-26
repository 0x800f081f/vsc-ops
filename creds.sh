pw_argocd=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
pw_grafana=$(kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath="{.data.admin-password}" | base64 -d)

echo "===================== Argo CD =====================\n"
echo "ArgoCD Login:  admin  /  $pw_argocd"
echo "Dashboard:     kubectl port-forward svc/argocd-server -n argocd 3000:443   -> https://localhost:3000"
echo "===================================================\n"

echo "===================== Grafana =====================\n"
echo "Grafana Login: admin  /  $pw_grafana"
echo "Dashboard:     kubectl port-forward svc/kube-prometheus-stack-grafana -n argocd 8080:80   -> https://localhost:8080"
echo "===================================================\n"

