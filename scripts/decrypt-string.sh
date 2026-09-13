#!/bin/bash

# group_vars/all.yml 内の Vault 暗号化された値(password など)を復号して
# 表示するスクリプト。ファイル全体ではなく特定の変数だけを暗号化する運用
# (scripts/encrypt-string.sh)のため、ansible-vault view/decrypt は
# このファイルには使えない(先頭が Vault ヘッダーではないため)。
# カレントディレクトリに .vault_password というファイルが存在すればそのファイルをパスワードファイルとして使用する
# 例: ./scripts/decrypt-string.sh provisioning_user.password

if [ $# -eq 0 ]; then
    echo "Usage: $0 <variable_path>"
    echo "  e.g. $0 provisioning_user.password"
    exit 1
fi

VAR_PATH="$1"
ANSIBLE_VAULT_PASSWORD_FILE=".vault_password"

VAULT_PASSWORD_OPTION="--ask-vault-pass"
if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
    VAULT_PASSWORD_OPTION="--vault-password-file $ANSIBLE_VAULT_PASSWORD_FILE"
fi

ansible localhost -m debug -a "msg={{ ${VAR_PATH} }}" -e @group_vars/all.yml $VAULT_PASSWORD_OPTION
