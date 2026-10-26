#!/bin/bash

# 引数に与えたファイル全体を ansible-vault で decrypt するスクリプト
# カレントディレクトリに .vault_password があればそのファイルをパスワードファイルとして使う
# 例: ./scripts/decrypt-file.sh inventory/bootstrap.yml

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file>"
    exit 1
fi

FILE="$1"
ANSIBLE_VAULT_PASSWORD_FILE=".vault_password"

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' does not exist."
    exit 1
fi

VAULT_PASSWORD_OPTION=""
if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
    VAULT_PASSWORD_OPTION="--vault-password-file $ANSIBLE_VAULT_PASSWORD_FILE"
fi

# 失敗時は終了コードを返す(成功時のみ完了メッセージを出す)
if ansible-vault decrypt $VAULT_PASSWORD_OPTION "$FILE"; then
    echo "File '$FILE' has been decrypted."
else
    echo "Error: failed to decrypt '$FILE'. (ファイル全体が vault 形式か確認してください)"
    exit 1
fi
