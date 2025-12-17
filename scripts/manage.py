#!/usr/bin/env python3
import requests
import sys
import time
import base64
import os
import json

# --- CONFIGURATION ---
GRAFANA_URL = "http://localhost:3000"
ADMIN_USER = "admin"
OUTPUT_FILE = "bootstrap-results.json"

# Fetch password from K8s if not provided via env var
try:
    import subprocess
    cmd = "kubectl get secret -n observability-prd grafana-admin-creds -o jsonpath='{.data.admin-password}' | base64 -d"
    ADMIN_PASS = subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
except:
    ADMIN_PASS = "admin" # Fallback

# Org Definitions
ORGS = [
    {
        "name": "platform-k8s",
        "tenant_id": "platform-k8s",
        "sa_name": "sa-platform-k8s"
    },
    {
        "name": "platform-obs",
        "tenant_id": "platform-obs",
        "sa_name": "sa-platform-obs"
    },
    {
        "name": "devteam-1",
        "tenant_id": "devteam-1",
        "sa_name": "sa-devteam-1"
    }
]

# --- FUNCTIONS ---
def get_auth():
    return (ADMIN_USER, ADMIN_PASS)

def create_org(name):
    print(f"🏢 Processing Org: {name}...")
    res = requests.post(f"{GRAFANA_URL}/api/orgs", json={"name": name}, auth=get_auth())
    if res.status_code == 409:
        # Fetch ID if exists
        orgs = requests.get(f"{GRAFANA_URL}/api/orgs/name/{name}", auth=get_auth()).json()
        return orgs['id']
    elif res.status_code == 200:
        print(f"   -> Created new Org.")
        return res.json()['orgId']
    else:
        print(f"   -> Error creating Org: {res.text}")
        return None

def create_datasource(org_id, org_name, ds_type, name, url, tenant_id):
    headers = {"X-Grafana-Org-Id": str(org_id)}
    
    payload = {
        "name": name,
        "type": ds_type,
        "url": url,
        "access": "proxy",
        "isDefault": True,
        "jsonData": {},
        "secureJsonData": {}
    }

    # Add Tenant Headers
    if ds_type in ["prometheus", "loki", "tempo"]:
        payload["jsonData"]["httpHeaderName1"] = "X-Scope-OrgID"
        payload["secureJsonData"]["httpHeaderValue1"] = tenant_id

    # Check if exists to update or create
    existing = requests.get(f"{GRAFANA_URL}/api/datasources/name/{name}", auth=get_auth(), headers=headers)
    
    if existing.status_code == 200:
        # Update existing
        ds_id = existing.json()['id']
        requests.put(f"{GRAFANA_URL}/api/datasources/{ds_id}", json=payload, auth=get_auth(), headers=headers)
        print(f"   PLEASED TO MEET YOU: Updated Datasource '{name}' for {tenant_id}")
    else:
        # Create new
        requests.post(f"{GRAFANA_URL}/api/datasources", json=payload, auth=get_auth(), headers=headers)
        print(f"   CREATED: Datasource '{name}' for {tenant_id}")

def create_service_account_and_token(org_id, sa_name):
    headers = {"X-Grafana-Org-Id": str(org_id)}
    
    # 1. Search for existing Service Account
    search = requests.get(f"{GRAFANA_URL}/api/serviceaccounts/search?name={sa_name}", auth=get_auth(), headers=headers)
    sa_id = None
    
    if search.status_code == 200 and len(search.json()['serviceAccounts']) > 0:
        sa_id = search.json()['serviceAccounts'][0]['id']
        print(f"   -> Found existing Service Account (ID: {sa_id})")
    else:
        # Create SA
        create = requests.post(f"{GRAFANA_URL}/api/serviceaccounts", json={"name": sa_name, "role": "Editor"}, auth=get_auth(), headers=headers)
        if create.status_code == 201:
            sa_id = create.json()['id']
            print(f"   -> Created Service Account (ID: {sa_id})")
        else:
            print(f"   -> Failed to create SA: {create.text}")
            return None

    # 2. Manage Token (Rotate: Create new, user handles cleanup of old manually if needed, or we just generate a fresh one)
    # Ideally, we delete old tokens with the same name to keep it clean
    tokens = requests.get(f"{GRAFANA_URL}/api/serviceaccounts/{sa_id}/tokens", auth=get_auth(), headers=headers)
    token_name = f"bootstrap-token-{int(time.time())}"
    
    # Create new token
    new_token_res = requests.post(f"{GRAFANA_URL}/api/serviceaccounts/{sa_id}/tokens", json={"name": token_name}, auth=get_auth(), headers=headers)
    
    if new_token_res.status_code == 200:
        key = new_token_res.json()['key']
        print(f"   -> Generated new Access Token: {token_name}")
        return key
    else:
        print(f"   -> Failed to generate token: {new_token_res.text}")
        return None

def bootstrap():
    print("--- 🚀 STARTING GRAFANA BOOTSTRAP ---")
    
    # Check connection
    try:
        requests.get(f"{GRAFANA_URL}/api/health")
    except:
        print("❌ Could not connect to Grafana on localhost:3000. Please run './scripts/portforward-grafana.sh start' first.")
        sys.exit(1)

    results = {}

    for org in ORGS:
        org_id = create_org(org['name'])
        
        if org_id:
            # 1. Configure Datasources
            create_datasource(org_id, org['name'], "prometheus", "Mimir", "http://mimir-nginx.observability-prd.svc:80/prometheus", org['tenant_id'])
            create_datasource(org_id, org['name'], "loki", "Loki", "http://loki-gateway.observability-prd.svc:80", org['tenant_id'])
            create_datasource(org_id, org['name'], "tempo", "Tempo", "http://tempo.observability-prd.svc:3100", org['tenant_id'])

            # 2. Create Service Account & Token
            token = create_service_account_and_token(org_id, org['sa_name'])
            
            if token:
                results[org['name']] = {
                    "org_id": org_id,
                    "tenant_id": org['tenant_id'],
                    "service_account": org['sa_name'],
                    "token": token
                }

    # Output Results
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(results, f, indent=4)
    
    print(f"\n✅ BOOTSTRAP COMPLETE! Credentials saved to {OUTPUT_FILE}")
    print(f"   (Use 'cat {OUTPUT_FILE}' to view tokens)")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--bootstrap-orgs":
        bootstrap()
    else:
        print("Usage: python3 scripts/manage.py --bootstrap-orgs")