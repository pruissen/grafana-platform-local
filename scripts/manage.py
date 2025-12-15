import argparse
import base64
import json
import os
import subprocess
import time
import requests
import sys

# Configuration
NAMESPACE = "observability-prd"
SECRET_NAME = "grafana-admin-creds"
SERVICE_NAME = "lgtm-distributed-grafana"
LOCAL_PORT = 3000

def get_k8s_secret():
    """Fetches the Grafana admin password from K8s secrets."""
    print(f"🔑 Fetching credentials from secret '{SECRET_NAME}'...")
    try:
        cmd = f"kubectl get secret {SECRET_NAME} -n {NAMESPACE} -o jsonpath='{{.data.admin-password}}'"
        result = subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
        return base64.b64decode(result).decode('utf-8')
    except subprocess.CalledProcessError:
        print("❌ Failed to fetch secret. Is kubectl configured?")
        sys.exit(1)

def start_port_forward():
    """Starts a temporary background port-forward to Grafana."""
    print(f"🔌 Opening port-forward to {SERVICE_NAME}...")
    proc = subprocess.Popen(
        ["kubectl", "port-forward", f"svc/{SERVICE_NAME}", f"{LOCAL_PORT}:80", "-n", NAMESPACE],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(3) # Wait for connection
    return proc

def import_dashboards(password):
    """Imports defined dashboards via Grafana API."""
    base_url = f"http://admin:{password}@localhost:{LOCAL_PORT}/api/dashboards/db"
    headers = {"Content-Type": "application/json", "Accept": "application/json"}

    # List of Dashboards to Import (ID: URL)
    dashboards = {
        "Kubernetes Compute Resources": "https://grafana.com/api/dashboards/15760/revisions/24/download",
        "OpenTelemetry Demo Webstore": "https://grafana.com/api/dashboards/19924/revisions/1/download",
        "Node Exporter Full": "https://grafana.com/api/dashboards/1860/revisions/37/download"
    }

    for name, download_url in dashboards.items():
        print(f"📦 Downloading dashboard: {name}...")
        try:
            # 1. Download JSON
            dash_json = requests.get(download_url).json()
            
            # 2. Fix Datasources
            payload = {
                "dashboard": dash_json,
                "overwrite": True,
                "inputs": [
                    {"name": "DS_PROMETHEUS", "type": "datasource", "pluginId": "prometheus", "value": "Mimir"},
                    {"name": "DS_LOKI", "type": "datasource", "pluginId": "loki", "value": "Loki"},
                    {"name": "DS_TEMPO", "type": "datasource", "pluginId": "tempo", "value": "Tempo"}
                ]
            }
            
            # 3. Upload to Grafana
            response = requests.post(base_url, json=payload, headers=headers)
            
            if response.status_code == 200:
                print(f"   ✅ Imported: {name}")
            else:
                print(f"   ⚠️ Failed to import {name}: {response.text}")

        except Exception as e:
            print(f"   ❌ Error processing {name}: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Grafana Platform Manager")
    parser.add_argument("--import-dashboards", action="store_true", help="Import standard dashboards")
    args = parser.parse_args()

    if args.import_dashboards:
        password = get_k8s_secret()
        pf_process = start_port_forward()
        try:
            import_dashboards(password)
        finally:
            print("🔌 Closing port-forward...")
            pf_process.terminate()
    else:
        parser.print_help()