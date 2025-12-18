#!/bin/bash

# Configuration
PID_FILE="/tmp/minio-portforward.pid"
LOG_FILE="/tmp/minio-portforward.log"
NAMESPACE="observability-prd"
# Ports: Local 9001 -> Remote 9001 (Console)
LOCAL_PORT="9001"
REMOTE_PORT="9001"
SERVICE="svc/loki-minio-console"

# ---------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------

show() {
    echo "------------------------------------------------------------------------"
    echo "🗄️  MINIO STORAGE (CONSOLE)"
    echo "------------------------------------------------------------------------"
    
    if [ -f "$PID_FILE" ] && ps -p $(cat "$PID_FILE") > /dev/null; then
        echo "✅ Status:   RUNNING (PID: $(cat $PID_FILE))"
    else
        echo "⚠️  Status:   STOPPED"
    fi

    echo "🔗 URL:      http://localhost:${LOCAL_PORT}"
    
    # Retrieve Credentials Safely
    USER=$(kubectl get secret -n "$NAMESPACE" minio-creds -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 -d)
    PASS=$(kubectl get secret -n "$NAMESPACE" minio-creds -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 -d)

    if [ -z "$USER" ]; then
        echo "👤 User:     (Secret 'minio-creds' not found)"
    else
        echo "👤 User:     $USER"
        echo "🔑 Pass:     $PASS"
    fi
    echo "------------------------------------------------------------------------"
}

start() {
    if [ -f "$PID_FILE" ]; then
        if ps -p $(cat "$PID_FILE") > /dev/null; then
            echo "✅ MinIO port-forward is already running."
            show
            exit 0
        else
            rm "$PID_FILE"
        fi
    fi

    echo "🚀 Starting MinIO self-healing port-forward..."
    
    (
        while true; do
            echo "[$(date)] Connecting to $SERVICE..." >> "$LOG_FILE"
            kubectl port-forward -n "$NAMESPACE" "$SERVICE" "${LOCAL_PORT}:${REMOTE_PORT}" >> "$LOG_FILE" 2>&1
            echo "[$(date)] Connection died. Restarting in 2s..." >> "$LOG_FILE"
            sleep 2
        done
    ) &

    echo $! > "$PID_FILE"
    sleep 1
    show
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "🛑 Stopping MinIO port-forward (PID: $PID)..."
        kill "$PID" 2>/dev/null
        # Cleanup any lingering matching processes
        pkill -f "kubectl port-forward -n $NAMESPACE .*${LOCAL_PORT}:${REMOTE_PORT}"
        rm "$PID_FILE"
        echo "✅ Stopped."
    else
        echo "⚠️  No PID file found. Cleaning up orphans..."
        pkill -f "kubectl port-forward -n $NAMESPACE .*${LOCAL_PORT}:${REMOTE_PORT}"
        echo "✅ Cleanup complete."
    fi
}

help() {
    echo "Usage: $0 {start|stop|restart|show|help}"
}

# ---------------------------------------------------------
# MENU LOGIC
# ---------------------------------------------------------
case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    show)    show ;;
    *)       help ;;
esac