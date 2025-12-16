#!/bin/bash

# Configuration
PID_FILE="/tmp/argocd-portforward.pid"
LOG_FILE="/tmp/argocd-portforward.log"
NAMESPACE="argocd-system"
SERVICE="svc/argocd-server"
LOCAL_PORT="8080"
REMOTE_PORT="443"

# ---------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------

show() {
    echo "------------------------------------------------------------------------"
    echo "🐙 ARGOCD ACCESS & CREDENTIALS"
    echo "------------------------------------------------------------------------"
    
    # Check if port-forward is actually running
    if [ -f "$PID_FILE" ] && ps -p $(cat "$PID_FILE") > /dev/null; then
        echo "✅ Status:   RUNNING (PID: $(cat $PID_FILE))"
    else
        echo "⚠️  Status:   STOPPED"
    fi

    echo "🔗 URL:      https://localhost:${LOCAL_PORT}"
    echo "👤 User:     admin"
    
    # Retrieve password safely
    PASS=$(kubectl get secret -n "$NAMESPACE" argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if [ -z "$PASS" ]; then
        echo "🔑 Pass:     (Secret not found - is ArgoCD installed?)"
    else
        echo "🔑 Pass:     $PASS"
    fi
    echo "------------------------------------------------------------------------"
}

start() {
    if [ -f "$PID_FILE" ]; then
        if ps -p $(cat "$PID_FILE") > /dev/null; then
            echo "✅ ArgoCD port-forward is already running."
            show
            exit 0
        else
            rm "$PID_FILE"
        fi
    fi

    echo "🚀 Starting ArgoCD self-healing port-forward..."
    
    # Run the auto-healing loop in the background
    (
        while true; do
            echo "[$(date)] Starting connection to $SERVICE..." >> "$LOG_FILE"
            
            # The actual port-forward command
            kubectl port-forward -n "$NAMESPACE" "$SERVICE" "${LOCAL_PORT}:${REMOTE_PORT}" >> "$LOG_FILE" 2>&1
            
            # If it crashes/disconnects, log it and wait before restarting
            EXIT_CODE=$?
            echo "[$(date)] Connection died (Code: $EXIT_CODE). Restarting in 2s..." >> "$LOG_FILE"
            sleep 2
        done
    ) &

    # Save the PID of the loop
    echo $! > "$PID_FILE"
    
    # Wait a moment to let the first connection attempt happen
    sleep 1
    show
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "🛑 Stopping ArgoCD port-forward (PID: $PID)..."
        
        # Kill the loop process
        kill "$PID" 2>/dev/null
        
        # Cleanup any lingering kubectl processes matching our target
        pkill -f "kubectl port-forward -n $NAMESPACE $SERVICE"
        
        rm "$PID_FILE"
        echo "✅ Stopped."
    else
        echo "⚠️  No PID file found. Cleaning up potential orphans..."
        pkill -f "kubectl port-forward -n $NAMESPACE $SERVICE"
        echo "✅ Cleanup complete."
    fi
}

# ---------------------------------------------------------
# MENU LOGIC
# ---------------------------------------------------------

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
    show)
        show
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|show}"
        exit 1
esac