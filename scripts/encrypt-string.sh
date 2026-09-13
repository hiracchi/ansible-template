#!/bin/bash

# ファイル全体ではなく特定の値だけを ansible-vault でインライン暗号化
# (`変数名: !vault |` 形式)するスクリプト。出力をそのまま該当行と
# 置き換えて使う(例: group_vars/all.yml の provisioning_user.password)。
# 平文はプロンプトで隠し入力するため、シェル履歴等に残らない。
# カレントディレクトリに .vault_password というファイルが存在すればそのファイルをパスワードファイルとして使用する
# 例: ./scripts/encrypt-string.sh password

if [ $# -eq 0 ]; then
    echo "Usage: $0 <variable_name>"
    exit 1
fi

VAR_NAME="$1"
ANSIBLE_VAULT_PASSWORD_FILE=".vault_password"

VAULT_PASSWORD_OPTION="--ask-vault-pass"
if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
    VAULT_PASSWORD_OPTION="--vault-password-file $ANSIBLE_VAULT_PASSWORD_FILE"
fi

# ansible-vaultでインライン暗号化(--promptで平文を隠し入力)
ansible-vault encrypt_string $VAULT_PASSWORD_OPTION --name "$VAR_NAME" --prompt
