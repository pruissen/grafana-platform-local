#!/bin/bash
SESSION="grafana-lab"
start() {
    echo "Starting Observability forwards..."
    screen -dmS $SESSION
    screen -S $SESSION -X screen -t grafana bash -c "kubectl port-forward --address 0.0.0.0 svc/lgtm-distributed-grafana -n observability-prd 3000:80; exec bash"
    screen -S $SESSION -X screen -t oncall bash -c "kubectl port-forward --address 0.0.0.0 svc/lgtm-distributed-grafana-oncall-engine -n observability-prd 8082:8080; exec bash"
    screen -S $SESSION -X screen -t minio bash -c "kubectl port-forward --address 0.0.0.0 svc/minio-storage-console -n observability-prd 9001:9001; exec bash"
    screen -S $SESSION -X screen -t webstore bash -c "kubectl port-forward --address 0.0.0.0 svc/astronomy-shop-frontend -n astronomy-shop 8081:8080; exec bash"

    GP=$(kubectl -n observability-prd get secret grafana-admin-creds -o jsonpath="{.data.admin-password}" | base64 -d)
    MP=$(kubectl -n observability-prd get secret minio-creds -o jsonpath="{.data.rootPassword}" | base64 -d)
    echo "Grafana: http://localhost:3000 (admin / $GP)"
    echo "MinIO:   http://localhost:9001 (admin / $MP)"
    echo "Shop:    http://localhost:8081"
}
stop() { screen -S $SESSION -X quit; }
case "$1" in start) start ;; stop) stop ;; esac