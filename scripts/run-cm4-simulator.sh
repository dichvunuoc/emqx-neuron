#!/usr/bin/env bash
set -euo pipefail

echo "Docker CM4 simulator has been removed to avoid deployment confusion."
echo "Use native flow instead:"
echo "  scripts/cm4-one-command-setup.sh --repo <git-url> --branch <branch> --enable-service"
exit 1
