#!/bin/bash

# 引数に与えたファイルをansible-vaultで暗号化するスクリプト
# カレントディレクトリに .vault_pass.txt というファイルが存在すればそのファイルをパスワードファイルとして使用する
# 例: ./encrypt.sh group_vars/all.yml

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file_to_encrypt>"
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

# ansible-vaultで暗号化
ansible-vault encrypt $VAULT_PASSWORD_OPTION "$FILE_TO_ENCRYPT"
echo "File '$FILE_TO_ENCRYPT' has been encrypted."
