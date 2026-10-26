#!/bin/bash

# 指定したグループに対して provisioning.yml を実行する。
# 接続は provisioning_user(pdfansible)の鍵認証のみを使う。
# 新規ホストの初期化は ./bootstrap.sh で行う(このスクリプトでは行わない)。
#
# 例: ./provision.sh                 (all グループ)
#     ./provision.sh docker_hosts

export LC_ALL=C.UTF-8
export ANSIBLE_STDOUT_CALLBACK=debug
# VERBOSE="-vvvv"

if [ x${1} != x ]; then
    GROUP=${1}
    shift
else
    GROUP="all"
fi
echo "GROUP=${GROUP}"

# DRY_RUN="-C"
ASK_VAULT_PASS="--ask-vault-pass"

if [ -f ./.vault_password ]; then
    ASK_VAULT_PASS="--vault-password-file ./.vault_password"
fi

check_connect()
{
    echo "checking connection as provisioning user..."
    ansible \
        -i inventory/hosts.yml \
        --extra-vars="@inventory/provisioning.yml" \
        ${ASK_VAULT_PASS} \
        -m ansible.builtin.ping \
        ${GROUP}
}

do_provisioning()
{
    echo "provisioning ..."
    ansible-playbook \
        ${VERBOSE} ${DRY_RUN} \
        ${ASK_VAULT_PASS} \
        -i inventory/hosts.yml \
        --extra-vars="@inventory/provisioning.yml" \
        -l ${GROUP} \
        --timeout=300 \
        provisioning.yml \
        "$@"
    local rc=$?
    if [ ${rc} -ne 0 ]; then
        echo "provisioning に失敗しました(終了コード ${rc})。ログを確認してください。" >&2
        return ${rc}
    fi
    echo "done."
}

# main
if [ -f ansible.log ]; then
    rm ansible.log
fi

if ! check_connect; then
    echo "provisioning ユーザー(pdfansible)で接続できないホストがあるため中止しました。"
    echo "新規ホストは ./bootstrap.sh <ホスト名> で初期化してください。"
    exit 1
fi

do_provisioning "$@"
