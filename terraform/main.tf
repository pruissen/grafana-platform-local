# -------------------------------------------------------------------
# 1. SECRETS GENERATION
# -------------------------------------------------------------------
resource "random_password" "minio_root_password" {
  length  = 16
  special = false
}

resource "random_password" "grafana_admin_password" {
  length  = 16
  special = false
}

# -------------------------------------------------------------------
# 2. KUBERNETES SECRETS
# -------------------------------------------------------------------

# MinIO Credentials (Used by MinIO Server)
resource "kubernetes_secret_v1" "minio_creds" {
  metadata {
    name      = "minio-creds"
    namespace = "observability-prd"
  }
  data = {
    # Bitnami chart expects "root-user" and "root-password"
    "root-user"     = "admin"
    "root-password" = random_password.minio_root_password.result
    # Legacy keys for compatibility
    rootUser        = "admin"
    rootPassword    = random_password.minio_root_password.result
  }
}

# S3 Credentials (Used by Mimir/Loki/Tempo Clients)
resource "kubernetes_secret_v1" "mimir_s3_creds" {
  metadata {
    name      = "mimir-s3-credentials"
    namespace = "observability-prd"
  }
  data = {
    AWS_ACCESS_KEY_ID     = "admin"
    AWS_SECRET_ACCESS_KEY = random_password.minio_root_password.result
  }
}

# Grafana Admin Credentials
resource "kubernetes_secret_v1" "grafana_creds" {
  metadata {
    name      = "grafana-admin-creds"
    namespace = "observability-prd"
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin_password.result
  }
}

# -------------------------------------------------------------------
# 3. BASE INFRASTRUCTURE
# -------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd-system"
  version    = "7.7.16"
  values = [yamlencode({
    server = {
      insecure = true
    }
  })]
}

resource "helm_release" "ksm" {
  name             = "kube-state-metrics"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-state-metrics"
  namespace        = "observability-prd"
  version          = "5.16.0"
  create_namespace = false
}

# -------------------------------------------------------------------
# 4. APP 1: SHARED STORAGE (MinIO Official)
# -------------------------------------------------------------------
resource "kubectl_manifest" "minio" {
  depends_on = [helm_release.argocd, kubernetes_secret_v1.minio_creds]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "minio-enterprise"
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
        # UPDATED: Official MinIO Repository
        repoURL        = "https://charts.min.io/"
        chart          = "minio"
        # Using a recent stable version compliant with the new values.yaml structure
        targetRevision = "5.3.0"
        helm = {
          values = file("${path.module}/../k8s/values/minio-enterprise.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 5. APP 2: MIMIR (Metrics)
# -------------------------------------------------------------------
resource "kubectl_manifest" "mimir" {
  depends_on = [kubectl_manifest.minio, kubernetes_secret_v1.mimir_s3_creds]
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
# 6. APP 3: LOKI (Logs)
# -------------------------------------------------------------------
resource "kubectl_manifest" "loki" {
  depends_on = [kubectl_manifest.minio]
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
# 7. APP 4: TEMPO (Traces)
# -------------------------------------------------------------------
resource "kubectl_manifest" "tempo" {
  depends_on = [kubectl_manifest.minio]
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
        chart          = "tempo-distributed"
        targetRevision = "1.18.1"
        helm = {
          values = file("${path.module}/../k8s/values/tempo.yaml")
        }
      }
    }
  })
}

# -------------------------------------------------------------------
# 8. APP 5: GRAFANA (Viz)
# -------------------------------------------------------------------
resource "kubectl_manifest" "grafana" {
  depends_on = [kubernetes_secret_v1.grafana_creds]
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
# 9. OTEL / DEMO
# -------------------------------------------------------------------
resource "kubectl_manifest" "alloy" {
  depends_on = [kubectl_manifest.mimir, kubectl_manifest.loki, kubectl_manifest.tempo]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "alloy"
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
        chart          = "alloy"
        targetRevision = "0.9.1"
        helm = {
          values = file("${path.module}/../k8s/values/alloy.yaml")
        }
      }
    }
  })
}

resource "kubectl_manifest" "astronomy" {
  depends_on = [kubectl_manifest.alloy]
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
        namespace = "astronomy-shop"
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
        targetRevision = "0.26.0"
        helm = {
          parameters = [
            { name = "opentelemetry-collector.enabled", value = "false" },
            { name = "jaeger.enabled", value = "false" },
            { name = "grafana.enabled", value = "false" },
            { name = "default.env.OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://alloy.observability-prd.svc:4317" }
          ]
        }
      }
    }
  })
}