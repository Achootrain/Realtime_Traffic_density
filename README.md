# Traffic System: Deploy to EC2 (K3s) via GitHub Actions

This guide walks through deploying Kafka producer, Spark app, TimescaleDB, Grafana, and MinIO to your EC2-hosted K3s cluster using the provided GitHub Actions workflow.

## Prerequisites
- EC2 instance with K3s installed and `kubectl` configured (the workflow copies `/etc/rancher/k3s/k3s.yaml` for the `ubuntu` user).
- Docker installed on the EC2 instance (for pulling GHCR images required by cluster nodes when using containerd, ensure nodes can pull from GHCR).
- Repository access with GitHub Actions enabled.
- Required files present:
  - Kubernetes manifests in `k8s/`
  - Dockerfiles and app sources in `kafka/` and `spark/`
  - Workflow: `.github/workflows/aws-ec2-deploy.yml`

## Secrets to Configure (GitHub)
Set the following repository secrets:
- `EC2_HOST`: Public IP or DNS of EC2 (used to SSH and Kafka external announcements if needed)
- `EC2_USER`: SSH username (e.g., `ubuntu`)
- `EC2_SSH_KEY`: Private key for SSH (PEM content)
- `GHCR_USERNAME`: GitHub username that can read the package (often your username)
- `GHCR_TOKEN`: GitHub Personal Access Token with `read:packages` (and `repo` if the image is private)
- Optional:
  - `KAFKA_BOOTSTRAP_SERVERS`: If needed by external components (usually in-cluster Service is used)
  - `POSTGRES_PASSWORD`: If you override DB password via manifests (default in manifests is `postgres`)

## What the Workflow Does
- Chooses service (`kafka` or `spark`) to build based on dispatch input or repo changes.
- Uses prebuilt Docker Hub images:
  - `docker.io/achootrain/kafka-producer:latest`
  - `docker.io/achootrain/spark-application:latest`
- Copies all Kubernetes manifests from `k8s/` to `/home/ubuntu/k8s/` on EC2.
- SSH into EC2 and runs:
  - Grants `kubectl` access for `ubuntu` using K3s config.
  - Replaces placeholders in YAMLs:
    - `IP_PLACEHOLDER` -> `EC2_HOST`
    - `GITHUB_USER_PLACEHOLDER` -> repo owner (lowercased)
  - Creates namespace `traffic` if missing.
  - Applies all manifests using Kustomize: `kubectl apply -k /home/ubuntu/k8s`
    - Image names are pinned in Kustomize; no username substitution.

## Run a Deployment
### Option A: From a Commit to `main`
- Push changes to `kafka/` or `spark/` to `main`.
- The workflow builds the changed service image and deploys.

### Option B: Manual Dispatch (Recommended)
1. Go to GitHub → Actions → "Build & Deploy to GHCR (K3s)".
2. Click "Run workflow".
3. Choose `service`: `kafka` or `spark`.
4. Run. The workflow will:
   - Build & push the selected image to GHCR.
   - Apply K8s manifests on EC2 K3s.

## Verify Deployment
- Namespace: `traffic`.
- Kafka: `statefulset/kafka` and `service/kafka`.
- TimescaleDB: `statefulset/timescaledb` and `service/timescaledb`.
- Grafana: ConfigMaps + Deployment/Service (ensure grafana Deployment is present in `grafana.yaml`).
- Spark: Operator RBAC and application manifests.

Commands (from your local with kubeconfig to the cluster or via EC2):
```bash
kubectl get all -n traffic
kubectl logs -n traffic statefulset/kafka -c kafka --tail=200
kubectl logs -n traffic deployment/<spark-deployment-or-pod> --tail=200
kubectl logs -n traffic statefulset/timescaledb --tail=200
```

## Pulling Private GHCR Images (Spark)
If `ghcr.io/achootrain/spark-application:latest` is private, the workflow will auto-create/update a registry secret named `ghcr-secret` in the `traffic` namespace using `GHCR_USERNAME` and `GHCR_TOKEN`.

```bash
kubectl create secret docker-registry ghcr-secret \
  -n traffic \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GHCR_TOKEN \
  --docker-email=YOUR_EMAIL
```

The Spark manifests already reference this via `imagePullSecrets`.

## Image References
- Kustomize remaps image names found in manifests to:
  - `docker.io/achootrain/kafka-producer:latest`
  - `docker.io/achootrain/spark-application:latest`
- Kustomize pins `latest` tag by default. To deploy a specific commit:
  - Update `kustomization.yaml` `images.newTag` to `${{ github.sha }}` via sed in the workflow.

## Kafka Topic and Connectivity
- Producer sends to topic `hugedata`.
- Spark reads topic `hugedata`.
- In-cluster bootstrap suggested: `kafka.traffic.svc.cluster.local:9092`.
- For external producer on EC2, configure Kafka advertised listeners to use `EC2_HOST` and expose a NodePort; update `KAFKA_BOOTSTRAP_SERVERS` accordingly.

## TimescaleDB and Grafana
- TimescaleDB Service: `timescaledb.traffic.svc.cluster.local:5432`, DB `traffic`, user `postgres`.
- Grafana datasource preconfigured to the TimescaleDB service.
- Consider setting a stronger Grafana admin password via a Secret and env.

## Troubleshooting
- Permissions: Ensure `ubuntu` can read `~/.kube/config` (workflow sets file perms).
- CRDs: Install Spark Operator before applying `SparkApplication` manifests.
- JDBC: Ensure Spark image contains PostgreSQL JDBC driver in `spark/jars/`.
- Checkpoints: Mount a PVC at `/app/data` in Spark if you need persistent state.

## Clean Up
```bash
kubectl delete namespace traffic
```

## Notes
- Adjust resource requests/limits in manifests as needed for your EC2 size.
- Use GHCR "latest" for simplicity; for production, prefer immutable tags.
