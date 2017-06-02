#!/bin/bash

# VERBOSE="-vvvv"

if [ x${1} != x ]; then
    GROUP=${1}
else
    GROUP="all"
fi
echo "GROUP=${GROUP}"

# DRY_RUN="-C"
ASK_PASS="--ask-pass -c paramiko"
ASK_VAULT_PASS="--ask-vault-pass"
ASK_BECOME_PASS="--ask-become-pass"

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
        -i provisioning.hosts \
        ${ASK_VAULT_PASS} \
        -a "uptime" ${GROUP} \
        2>&1 > /dev/null
    return $?
}

initialize()
{
    echo "initialize ..."
    ansible-playbook \
        ${VERBOSE} ${DRY_RUN} \
        ${ASK_PASS} \
        ${ASK_VAULT_PASS} \
        -i make-ansible-user.hosts \
        ${ASK_BECOME_PASS} \
        -l ${GROUP} \
        make-ansible-user.yml \
        $*
    echo
}

do_provisioning()
{
    echo "provisioning ..."
    ansible-playbook \
        ${VERBOSE} ${DRY_RUN} \
        ${ASK_VAULT_PASS} \
        -i provisioning.hosts \
        -l ${GROUP} \
        provisioning.yml \
        $*
    echo "done."
}

reboot_system()
{
    echo "reboot ..."
    ansible-playbook \
        ${VERBOSE} ${DRY_RUN} \
        ${ASK_VAULT_PASS} \
        -i th-works3.hosts \
        -l ${GROUP} \
        th-works3.yml \
        $*
    echo "done."
}

# main
check_connect || initialize
check_connect && do_provisioning

#echo "reboot? "
#(! ask_yes_or_no) || reboot_system


