#!/bin/bash
SESSION="argocd-lab"
start() {
    screen -ls | grep -q $SESSION && echo "Session running." && exit 0
    echo "--- Launching ArgoCD Forward ---"
    screen -dmS $SESSION
    screen -S $SESSION -X screen -t argocd bash -c "kubectl port-forward --address 0.0.0.0 svc/argocd-server -n argocd-system 8080:80; exec bash"
    ARGO_PASS=$(kubectl -n argocd-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "ArgoCD: http://localhost:8080 (admin / $ARGO_PASS)"
}
stop() { screen -S $SESSION -X quit; }
case "$1" in start) start ;; stop) stop ;; esac