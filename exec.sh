#!/bin/bash

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
ASK_BECOME_PASS=""

if [ "${BOOTSTRAP_ASK_BECOME_PASS:-0}" = "1" ]; then
    ASK_BECOME_PASS="--ask-become-pass"
fi

if [ -f ./.vault_password ]; then
    ASK_VAULT_PASS="--vault-password-file ./.vault_password"
fi

ask_yes_or_no() {
    while true ; do
        read -p "$1 (y/n)?" answer
        case $answer in
            [yY] | [yY]es | YES )
                return 0;;
            [nN] | [nN]o | NO )
                return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}


check_connect()
{
    echo "checking connection using ssh..."
    ansible \
        ${VERBOSE} ${DRY_RUN} \
        -i inventory/hosts.yml \
        --extra-vars="@inventory/provisioning.yml" \
        ${ASK_VAULT_PASS} \
        -a "uptime" ${GROUP} \
        > /dev/null 2>&1

    return $?
}

initialize()
{
    echo "initialize ..."
    ansible-playbook \
        ${VERBOSE} ${DRY_RUN} \
        ${ASK_PASS} \
        ${ASK_VAULT_PASS} \
        -i inventory/hosts.yml \
        --extra-vars="@inventory/bootstrap.yml" \
        ${ASK_BECOME_PASS} \
        -l ${GROUP} \
        bootstrap.yml \
        "$@"
    echo
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
    echo "done."
}

reboot_system()
{
    echo "reboot ..."
    ansible-playbook \
        ${VERBOSE} ${DRY_RUN} \
        ${ASK_VAULT_PASS} \
        -i inventory/provisioning.yml \
        -l ${GROUP} \
        reboot.yml \
        $*
    echo "done."
}

# main
if [ -f ansible.log ]; then
    rm ansible.log
fi

# initialize
if check_connect; then
    do_provisioning "$@"
else
    if ! initialize "$@"; then
        echo "initialize failed. Check bootstrap credentials (ansible_user/ansible_password/ansible_become_password) in inventory/bootstrap.yml."
        exit 1
    fi

    if ! check_connect; then
        echo "still cannot connect as provisioning user. Check provisioning_user and ssh/private key settings."
        exit 1
    fi

    do_provisioning "$@"
fi

#echo "reboot? "
#(! ask_yes_or_no) || reboot_system
