.PHONY: all install-microk8s tfvars terraform-plan terraform-apply forward clean remove-microk8s

# Detect the git URL automatically
REPO_URL ?= $(shell git config --get remote.origin.url)

all: install-microk8s terraform-apply

install-microk8s:
	@echo "--- Installing MicroK8s ---"
	sudo snap install microk8s --classic
	sudo microk8s status --wait-ready
	@echo "--- Enabling Addons ---"
	sudo microk8s enable dns
	sudo microk8s enable helm3
	sudo microk8s enable storage
	sudo microk8s config > ~/.kube/config
	sudo chmod 600 ~/.kube/config

# New Target: Generates the variable file automatically
tfvars:
	@echo "--- Generating terraform.tfvars ---"
	@echo 'repo_url = "$(REPO_URL)"' > terraform/terraform.tfvars

terraform-plan: tfvars
	@echo "--- Generating Terraform Plan ---"
	cd terraform && terraform init && terraform plan

terraform-apply: tfvars
	@echo "--- Applying Terraform (Interactive) ---"
	cd terraform && terraform init && terraform apply

forward:
	@echo "--- Launching Port Forwards ---"
	@bash scripts/portforward.sh start

stop-forward:
	@bash scripts/portforward.sh stop

clean:
	@echo "--- Destroying Terraform Resources ---"
	cd terraform && terraform destroy -auto-approve
	rm -f terraform/terraform.tfvars

remove-microk8s:
	@echo "--- Completely Removing MicroK8s ---"
	sudo microk8s stop
	sudo snap remove microk8s --purge
	rm -f ~/.kube/config