# terraform/main.tf

# -------------------------------------------------------------------
# 1. PROVIDERS & CONFIG
# -------------------------------------------------------------------
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

# -------------------------------------------------------------------
# 2. NAMESPACES
# -------------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd-system"
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability-prd"
  }
}

resource "kubernetes_namespace" "devteam_1" {
  metadata {
    name = "devteam-1"
  }
}

# -------------------------------------------------------------------
# 3. ARGOCD
# -------------------------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    file("${path.module}/../k8s/values/argocd.yaml")
  ]
}

# -------------------------------------------------------------------
# 4. SHARED SECRETS & CREDENTIALS
# -------------------------------------------------------------------

# A. Generate Random Password
resource "random_password" "minio_root_password" {
  length  = 24
  special = false
}

# B. Secret for MinIO Server
resource "kubernetes_secret_v1" "minio_creds" {
  metadata {
    name      = "minio-creds"
    namespace = "observability-prd"
  }
  data = {
    rootUser     = "admin"
    rootPassword = random_password.minio_root_password.result
  }
  type = "Opaque"
}

# C. Secrets for Clients (S3 Access)
resource "kubernetes_secret_v1" "mimir_s3_creds" {
  metadata {
    name      = "mimir-s3-credentials"
    namespace = "observability-prd"
  }
  data = {
    AWS_ACCESS_KEY_ID     = "admin"
    AWS_SECRET_ACCESS_KEY = random_password.minio_root_password.result
  }
  type = "Opaque"
}

resource "kubernetes_secret_v1" "loki_s3_creds" {
  metadata {
    name      = "loki-s3-credentials"
    namespace = "observability-prd"
  }
  data = {
    AWS_ACCESS_KEY_ID     = "admin"
    AWS_SECRET_ACCESS_KEY = random_password.minio_root_password.result
  }
  type = "Opaque"
}

resource "kubernetes_secret_v1" "tempo_s3_creds" {
  metadata {
    name      = "tempo-s3-credentials"
    namespace = "observability-prd"
  }
  data = {
    AWS_ACCESS_KEY_ID     = "admin"
    AWS_SECRET_ACCESS_KEY = random_password.minio_root_password.result
  }
  type = "Opaque"
}

# D. Secrets for k8s-monitoring (Alloy Authentication)
resource "kubernetes_secret" "loki_k8s_monitoring" {
  metadata {
    name      = "loki-k8s-monitoring"
    namespace = "observability-prd"
  }

  data = {
    username = "admin"
    password = random_password.minio_root_password.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "prometheus_k8s_monitoring" {
  metadata {
    name      = "prometheus-k8s-monitoring"
    namespace = "observability-prd"
  }

  data = {
    username = "admin"
    password = random_password.minio_root_password.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "tempo_k8s_monitoring" {
  metadata {
    name      = "tempo-k8s-monitoring"
    namespace = "observability-prd"
  }

  data = {
    username = "admin"
    password = random_password.minio_root_password.result
  }

  type = "Opaque"
}

# -------------------------------------------------------------------
# 5. LOKI
# -------------------------------------------------------------------
resource "kubectl_manifest" "loki" {
  depends_on = [
    helm_release.argocd, 
    kubernetes_secret_v1.loki_s3_creds, 
    kubernetes_secret_v1.minio_creds
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "loki"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "observability-prd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "loki"
        targetRevision = "6.24.0"
        helm = {
          values = file("${path.module}/../k8s/values/loki.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 6. MIMIR
# -------------------------------------------------------------------
resource "kubectl_manifest" "mimir" {
  depends_on = [
    helm_release.argocd, 
    kubectl_manifest.loki, 
    kubernetes_secret_v1.mimir_s3_creds
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "mimir"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "observability-prd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "mimir-distributed"
        targetRevision = "5.6.0"
        helm = {
          values = file("${path.module}/../k8s/values/mimir.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 7. TEMPO
# -------------------------------------------------------------------
resource "kubectl_manifest" "tempo" {
  depends_on = [
    helm_release.argocd, 
    kubectl_manifest.loki, 
    kubernetes_secret_v1.tempo_s3_creds
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "tempo"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "observability-prd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "tempo"
        targetRevision = "1.24.1" 
        helm = {
          values = file("${path.module}/../k8s/values/tempo.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 8. GRAFANA
# -------------------------------------------------------------------
resource "random_password" "grafana_admin_password" {
  length  = 16
  special = false
}

resource "kubernetes_secret_v1" "grafana_creds" {
  metadata {
    name      = "grafana-admin-creds"
    namespace = "observability-prd"
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin_password.result
  }
  type = "Opaque"
}

resource "kubectl_manifest" "grafana" {
  depends_on = [
    helm_release.argocd, 
    kubernetes_secret_v1.grafana_creds,
    kubectl_manifest.mimir,
    kubectl_manifest.loki,
    kubectl_manifest.tempo
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "grafana"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "observability-prd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "grafana"
        targetRevision = "8.5.1"
        helm = {
          values = file("${path.module}/../k8s/values/grafana.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 9. K8S MONITORING (Replaces Alloy & Kube-State-Metrics)
# -------------------------------------------------------------------
resource "kubectl_manifest" "alloy" {
  depends_on = [
    helm_release.argocd,
    kubectl_manifest.mimir,
    kubectl_manifest.loki,
    kubectl_manifest.tempo,
    # Ensure secrets exist before deploying
    kubernetes_secret.loki_k8s_monitoring,
    kubernetes_secret.prometheus_k8s_monitoring,
    kubernetes_secret.tempo_k8s_monitoring
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "k8s-monitoring"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "observability-prd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        # ⚠️ FIXED: Enable Server-Side Apply to handle large CRDs
        syncOptions = [
          "ServerSideApply=true"
        ]
      }
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "k8s-monitoring"
        targetRevision = "1.6.1"
        helm = {
          values = file("${path.module}/../k8s/values/k8s-monitoring.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 10. OTEL DEMO (Astronomy Shop)
# -------------------------------------------------------------------
resource "kubectl_manifest" "astronomy_shop" {
  depends_on = [
    kubectl_manifest.alloy, # Waits for the new monitoring stack
    kubernetes_namespace.devteam_1
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "astronomy-shop"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "devteam-1"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
      source = {
        repoURL        = "https://open-telemetry.github.io/opentelemetry-helm-charts"
        chart          = "opentelemetry-demo"
        targetRevision = "0.31.0"
        helm = {
          values = file("${path.module}/../k8s/values/astronomy-shop.yaml")
        }
      }
    }
  })
}