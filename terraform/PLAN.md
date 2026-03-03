# Terraform Infrastructure Plan — Traffic System

## Overview

This plan converts the manually-deployed AWS infrastructure (currently managed via GitHub Actions SSH + kubectl) into reproducible **Terraform Infrastructure as Code**.

---

## Current Architecture (Reverse-Engineered)

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud (us-east-1)                   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    VPC (10.0.0.0/16)                     │   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────────┐     │   │
│  │  │         Public Subnet (10.0.1.0/24)             │     │   │
│  │  │                                                 │     │   │
│  │  │  ┌───────────────────────────────────────────┐  │     │   │
│  │  │  │         EC2 Instance (Ubuntu)             │  │     │   │
│  │  │  │              K3s Cluster                   │  │     │   │
│  │  │  │                                           │  │     │   │
│  │  │  │  namespace: traffic                       │  │     │   │
│  │  │  │  ├── Kafka (StatefulSet, 5Gi PVC)         │  │     │   │
│  │  │  │  ├── Kafka Producer (Deployment, YOLO)    │  │     │   │
│  │  │  │  ├── TimescaleDB (StatefulSet, 10Gi PVC)  │  │     │   │
│  │  │  │  ├── Grafana (Deployment, NodePort:3000)  │  │     │   │
│  │  │  │  ├── Spark Operator (Helm)                │  │     │   │
│  │  │  │  ├── Spark Realtime (Kafka→TimescaleDB)   │  │     │   │
│  │  │  │  └── Spark S3 Glacier (Kafka→S3)          │  │     │   │
│  │  │  └───────────────────────────────────────────┘  │     │   │
│  │  └─────────────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │   S3 Bucket       │  │   AWS Athena      │                   │
│  │   traffic-count-  │  │   DB: traffic_    │                   │
│  │   bigdata         │  │   analytics       │                   │
│  │   + /athena_      │  │   Table: traffic_ │                   │
│  │     results/      │  │   stream          │                   │
│  └──────────────────┘  └──────────────────┘                     │
│                                                                 │
│  ┌──────────────────┐                                           │
│  │  AWS Glue Catalog │  (backing Athena AwsDataCatalog)         │
│  └──────────────────┘                                           │
│                                                                 │
│  ┌──────────────────┐                                           │
│  │   IAM Role/User   │  (for Spark S3 access + Grafana Athena) │
│  └──────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Terraform Modules Breakdown

### Module 1: `network` — VPC & Networking
| Resource | Description |
|---|---|
| `aws_vpc` | VPC `10.0.0.0/16` |
| `aws_subnet` (public) | Public subnet `10.0.1.0/24` with auto-assign public IP |
| `aws_internet_gateway` | Internet access for EC2 |
| `aws_route_table` + association | Route `0.0.0.0/0` → IGW |
| `aws_security_group` | Inbound: SSH(22), Grafana(3000), K3s API(6443), Kafka external(9094). Outbound: all |

### Module 2: `compute` — EC2 + K3s
| Resource | Description |
|---|---|
| `aws_key_pair` | SSH key for EC2 access (public key from variable) |
| `aws_instance` | Ubuntu 22.04 LTS, instance type configurable (default: `m7i-flex.large`), 40GB gp3 root volume. User-data script installs K3s automatically |
| `null_resource` (provisioner) | Waits for K3s readiness after boot |

### Module 3: `storage` — S3
| Resource | Description |
|---|---|
| `aws_s3_bucket` | `traffic-count-bigdata` |
| `aws_s3_bucket_lifecycle_configuration` | Lifecycle rules (transition to Glacier after N days, matching current S3 Glacier app usage) |
| `aws_s3_bucket_public_access_block` | Block all public access |

### Module 4: `analytics` — Athena & Glue
| Resource | Description |
|---|---|
| `aws_glue_catalog_database` | `traffic_analytics` |
| `aws_glue_catalog_table` | `traffic_stream` — schema matching S3 Parquet data |
| `aws_athena_workgroup` | `primary` workgroup with S3 output location |

### Module 5: `iam` — IAM Roles & Policies
| Resource | Description |
|---|---|
| `aws_iam_user` | Service user for Spark + Grafana |
| `aws_iam_access_key` | Programmatic access key (stored in Terraform state, use with caution) |
| `aws_iam_user_policy` | Inline policy: S3 read/write on `traffic-count-bigdata`, Athena query access, Glue catalog access |

### Module 6: `k3s_apps` — K8s Workloads (via Terraform K8s/Helm providers)
| Resource | Description |
|---|---|
| Kubernetes provider | Connects to K3s via SSH tunnel or kubeconfig |
| `kubernetes_namespace` | `traffic` |
| `kubernetes_secret` | `aws-credentials`, `ghcr-secret` |
| `helm_release` | Spark Operator |
| `kubectl_manifest` / `kubernetes_manifest` | All K8s manifests (Kafka, Producer, TimescaleDB, Grafana, Spark apps, RBAC) |

---

## File Structure

```
terraform/
├── PLAN.md                    # ← This file
├── main.tf                    # Root module: wires all modules together
├── variables.tf               # Input variables (instance type, region, SSH key, etc.)
├── outputs.tf                 # Outputs (EC2 IP, S3 bucket name, etc.)
├── terraform.tfvars.example   # Example variable values (DO NOT commit real secrets)
├── versions.tf                # Provider version constraints
│
├── modules/
│   ├── network/
│   │   ├── main.tf            # VPC, subnet, IGW, route table, security group
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── compute/
│   │   ├── main.tf            # EC2 instance + K3s user-data installation
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── userdata.sh        # K3s install + initial setup script
│   │
│   ├── storage/
│   │   ├── main.tf            # S3 bucket + lifecycle + access block
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── analytics/
│   │   ├── main.tf            # Glue catalog DB/table + Athena workgroup
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── iam/
│   │   ├── main.tf            # IAM user + policy + access key
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── k3s_apps/
│       ├── main.tf            # K8s namespace, secrets, Helm (Spark Operator)
│       ├── manifests.tf       # kubectl_manifest for all K8s YAML resources
│       ├── variables.tf
│       └── outputs.tf
```

---

## Variables (User Input Required)

| Variable | Type | Description | Default |
|---|---|---|---|
| `aws_region` | string | AWS region | `us-east-1` |
| `project_name` | string | Project name prefix | `traffic-system` |
| `instance_type` | string | EC2 instance type | `m7i-flex.large` |
| `ssh_public_key` | string | SSH public key content for EC2 access | — (required) |
| `ssh_private_key_path` | string | Path to private key (for provisioners) | — (required) |
| `s3_bucket_name` | string | S3 bucket name | `traffic-count-bigdata` |
| `ghcr_username` | string | GitHub Container Registry username | — (required) |
| `ghcr_token` | string | GHCR personal access token | — (sensitive, required) |
| `glacier_transition_days` | number | Days before S3 → Glacier transition | `30` |
| `grafana_admin_password` | string | Grafana admin password | — (sensitive, default: `admin`) |
| `allowed_ssh_cidrs` | list(string) | CIDRs allowed to SSH | `["0.0.0.0/0"]` |

---

## Deployment Flow

```
terraform init          # Download providers (AWS, Kubernetes, Helm, kubectl)
terraform plan          # Preview all resources to create
terraform apply         # Create infrastructure in order:
                        #   1. VPC + Networking
                        #   2. IAM user + keys  
                        #   3. S3 bucket
                        #   4. Athena + Glue
                        #   5. EC2 + K3s install (user-data)
                        #   6. Wait for K3s ready
                        #   7. Deploy K8s workloads (namespace, secrets, Helm, manifests)
terraform destroy       # Tear down everything (reverse order)
```

---

## Key Design Decisions

### 1. K3s on EC2 (not EKS)
Your current setup uses K3s on a single EC2 instance. This is cost-effective for a dev/staging environment. Terraform will reproduce this exactly — **not** migrate to EKS.

### 2. K8s manifests deployed via Terraform
Instead of SSH + kubectl (as in GitHub Actions), Terraform will use the `kubernetes` and `helm` providers to apply manifests declaratively. The kubeconfig is fetched from the EC2 instance after K3s boots.

### 3. Secrets handling
- AWS credentials → created by Terraform IAM module, injected as K8s secrets
- GHCR credentials → passed as Terraform variables, injected as K8s `docker-registry` secret
- **No secrets stored in YAML files** — all injected at apply time

### 4. S3 bucket lifecycle
The S3 Glacier app writes data with a configurable storage class. Terraform also sets a lifecycle rule to transition older objects to Glacier automatically.

### 5. Athena/Glue
Terraform creates the Glue catalog database + table schema to match the Parquet data written by Spark. The Athena workgroup is configured with the S3 output location.

---

## What Changes vs. Current Setup

| Aspect | Current (GitHub Actions) | Terraform |
|---|---|---|
| EC2 creation | Manual / pre-existing | Automated |
| VPC/networking | Manual / default VPC | Explicit VPC with proper security group |
| K3s install | Manual on server | User-data script on EC2 boot |
| K8s manifests | `kubectl apply` via SSH | `kubernetes_manifest` provider |
| Spark Operator | `helm upgrade --install` via SSH | `helm_release` resource |
| S3 bucket | Manual creation | `aws_s3_bucket` resource |
| Athena/Glue | Manual setup | `aws_glue_*` + `aws_athena_*` resources |
| IAM credentials | Manual IAM user | `aws_iam_user` + auto-generated keys |
| Secrets | GitHub Secrets → kubectl create | Terraform variables → K8s secrets |
| Reproducibility | Partial (only deploy step) | **Full** (infra + app in one `terraform apply`) |

---

## Notes & Caveats

1. **State management**: For production, use a remote backend (S3 + DynamoDB). The initial setup uses local state.
2. **TimescaleDB init.sql**: Executed via `null_resource` provisioner after the pod is ready.
3. **Grafana dashboards**: The full JSON dashboard configs are embedded in the K8s ConfigMap (as they are today).
4. **Cost estimate**: ~$60-70/month for `m7i-flex.large` (2 vCPU, 8GB RAM) + 40GB gp3 + S3 + Athena queries (pay-per-query).
5. **GitHub Actions workflow**: After Terraform, the CI/CD workflow can be simplified to only build+push images and `kubectl rollout restart` — no more infrastructure setup in CI.

---

## Ready to Implement?

Review this plan and confirm. I will then generate all Terraform files matching this structure.
