#!/bin/bash

PID_FILE="/tmp/lgtm-stack-portforward.pid"
LOG_FILE="/tmp/lgtm-stack-portforward.log"

start_forward_loop() {
    local NAME=$1
    local NAMESPACE=$2
    local RESOURCE=$3
    local PORT_MAPPING=$4

    (
        while true; do
            echo "[$(date)] [$NAME] Connecting to $RESOURCE in $NAMESPACE ($PORT_MAPPING)..." >> "$LOG_FILE"
            kubectl port-forward "$RESOURCE" -n "$NAMESPACE" "$PORT_MAPPING" >> "$LOG_FILE" 2>&1
            sleep 2
        done
    ) &
    PIDS+=($!)
}

start() {
    if [ -f "$PID_FILE" ]; then
        if ps -p $(head -n 1 "$PID_FILE") > /dev/null; then
            echo "✅ Port-forwards are already running."
            exit 0
        else
            rm "$PID_FILE"
        fi
    fi

    echo "🚀 Starting Self-Healing Port-Forwards..."
    PIDS=()

    # 1. Grafana
    start_forward_loop "Grafana" "observability-prd" "svc/grafana" "3000:80"

    # 2. MinIO Console (Bitnami service name is usually release-name)
    start_forward_loop "MinIO" "observability-prd" "svc/minio-enterprise" "9001:9001"

    # 3. Demo Shop
    start_forward_loop "DemoApp" "astronomy-shop" "svc/astronomy-shop-frontendproxy" "8081:8080"

    printf "%s\n" "${PIDS[@]}" > "$PID_FILE"

    echo "------------------------------------------------------------------------"
    echo "✅ DASHBOARD ACCESS & CREDENTIALS"
    echo "------------------------------------------------------------------------"
    echo "📊 Grafana: http://localhost:3000 (admin / see below)"
    echo "🗄️  MinIO:   http://localhost:9001 (admin / see below)"
    echo "🛍️  Shop:    http://localhost:8081"
    echo ""
    echo "Passwords:"
    echo "  Grafana: $(kubectl get secret -n observability-prd grafana-admin-creds -o jsonpath='{.data.admin-password}' | base64 -d)"
    echo "  MinIO:   $(kubectl get secret -n observability-prd minio-creds -o jsonpath='{.data.root-password}' | base64 -d)"
    echo "------------------------------------------------------------------------"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        echo "🛑 Stopping Port-Forward loops..."
        while read -r PID; do kill "$PID" 2>/dev/null; done < "$PID_FILE"
        pkill -f "kubectl port-forward svc/grafana"
        pkill -f "kubectl port-forward svc/minio-enterprise"
        pkill -f "kubectl port-forward svc/astronomy-shop-frontendproxy"
        rm "$PID_FILE"
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|restart}"; exit 1 ;;
esac