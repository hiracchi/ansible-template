#!/bin/bash

# ファイル全体が ansible-vault で暗号化されたファイルを、復号せずに閲覧するスクリプト
# カレントディレクトリに .vault_password があればそのファイルをパスワードファイルとして使用する
# 例: ./scripts/view.sh inventory/bootstrap.yml

if [ $# -eq 0 ]; then
    echo "Usage: $0 <vault_encrypted_file>"
    exit 1
fi

FILE_TO_ENCRYPT="$1"
ANSIBLE_VAULT_PASSWORD_FILE=".vault_password"

if [ ! -f "$FILE_TO_ENCRYPT" ]; then
    echo "Error: File '$FILE_TO_ENCRYPT' does not exist."
    exit 1
fi

VAULT_PASSWORD_OPTION=""
if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
    VAULT_PASSWORD_OPTION="--vault-password-file $ANSIBLE_VAULT_PASSWORD_FILE"
fi

# ansible-vaultで復号化
ansible-vault view $VAULT_PASSWORD_OPTION "$FILE_TO_ENCRYPT"
