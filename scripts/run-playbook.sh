#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run-playbook.sh [site|bootstrap|provisioning] [options] [-- ansible-playbook args]

Options:
  --ask-vault-pass              Prompt for Ansible Vault password
  --vault-password-file PATH    Use a vault password file
  -l, --limit PATTERN           Limit target hosts
  -t, --tags TAGS               Run only selected tags
  -h, --help                    Show this help

Examples:
  ./scripts/run-playbook.sh
  ./scripts/run-playbook.sh site
  ./scripts/run-playbook.sh site --vault-password-file .vault_pass.txt
  ./scripts/run-playbook.sh provisioning --ask-vault-pass -- -e common_packages='["git"]'
EOF
}

playbook="site.yml"
default_vault_password_file="${REPO_ROOT}/.vault_pass.txt"
vault_args=()
ansible_args=()
vault_option_explicitly_set=false

if [[ $# -gt 0 ]]; then
  case "$1" in
    site)
      playbook="site.yml"
      shift
      ;;
    bootstrap)
      playbook="bootstrap.yml"
      shift
      ;;
    provisioning)
      playbook="provisioning.yml"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ask-vault-pass)
      vault_args+=("$1")
      vault_option_explicitly_set=true
      shift
      ;;
    --vault-password-file)
      [[ $# -ge 2 ]] || {
        echo "Missing value for --vault-password-file" >&2
        exit 1
      }
      vault_args+=("$1" "$2")
      vault_option_explicitly_set=true
      shift 2
      ;;
    -l|--limit|-t|--tags)
      [[ $# -ge 2 ]] || {
        echo "Missing value for $1" >&2
        exit 1
      }
      ansible_args+=("$1" "$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      ansible_args+=("$@")
      break
      ;;
    *)
      ansible_args+=("$1")
      shift
      ;;
  esac
done

if [[ "${vault_option_explicitly_set}" == false ]]; then
  if [[ -f "${default_vault_password_file}" ]]; then
    vault_args=("--vault-password-file" "${default_vault_password_file}")
  else
    vault_args=("--ask-vault-pass")
  fi
fi

cd "${REPO_ROOT}"

exec ansible-playbook "${playbook}" "${vault_args[@]}" "${ansible_args[@]}"
