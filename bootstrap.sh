#!/bin/bash

# 新規ホストを初期化する(provisioning ユーザーの作成、SSH 鍵配置、sudoers 設定)。
# 接続は inventory/bootstrap.yml の初期ユーザーで行う。
# 初期化済み(pdfansible で接続できる)ホストには実行しない。
#
# 例: ./bootstrap.sh liva
#     ./bootstrap.sh liva jarvis-z3-04   (複数指定可)

export LC_ALL=C.UTF-8
export ANSIBLE_STDOUT_CALLBACK=debug

if [ $# -eq 0 ]; then
    echo "Usage: $0 <host> [host ...]"
    echo "新規ホストの初期化に使います。グループ名は指定できません。"
    exit 1
fi

ASK_VAULT_PASS="--ask-vault-pass"
ASK_BECOME_PASS=""

if [ "${BOOTSTRAP_ASK_BECOME_PASS:-0}" = "1" ]; then
    ASK_BECOME_PASS="--ask-become-pass"
fi

if [ -f ./.vault_password ]; then
    ASK_VAULT_PASS="--vault-password-file ./.vault_password"
fi

LIMIT=$(IFS=,; echo "$*")

# 既に provisioning ユーザーで接続できるホストは初期化済みとみなし、拒否する
for host in "$@"; do
    if ansible "${host}" \
        -i inventory/hosts.yml \
        --extra-vars="@inventory/provisioning.yml" \
        ${ASK_VAULT_PASS} \
        -m ansible.builtin.ping > /dev/null 2>&1; then
        echo "${host} は provisioning ユーザーで接続できるため初期化済みです。中止します。"
        exit 1
    fi
done

ansible-playbook \
    ${ASK_VAULT_PASS} \
    -i inventory/hosts.yml \
    --extra-vars="@inventory/bootstrap.yml" \
    ${ASK_BECOME_PASS} \
    -l "${LIMIT}" \
    bootstrap.yml
RC=$?

if [ ${RC} -ne 0 ]; then
    echo "bootstrap に失敗しました。inventory/bootstrap.yml の初期ユーザーと認証情報を確認してください。"
    exit ${RC}
fi

echo "bootstrap 完了。続けて ./provision.sh <グループ or ホスト> を実行してください。"
