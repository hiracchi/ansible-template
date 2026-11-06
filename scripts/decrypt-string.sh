#!/bin/bash

# group_vars/all.yml 内の Vault 暗号化された値(password など)を復号して
# 表示するスクリプト。ファイル全体ではなく特定の変数だけを暗号化する運用
# (scripts/encrypt-string.sh)のため、ansible-vault view/decrypt は
# このファイルには使えない(先頭が Vault ヘッダーではないため)。
# カレントディレクトリに .vault_password というファイルが存在すればそのファイルをパスワードファイルとして使用する
# 例: ./scripts/decrypt-string.sh provisioning_user.password
#     ./scripts/decrypt-string.sh my_users.toshi.password   (my_users は user: 名 で引く)

usage() {
    echo "Usage: $0 <variable_path>"
    echo "  e.g. $0 provisioning_user.password"
    echo "       $0 my_users.toshi.password     (my_users は user が toshi の項目)"
    echo "       $0 'my_users[0].password'      (リストは [番号] でも指定可)"
    echo "復号した値は平文で画面に表示されます。"
}

case "${1:-}" in
    "" | -h | --help)
        usage
        [ $# -eq 0 ] && exit 1
        exit 0
        ;;
esac

VAR_PATH="$1"
ANSIBLE_VAULT_PASSWORD_FILE=".vault_password"

VAULT_PASSWORD_OPTION="--ask-vault-pass"
if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
    VAULT_PASSWORD_OPTION="--vault-password-file $ANSIBLE_VAULT_PASSWORD_FILE"
fi

# my_users.<name>.<key> は「user: <name>」の項目として解決する(my_users はリストのため)
if [[ "$VAR_PATH" =~ ^my_users\.([^.]+)\.([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
    EXPR="(my_users | selectattr('user', 'equalto', '${BASH_REMATCH[1]}') | first).${BASH_REMATCH[2]}"
else
    EXPR="${VAR_PATH}"
fi

ansible localhost -m debug -a "msg={{ ${EXPR} }}" -e @group_vars/all.yml $VAULT_PASSWORD_OPTION
