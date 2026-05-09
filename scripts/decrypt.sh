#!/bin/bash

# 引数に与えたファイルをansible-vaultで復号化するスクリプト
# カレントディレクトリに .vault_pass.txt というファイルが存在すればそのファイルをパスワードファイルとして使用する
# 例: ./decrypt.sh group_vars/all.yml

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

# ansible-vaultで復号化
ansible-vault decrypt $VAULT_PASSWORD_OPTION "$FILE_TO_ENCRYPT"
echo "File '$FILE_TO_ENCRYPT' has been decrypted."
