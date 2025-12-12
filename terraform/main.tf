# terraform/main.tf

# 1. Install ArgoCD using Helm
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd-system"
  create_namespace = true
  version          = "7.7.16"

  values = [
    yamlencode({
      server = {
        insecure = true
      }
      configs = {
        cm = {
          "resource.customizations.ignoreDifferences.all" = "jsonPointers:\n  - /status"
        }
      }
    })
  ]
}

# 2. Create Teams/Namespaces
resource "kubernetes_namespace" "teams" {
  for_each = toset(["k8s-platform-system", "observability-prd", "astronomy-shop"])
  metadata {
    name = each.key
  }
}

# 3. Bootstrap the Root Application
resource "kubectl_manifest" "argocd_root" {
  depends_on = [helm_release.argocd]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "bootstrap-root"
      namespace = "argocd-system"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url # This now pulls from variables.tf -> terraform.tfvars
        targetRevision = "HEAD"
        path           = "k8s/apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd-system"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })
}