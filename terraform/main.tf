# -------------------------------------------------------------------
# 1. GENERATE SECRETS
# -------------------------------------------------------------------
resource "random_password" "minio_root_password" {
  length  = 16
  special = false
}

resource "random_password" "grafana_admin_password" {
  length  = 16
  special = false
}

resource "random_password" "oncall_db_password" {
  length  = 16
  special = false
}

resource "random_password" "oncall_rabbitmq_password" {
  length  = 16
  special = false
}

resource "random_password" "oncall_redis_password" {
  length  = 16
  special = false
}

# -------------------------------------------------------------------
# 2. KUBERNETES SECRETS
# -------------------------------------------------------------------

# MinIO Admin Credentials (Renamed to 'lgtm-minio' for the bundled chart)
resource "kubernetes_secret_v1" "minio_creds" {
  metadata {
    name      = "lgtm-minio"
    namespace = "observability-prd"
  }
  data = {
    rootUser     = "admin"
    rootPassword = random_password.minio_root_password.result
  }
}

# Mimir S3 Credentials (Global Secret)
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

resource "kubernetes_secret_v1" "oncall_db_secret" {
  metadata {
    name      = "oncall-db-secret"
    namespace = "observability-prd"
  }
  data = {
    "mariadb-root-password" = random_password.oncall_db_password.result
    "mariadb-password"      = random_password.oncall_db_password.result
  }
}

resource "kubernetes_secret_v1" "oncall_rabbitmq_secret" {
  metadata {
    name      = "oncall-rabbitmq-secret"
    namespace = "observability-prd"
  }
  data = {
    "rabbitmq-password"      = random_password.oncall_rabbitmq_password.result
    "rabbitmq-erlang-cookie" = "secretcookie_for_clustering"
  }
}

resource "kubernetes_secret_v1" "oncall_redis_secret" {
  metadata {
    name      = "oncall-redis-secret"
    namespace = "observability-prd"
  }
  data = {
    "redis-password" = random_password.oncall_redis_password.result
  }
}

# -------------------------------------------------------------------
# 3. INFRASTRUCTURE & APPS
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
    configs = {
      cm = {
        "resource.customizations.ignoreDifferences.all" = "jsonPointers:\n  - /status"
      }
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
  values = [yamlencode({
    metricLabelsAllowlist = ["pods=[*]", "deployments=[*]", "nodes=[*]"]
  })]
}

# LGTM Stack (Includes Bundled MinIO)
resource "kubectl_manifest" "lgtm" {
  depends_on = [
    kubernetes_secret_v1.minio_creds, 
    kubernetes_secret_v1.mimir_s3_creds,
    kubernetes_secret_v1.oncall_db_secret,
    kubernetes_secret_v1.oncall_rabbitmq_secret,
    kubernetes_secret_v1.oncall_redis_secret
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "lgtm"
      namespace = "argocd-system"
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
        chart          = "lgtm-distributed"
        targetRevision = "3.0.1"
        helm = {
          values = file("${path.module}/../k8s/values/lgtm.yaml")
        }
      }
    }
  })
}

# Alloy
resource "kubectl_manifest" "alloy" {
  depends_on = [kubectl_manifest.lgtm]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "alloy"
      namespace = "argocd-system"
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

# Astronomy Shop
resource "kubectl_manifest" "astronomy" {
  depends_on = [kubectl_manifest.alloy]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "astronomy-shop"
      namespace = "argocd-system"
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