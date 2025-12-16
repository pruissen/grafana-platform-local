.PHONY: all install-k3s create-namespaces install-argocd install-observability install-otel import-dashboards forward forward-argocd clean nuke uninstall-observability clean-observability

USER_NAME ?= $(shell whoami)
# Detects the IP of the interface 'enp2s0'
NODE_IP ?= $(shell ip -4 addr show enp2s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# ---------------------------------------------------------
# MASTER FLOW
# ---------------------------------------------------------
all: install-k3s create-namespaces install-argocd install-observability install-otel import-dashboards

# ---------------------------------------------------------
# 1. INFRASTRUCTURE (K3s)
# ---------------------------------------------------------
install-k3s:
	@echo "--- 0. Setting up Virtual Disk ---"
	@chmod +x scripts/setup-virtual-disk.sh
	@sudo bash scripts/setup-virtual-disk.sh

	@echo "--- 1. Installing K3s (Interface: enp2s0) ---"
	curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip=$(NODE_IP) --flannel-iface=enp2s0 --bind-address=$(NODE_IP) --advertise-address=$(NODE_IP) --disable=traefik" sh -
	
	@echo "--- 2. Configuring Permissions ---"
	sudo mkdir -p ~/.kube
	sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
	sudo chown $(USER_NAME):$(USER_NAME) ~/.kube/config
	chmod 600 ~/.kube/config
	
	@echo "--- 3. Waiting for Cluster ---"
	@timeout=120; until kubectl get nodes | grep -q "Ready"; do echo "Waiting for node..."; sleep 2; done
	@echo "✅ K3s Ready."

create-namespaces:
	@echo "--- Creating Namespaces ---"
	@kubectl create namespace argocd-system --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create namespace observability-prd --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create namespace astronomy-shop --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------
# 2. ARGOCD
# ---------------------------------------------------------
install-argocd: create-namespaces
	@echo "--- Installing ArgoCD ---"
	cd terraform && terraform init && terraform apply -auto-approve -target=helm_release.argocd
	@sleep 10
	@bash scripts/portforward-argocd.sh start

# ---------------------------------------------------------
# 3. OBSERVABILITY (LGTM Stack + Bundled MinIO)
# ---------------------------------------------------------
install-observability:
	@echo "--- Installing LGTM Stack (Mimir, Loki, Tempo, MinIO) ---"
	cd terraform && terraform apply -auto-approve \
		-target=helm_release.ksm \
		-target=random_password.minio_root_password \
		-target=random_password.grafana_admin_password \
		-target=random_password.oncall_db_password \
		-target=random_password.oncall_rabbitmq_password \
		-target=random_password.oncall_redis_password \
		-target=kubernetes_secret_v1.minio_creds \
		-target=kubernetes_secret_v1.grafana_creds \
		-target=kubernetes_secret_v1.mimir_s3_creds \
		-target=kubernetes_secret_v1.oncall_db_secret \
		-target=kubernetes_secret_v1.oncall_rabbitmq_secret \
		-target=kubernetes_secret_v1.oncall_redis_secret \
		-target=kubectl_manifest.lgtm

uninstall-observability:
	@echo "--- 🗑️  Uninstalling LGTM Stack via Terraform ---"
	cd terraform && terraform destroy -auto-approve \
		-target=kubectl_manifest.lgtm \
		-target=kubectl_manifest.alloy \
		-target=kubectl_manifest.astronomy \
		-target=helm_release.ksm

clean-observability:
	@echo "--- 🧹 Manually Emptying observability-prd Namespace ---"
	@echo "Deleting all resources..."
	@kubectl delete all --all -n observability-prd --force --grace-period=0 2>/dev/null || true
	@echo "Deleting all PVCs..."
	@kubectl delete pvc --all -n observability-prd --force --grace-period=0 2>/dev/null || true
	@echo "Deleting all ConfigMaps..."
	@kubectl delete cm --all -n observability-prd --force --grace-period=0 2>/dev/null || true
	@echo "Deleting all Secrets..."
	@kubectl delete secret --all -n observability-prd --force --grace-period=0 2>/dev/null || true
	@echo "Deleting all Ingresses..."
	@kubectl delete ingress --all -n observability-prd --force --grace-period=0 2>/dev/null || true
	@echo "✅ observability-prd is empty."

install-otel:
	@echo "--- Installing Alloy & Demo ---"
	cd terraform && terraform apply -auto-approve -target=kubectl_manifest.alloy -target=kubectl_manifest.astronomy

import-dashboards:
	@echo "--- Importing Dashboards ---"
	@pip install -r scripts/requirements.txt > /dev/null 2>&1 || echo "Run pip install!"
	@python3 scripts/manage.py --import-dashboards

# ---------------------------------------------------------
# 4. UTILITIES
# ---------------------------------------------------------
forward:
	@bash scripts/portforward.sh start

forward-argocd:
	@bash scripts/portforward-argocd.sh start

stop-forward:
	@bash scripts/portforward.sh stop
	@bash scripts/portforward-argocd.sh stop

clean:
	@echo "--- Destroying ALL Terraform Resources ---"
	cd terraform && terraform destroy -auto-approve

# ---------------------------------------------------------
# 5. NUCLEAR OPTION (Remove K3s)
# ---------------------------------------------------------
nuke:
	@echo "--- ☢️  NUKING CLUSTER ☢️  ---"
	@chmod +x scripts/nuke-microk8s.sh 2>/dev/null || true
	@bash scripts/nuke-microk8s.sh 2>/dev/null || true
	
	@echo "--- Uninstalling K3s ---"
	/usr/local/bin/k3s-uninstall.sh || true
	
	@echo "--- Cleaning up mounts and configs ---"
	sudo umount /var/lib/rancher 2>/dev/null || true
	sudo rm -rf /etc/rancher
	sudo rm -rf /var/lib/rancher
	rm -rf ~/.kube
	
	@echo "✅ System Completely Cleaned."