#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run-playbook.sh [target ...] [options] [-- ansible-playbook args]

Options:
  --site                         Run site.yml (default)
  --bootstrap-only               Run bootstrap.yml only
  --provisioning-only            Run provisioning.yml only
  --ask-vault-pass              Prompt for Ansible Vault password
  --vault-password-file PATH    Use a vault password file
  -l, --limit PATTERN           Limit target hosts
  -t, --tags TAGS               Run only selected tags
  -h, --help                    Show this help

Examples:
  ./scripts/run-playbook.sh
  ./scripts/run-playbook.sh web01
  ./scripts/run-playbook.sh web,db
  ./scripts/run-playbook.sh web01 db
  ./scripts/run-playbook.sh --site
  ./scripts/run-playbook.sh --bootstrap-only
  ./scripts/run-playbook.sh --provisioning-only
  ./scripts/run-playbook.sh --site --vault-password-file .vault_pass.txt
  ./scripts/run-playbook.sh --provisioning-only --ask-vault-pass -- -e common_packages='["git"]'
EOF
}

playbook="site.yml"
default_vault_password_file="${REPO_ROOT}/.vault_pass.txt"
vault_args=()
ansible_args=()
target_patterns=()
vault_option_explicitly_set=false
playbook_option_count=0
limit_option_explicitly_set=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site)
      playbook="site.yml"
      playbook_option_count=$((playbook_option_count + 1))
      shift
      ;;
    --bootstrap-only)
      playbook="bootstrap.yml"
      playbook_option_count=$((playbook_option_count + 1))
      shift
      ;;
    --provisioning-only)
      playbook="provisioning.yml"
      playbook_option_count=$((playbook_option_count + 1))
      shift
      ;;
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
      if [[ "$1" == "-l" || "$1" == "--limit" ]]; then
        limit_option_explicitly_set=true
      fi
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
    site|bootstrap|provisioning)
      echo "Positional playbook selector '$1' is no longer supported. Use --site, --bootstrap-only, or --provisioning-only." >&2
      exit 1
      ;;
    *)
      target_patterns+=("$1")
      shift
      ;;
  esac
done

if [[ ${playbook_option_count} -gt 1 ]]; then
  echo "Specify only one of --site, --bootstrap-only, or --provisioning-only." >&2
  exit 1
fi

if [[ ${#target_patterns[@]} -gt 0 ]]; then
  if [[ "${limit_option_explicitly_set}" == true ]]; then
    echo "Do not combine target positional arguments with -l/--limit. Use either one." >&2
    exit 1
  fi
  limit_pattern=$(IFS=,; echo "${target_patterns[*]}")
  ansible_args+=("--limit" "${limit_pattern}")
fi

if [[ "${vault_option_explicitly_set}" == false ]]; then
  if [[ -f "${default_vault_password_file}" ]]; then
    vault_args=("--vault-password-file" "${default_vault_password_file}")
  else
    vault_args=("--ask-vault-pass")
  fi
fi

cd "${REPO_ROOT}"

exec ansible-playbook "${playbook}" "${vault_args[@]}" "${ansible_args[@]}"
