# 🔭 Enterprise Grafana LGTM Stack on K3s

Granular, distributed deployment of the Grafana Observability stack using ArgoCD, Terraform, and K3s.

## 🏗️ Architecture
* **Storage:** Bitnami MinIO (Enterprise-grade artifact)
* **Metrics:** Grafana Mimir (Distributed)
* **Logs:** Grafana Loki (Simple Scalable)
* **Traces:** Grafana Tempo (Distributed)
* **Visualization:** Grafana
* **Collector:** Grafana Alloy

## 🚀 Quick Start

1.  **Install Base & Prereqs:**
    ```bash
    make all
    ```

2.  **Access:**
    ```bash
    make forward
    ```