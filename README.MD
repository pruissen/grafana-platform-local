# Platform Engineering Lab: Grafana Enterprise Stack on MicroK8s

This project creates a local Multi-tenant Observability Platform using MicroK8s, ArgoCD, and the Grafana Stack (Mimir, Loki, Tempo, Grafana, Faro).

## Components
- **Orchestration**: MicroK8s (Local K8s)
- **GitOps**: ArgoCD
- **Observability**: Grafana LGTM Stack (Distributed Mode) + K6 + Faro
- **Telemetry**: OpenTelemetry Collectors (Gateway + DaemonSet)
- **Demo App**: OpenTelemetry Astronomy Shop

## Prerequisites
- Ubuntu/Linux environment
- `git`, `make`, `curl`, `screen` installed.
- **Important**: You must manually initialize this folder as a git repository and commit the files before running the installation.

## Quick Start

1. **Launch Everything**:
   ```bash
   make all