#!/usr/bin/env python3
"""
ssm-deploy.py — Upload bundle & execute deploy script on EC2 via SSM.

Usage: python ssm-deploy.py <ec2_id> <changed_services>
"""
import base64
import json
import os
import subprocess
import sys
import time


def aws_cmd(args, capture=True):
    """Run an AWS CLI command."""
    result = subprocess.run(
        ["aws"] + args,
        capture_output=capture, text=True
    )
    if result.returncode != 0 and capture:
        print(f"AWS CLI error: {result.stderr}", file=sys.stderr)
    return result


def send_ssm_command(ec2_id, commands, timeout=60):
    """Send an SSM command and return the command ID. Exits on failure."""
    result = aws_cmd([
        "ssm", "send-command",
        "--instance-ids", ec2_id,
        "--document-name", "AWS-RunShellScript",
        "--timeout-seconds", str(timeout),
        "--parameters", json.dumps({"commands": commands}),
        "--query", "Command.CommandId", "--output", "text"
    ])
    cmd_id = result.stdout.strip()
    if not cmd_id or len(cmd_id) < 36:
        print(f">>> SSM send-command failed! stderr: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return cmd_id


def create_bundle():
    """Create the deploy bundle tarball."""
    print(">>> Creating deploy bundle...")
    files = [
        "k8s/", "timescaledb/init.sql", "clean.sh",
        "services.json", "scripts/deploy.py"
    ]

    # Build tar command — include only files that exist
    tar_files = []
    for f in files:
        if os.path.exists(f):
            tar_files.append(f)

    # Also include .deploy-secrets from /tmp if it exists
    if os.path.exists("/tmp/.deploy-secrets"):
        tar_files.append("-C")
        tar_files.append("/tmp")
        tar_files.append(".deploy-secrets")

    subprocess.run(
        ["tar", "czf", "/tmp/deploy-bundle.tar.gz"] + tar_files,
        check=True
    )

    size = os.path.getsize("/tmp/deploy-bundle.tar.gz")
    print(f">>> Bundle size: {size} bytes")
    return size


def upload_via_s3(ec2_id, bucket):
    """Upload bundle to S3, then pull on EC2."""
    print(">>> Uploading to S3...")
    aws_cmd(["s3", "cp", "/tmp/deploy-bundle.tar.gz",
             f"s3://{bucket}/deploy/deploy-bundle.tar.gz"])

    return send_ssm_command(ec2_id, [
        "mkdir -p /home/ubuntu/k8s /home/ubuntu/timescaledb /home/ubuntu/scripts",
        f"aws s3 cp s3://{bucket}/deploy/deploy-bundle.tar.gz /tmp/deploy-bundle.tar.gz",
        "cd /home/ubuntu && tar xzf /tmp/deploy-bundle.tar.gz",
        "chmod +x /home/ubuntu/clean.sh",
        "rm -f /tmp/deploy-bundle.tar.gz"
    ])


def upload_inline(ec2_id):
    """Upload bundle inline via base64 in SSM command."""
    print(">>> Uploading inline via SSM...")
    with open("/tmp/deploy-bundle.tar.gz", "rb") as f:
        bundle_b64 = base64.b64encode(f.read()).decode()

    return send_ssm_command(ec2_id, [
        "mkdir -p /home/ubuntu/k8s /home/ubuntu/timescaledb /home/ubuntu/scripts",
        f"echo '{bundle_b64}' | base64 -d > /tmp/deploy-bundle.tar.gz",
        "cd /home/ubuntu && tar xzf /tmp/deploy-bundle.tar.gz",
        "chmod +x /home/ubuntu/clean.sh",
        "rm -f /tmp/deploy-bundle.tar.gz"
    ])


def wait_for_command(ec2_id, command_id):
    """Wait for SSM command to complete and return status."""
    aws_cmd(["ssm", "wait", "command-executed",
             "--command-id", command_id,
             "--instance-id", ec2_id], capture=False)

    result = aws_cmd([
        "ssm", "get-command-invocation",
        "--command-id", command_id,
        "--instance-id", ec2_id
    ])
    return json.loads(result.stdout)


def run_deploy(ec2_id, changed_services):
    """Execute deploy.py on EC2 via SSM."""
    print(f">>> Running deploy on EC2: {ec2_id}")
    return send_ssm_command(ec2_id, [
        f"cd /home/ubuntu && python3 scripts/deploy.py {changed_services}"
    ], timeout=300)


def main():
    ec2_id = sys.argv[1]
    changed = sys.argv[2] if len(sys.argv) > 2 else "all"
    bucket = os.environ.get("S3_BUCKET_NAME", "traffic-count-bigdata")

    print(f">>> Deploying to EC2: {ec2_id}")
    print(f">>> Services: {changed}")

    # 1. Create bundle
    bundle_size = create_bundle()

    # 2. Upload
    if bundle_size > 20000:
        cmd_id = upload_via_s3(ec2_id, bucket)
    else:
        cmd_id = upload_inline(ec2_id)

    # 3. Wait for upload
    invocation = wait_for_command(ec2_id, cmd_id)
    status = invocation.get("Status", "Unknown")
    if status != "Success":
        print(f">>> Upload failed: {status}")
        print(invocation.get("StandardErrorContent", ""))
        sys.exit(1)
    print(">>> Bundle uploaded successfully")

    # 4. Run deploy
    cmd_id = run_deploy(ec2_id, changed)
    print(f">>> SSM Command ID: {cmd_id}")
    print(">>> Waiting for deployment...")

    # 5. Wait and report
    invocation = wait_for_command(ec2_id, cmd_id)
    status = invocation.get("Status", "Unknown")
    print(f">>> Command Status: {status}")
    print("--- STDOUT ---")
    print(invocation.get("StandardOutputContent", ""))
    print("--- STDERR ---")
    print(invocation.get("StandardErrorContent", ""))

    if status != "Success":
        print(">>> Deployment failed!")
        sys.exit(1)

    print(">>> Deployment successful!")


if __name__ == "__main__":
    main()
