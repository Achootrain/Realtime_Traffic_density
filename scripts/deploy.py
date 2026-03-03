#!/usr/bin/env python3
"""
deploy.py — Runs ON the EC2 instance.
Deploys K8s services via kubectl/helm, driven by services.json.

Usage: python3 deploy.py <changed_services>
  changed_services: comma-separated list or "all"

Env vars (set by .deploy-secrets):
  GHCR_USERNAME, GHCR_TOKEN
  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
"""
import json
import os
import subprocess
import sys


def run(cmd, check=False, shell=True):
    """Run a shell command, print it, return success."""
    print(f"    $ {cmd}")
    result = subprocess.run(cmd, shell=shell, capture_output=False)
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}")
    return result.returncode == 0


def load_config():
    """Load services.json."""
    config_path = "/home/ubuntu/services.json"
    with open(config_path, "r") as f:
        return json.load(f)


def setup_kafka_ip():
    """Resolve EC2 public IP via IMDSv2 and patch kafka.yaml."""
    print(">>> Resolving EC2 public IP (IMDSv2)...")
    try:
        token = subprocess.run(
            ["curl", "-sf", "-X", "PUT",
             "http://169.254.169.254/latest/api/token",
             "-H", "X-aws-ec2-metadata-token-ttl-seconds: 60"],
            capture_output=True, text=True, timeout=5
        ).stdout.strip()

        ip = subprocess.run(
            ["curl", "-sf", "-H", f"X-aws-ec2-metadata-token: {token}",
             "http://169.254.169.254/latest/meta-data/public-ipv4"],
            capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except Exception:
        ip = "127.0.0.1"

    ip = ip or "127.0.0.1"
    print(f"    EC2 IP: {ip}")
    run(f"sed -i 's/IP_PLACEHOLDER/{ip}/g' kafka.yaml || true")


def setup_helm(config):
    """Install Helm and add repos from config."""
    print(">>> Setting up Helm...")
    run("command -v helm &>/dev/null || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash")

    for name, url in config.get("helm_repos", {}).items():
        run(f'helm repo add "{name}" "{url}" || true')
    run("helm repo update")


def create_namespace():
    print(">>> Creating namespace...")
    run("kubectl create namespace traffic --dry-run=client -o yaml | kubectl apply -f -")


def create_secrets():
    """Create K8s secrets from env vars."""
    print(">>> Creating secrets...")

    # Load deploy secrets file into env vars
    secrets_file = "/home/ubuntu/.deploy-secrets"
    if os.path.exists(secrets_file):
        with open(secrets_file, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("export ") and "=" in line:
                    # Parse: export KEY="VALUE"
                    kv = line[len("export "):]
                    key, _, value = kv.partition("=")
                    value = value.strip('"').strip("'")
                    os.environ[key] = value

    ghcr_user = os.environ.get("GHCR_USERNAME", "")
    ghcr_token = os.environ.get("GHCR_TOKEN", "")
    aws_key = os.environ.get("AWS_ACCESS_KEY_ID", "")
    aws_secret = os.environ.get("AWS_SECRET_ACCESS_KEY", "")

    run(f'kubectl create secret docker-registry ghcr-secret '
        f'--namespace traffic --docker-server=ghcr.io '
        f'--docker-username="{ghcr_user}" --docker-password="{ghcr_token}" '
        f'--docker-email="noreply@example.com" '
        f'--dry-run=client -o yaml | kubectl apply -f -')

    run(f'kubectl create secret generic aws-credentials '
        f'--namespace traffic '
        f'--from-literal=access_key_id="{aws_key}" '
        f'--from-literal=secret_access_key="{aws_secret}" '
        f'--dry-run=client -o yaml | kubectl apply -f -')


def install_helm_releases(config):
    """Install/upgrade Helm releases from config."""
    for release in config.get("helm_releases", []):
        name = release["name"]
        chart = release["chart"]
        set_flags = " ".join(
            f'--set {k}={v}' for k, v in release.get("set", {}).items()
        )
        print(f">>> Installing Helm release: {name}")
        run(f'helm upgrade --install "{name}" "{chart}" --namespace traffic {set_flags}')


def apply_manifests():
    print(">>> Applying manifests via Kustomize...")
    run("kubectl apply -k .", check=True)


def init_timescaledb():
    print(">>> Initializing TimescaleDB...")
    run("kubectl wait --for=condition=ready pod/timescaledb-0 -n traffic --timeout=120s || true")
    if os.path.exists("/home/ubuntu/timescaledb/init.sql"):
        run("kubectl cp /home/ubuntu/timescaledb/init.sql traffic/timescaledb-0:/tmp/init.sql")
        run("kubectl exec timescaledb-0 -n traffic -- psql -U postgres -d traffic -f /tmp/init.sql || true")


def restart_services(config, changed_services):
    """Restart services based on what changed."""
    print(f">>> Restarting services: {changed_services}")

    for svc in config.get("services", []):
        name = svc["name"]
        should_restart = (
            changed_services == "all" or
            name in changed_services.split(",")
        )

        if should_restart:
            print(f">>> Restarting: {name}")
            for cmd in svc.get("restart", []):
                run(cmd)


def main():
    changed_services = sys.argv[1] if len(sys.argv) > 1 else "all"
    print(f">>> Deploy starting — services: {changed_services}")

    os.environ["KUBECONFIG"] = "/home/ubuntu/.kube/config"
    os.environ["HOME"] = "/home/ubuntu"
    os.chdir("/home/ubuntu/k8s")

    config = load_config()

    setup_kafka_ip()
    setup_helm(config)
    create_namespace()
    create_secrets()
    install_helm_releases(config)
    apply_manifests()
    init_timescaledb()
    restart_services(config, changed_services)

    print(">>> Deploy complete!")


if __name__ == "__main__":
    main()
