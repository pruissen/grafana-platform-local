#!/bin/bash

# Define where to store the PID and Logs
PID_FILE="/tmp/argocd-portforward.pid"
LOG_FILE="/tmp/argocd-portforward.log"

start() {
    # Check if already running
    if [ -f "$PID_FILE" ]; then
        if ps -p $(cat "$PID_FILE") > /dev/null; then
            echo "✅ ArgoCD port-forward is already running (PID: $(cat $PID_FILE))."
            echo "   View logs: tail -f $LOG_FILE"
            exit 0
        else
            # Stale PID file
            rm "$PID_FILE"
        fi
    fi

    echo "🚀 Starting ArgoCD self-healing port-forward..."
    
    # Run the loop in the background
    (
        while true; do
            echo "[$(date)] Starting kubectl port-forward..." >> "$LOG_FILE"
            
            # The actual command. We use svc/argocd-server explicitly.
            # We filter out the 'Handling connection' spam to keep logs clean-ish
            kubectl port-forward svc/argocd-server -n argocd-system 8080:443 >> "$LOG_FILE" 2>&1
            
            EXIT_CODE=$?
            echo "[$(date)] Port-forward crashed with exit code $EXIT_CODE. Restarting in 2s..." >> "$LOG_FILE"
            sleep 2
        done
    ) &

    # Save the PID of the loop (not the kubectl command)
    echo $! > "$PID_FILE"
    echo "✅ Running in background (PID: $(cat $PID_FILE))."
    echo "   Access at: https://localhost:8080"
    echo "   Logs: $LOG_FILE"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "🛑 Stopping ArgoCD port-forward loop (PID: $PID)..."
        
        # Kill the loop process (the parent)
        kill $PID 2>/dev/null
        
        # Find and kill any lingering kubectl port-forward processes matching our target
        pkill -f "kubectl port-forward svc/argocd-server"
        
        rm "$PID_FILE"
        echo "✅ Stopped."
    else
        echo "⚠️  No PID file found. Is it running?"
        # Cleanup just in case
        pkill -f "kubectl port-forward svc/argocd-server"
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