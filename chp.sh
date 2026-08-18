#!/bin/bash

set -e

PROVIDER=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -g|--github) PROVIDER="github"; shift ;;
        -k|--keycloak) PROVIDER="keycloak-oidc"; shift ;;
        *) echo "Unknown parameter passed: $1"; show_help; exit 1 ;;
    esac
done


if [ -z "$PROVIDER" ]; then
    echo "Error: You must specify a provider."
    show_help
    exit 1
fi

VARS_FILE="ansible/vars/main.yml"
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

cd "$WORKSPACE_DIR"

if [ ! -f "$VARS_FILE" ]; then
    echo "Error: Cannot find $VARS_FILE."
    exit 1
fi

echo "Switching OAuth provider to: $PROVIDER..."

if sed --version >/dev/null 2>&1; then
  sed -i "s/^oauth_provider:.*/oauth_provider: \"$PROVIDER\"/" "$VARS_FILE"
else
  sed -i '' "s/^oauth_provider:.*/oauth_provider: \"$PROVIDER\"/" "$VARS_FILE"
fi

echo "Provider updated in $VARS_FILE."
echo "Running Ansible playbook to deploy changes to the server..."

cd ansible
ansible-playbook -i inventory/hosts.ini playbook.yml --tags "oauth2"

echo "The OAuth provider is now set to '$PROVIDER'."
