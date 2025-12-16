#!/bin/bash

PID_FILE="/tmp/lgtm-stack-portforward.pid"
LOG_FILE="/tmp/lgtm-stack-portforward.log"

# Helper function to start a self-healing forwarder in the background
start_forward_loop() {
    local NAME=$1
    local NAMESPACE=$2
    local RESOURCE=$3
    local PORT_MAPPING=$4

    (
        while true; do
            echo "[$(date)] [$NAME] Connecting to $RESOURCE in $NAMESPACE ($PORT_MAPPING)..." >> "$LOG_FILE"
            kubectl port-forward "$RESOURCE" -n "$NAMESPACE" "$PORT_MAPPING" >> "$LOG_FILE" 2>&1
            
            EXIT_CODE=$?
            echo "[$(date)] [$NAME] Disconnected (Code: $EXIT_CODE). Retrying in 2s..." >> "$LOG_FILE"
            sleep 2
        done
    ) &
    # Store the PID of the loop subshell
    PIDS+=($!)
}

start() {
    if [ -f "$PID_FILE" ]; then
        if ps -p $(head -n 1 "$PID_FILE") > /dev/null; then
            echo "✅ Port-forwards are already running."
            echo "   View logs: tail -f $LOG_FILE"
            exit 0
        else
            rm "$PID_FILE"
        fi
    fi

    echo "🚀 Starting Self-Healing Port-Forwards..."
    echo "   (Logs are being written to $LOG_FILE)"
    
    # Initialize PID array
    PIDS=()

    # 1. Grafana (Port 3000)
    start_forward_loop "Grafana" "observability-prd" "svc/lgtm-grafana" "3000:80"

    # 2. MinIO Console (Port 9001) - FIXED SERVICE NAME
    start_forward_loop "MinIO" "observability-prd" "svc/lgtm-minio-console" "9001:9001"

    # 3. Astronomy Shop Frontend (Port 8081 locally to avoid conflict)
    start_forward_loop "DemoApp" "astronomy-shop" "svc/astronomy-shop-frontendproxy" "8081:8080"

    # Save all PIDs to the file
    printf "%s\n" "${PIDS[@]}" > "$PID_FILE"

    echo "------------------------------------------------------------------------"
    echo "✅ DASHBOARD ACCESS & CREDENTIALS"
    echo "------------------------------------------------------------------------"
    
    echo "📊 Grafana"
    echo "   URL:      http://localhost:3000"
    echo "   User:     admin"
    printf "   Pass:     "
    kubectl get secret -n observability-prd grafana-admin-creds -o jsonpath="{.data.admin-password}" | base64 -d; echo
    echo ""

    echo "🗄️  MinIO Console"
    echo "   URL:      http://localhost:9001"
    echo "   User:     admin"
    printf "   Pass:     "
    kubectl get secret -n observability-prd lgtm-minio -o jsonpath="{.data.rootPassword}" | base64 -d; echo
    echo ""

    echo "🛍️  Astronomy Shop (Demo App)"
    echo "   URL:      http://localhost:8081"
    echo "   User:     (No Auth Required)"
    echo ""
    
    echo "🐙 ArgoCD (Separate Forwarder)"
    echo "   Run:      make forward-argocd"
    echo "   URL:      https://localhost:8080"
    echo "   User:     admin"
    printf "   Pass:     "
    kubectl get secret -n argocd-system argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(Not found - check install)"
    echo ""
    echo "------------------------------------------------------------------------"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        echo "🛑 Stopping Port-Forward loops..."
        
        # Kill all PIDs listed in the file
        while read -r PID; do
            kill "$PID" 2>/dev/null
        done < "$PID_FILE"
        
        # Cleanup any lingering kubectl processes matching our targets
        pkill -f "kubectl port-forward svc/lgtm-grafana"
        pkill -f "kubectl port-forward svc/lgtm-minio-console"
        pkill -f "kubectl port-forward svc/astronomy-shop-frontendproxy"
        
        rm "$PID_FILE"
        echo "✅ All port-forwards stopped."
    else
        echo "⚠️  No PID file found. Cleaning up potential orphans..."
        pkill -f "kubectl port-forward svc/lgtm-grafana"
        pkill -f "kubectl port-forward svc/lgtm-minio-console"
        pkill -f "kubectl port-forward svc/astronomy-shop-frontendproxy"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 1
        start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
esac