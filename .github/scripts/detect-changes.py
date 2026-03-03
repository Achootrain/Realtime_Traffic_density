#!/usr/bin/env python3
"""
detect-changes.py
Detects which services changed based on git diff and services.json.

Usage: python detect-changes.py [manual_service]
Output: writes "services=..." to $GITHUB_OUTPUT
"""
import json
import os
import subprocess
import sys


def get_changed_files():
    """Get list of changed files from git diff."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD^", "HEAD"],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip().splitlines()
    except subprocess.CalledProcessError:
        return []


def load_services():
    """Load services.json config."""
    with open("services.json", "r") as f:
        return json.load(f)


def detect_changed_services(changed_files, services):
    """Match changed files to service source_dirs."""
    changed = []

    for svc in services:
        src_dir = svc["source_dir"]
        if any(f.startswith(src_dir) for f in changed_files):
            changed.append(svc["name"])

    # If k8s/ manifests changed, deploy all
    if any(f.startswith("k8s/") for f in changed_files):
        return "all"

    return ",".join(changed) if changed else "all"


def main():
    manual_service = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""

    if manual_service:
        result = manual_service
        print(f">>> Manual target: {result}")
    else:
        config = load_services()
        changed_files = get_changed_files()
        result = detect_changed_services(changed_files, config["services"])
        print(f">>> Auto-detected: {result}")

    # Write to GitHub Actions output
    github_output = os.environ.get("GITHUB_OUTPUT", "")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"services={result}\n")
    else:
        print(f"services={result}")


if __name__ == "__main__":
    main()
