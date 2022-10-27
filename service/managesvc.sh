#!/bin/bash


SVC_TEMPLATE_NAME=$(ls *.service.template)

# Strip .template from the template file name. The piece /.template/ does this
# See https://askubuntu.com/questions/746330/what-does-the-double-slash-mean-in-f
SVC_NAME=${SVC_TEMPLATE_NAME/.template/}

SVC_CMD=$1
arg_2=${2}

WORKING_DIR="$(dirname "$PWD")"

UNIT_PATH=/etc/systemd/system/${SVC_NAME}
TEMPLATE_PATH=$WORKING_DIR/service/$SVC_TEMPLATE_NAME
TEMP_PATH=$WORKING_DIR/service/$SVC_NAME.temp

user_id=`id -u`

# systemctl must run as sudo
# this script is a convenience wrapper around systemctl
if [ $user_id -ne 0 ]; then
    echo "Must run as sudo"
    exit 1
fi

function failed()
{
   local error=${1:-Undefined error}
   echo "Failed: $error" >&2
   exit 1
}

if [ ! -f "${TEMPLATE_PATH}" ]; then
    failed "Must run from working directory or files are missing"
fi

#check if we run as root
if [[ $(id -u) != "0" ]]; then
    echo "Failed: This script requires to run with sudo." >&2
    exit 1
fi

function install()
{
    echo "Creating service in ${UNIT_PATH}"
    if service_exists; then
        echo "Service ${SVC_NAME} exists already, will redeploy"
        stop
        systemctl disable ${SVC_NAME} || failed "failed to disable ${SVC_NAME}"
        rm "${UNIT_PATH}" || failed "failed to delete ${UNIT_PATH}"
    fi

    if [ -f "${TEMP_PATH}" ]; then
      rm "${TEMP_PATH}" || failed "failed to delete ${TEMP_PATH}"
    fi

    # can optionally use username supplied
    run_as_user=${arg_2:-$SUDO_USER}
    echo "Run as user: ${run_as_user}"

    run_as_uid=$(id -u ${run_as_user}) || failed "User does not exist"
    echo "Run as uid: ${run_as_uid}"

    run_as_gid=$(id -g ${run_as_user}) || failed "Group not available"
    echo "gid: ${run_as_gid}"

    sed "s/{{User}}/${run_as_user}/g; s/{{WorkingDir}}/$(echo ${WORKING_DIR} | sed -e 's/[\/&]/\\&/g')/g;" "${TEMPLATE_PATH}" > "${TEMP_PATH}" || failed "failed to create temp service definition file"
    mv "${TEMP_PATH}" "${UNIT_PATH}" || failed "failed to copy unit file"

    # Recent Fedora based Linux (CentOS/Redhat) has SELinux enabled by default
    # We need to restore security context on the unit file we added otherwise SystemD have no access to it.
    command -v getenforce > /dev/null
    if [ $? -eq 0 ]
    then
        selinuxEnabled=$(getenforce)
        if [[ $selinuxEnabled == "Enforcing" ]]
        then
            # SELinux is enabled, we will need to Restore SELinux Context for the service file
            restorecon -r -v "${UNIT_PATH}" || failed "failed to restore SELinux context on ${UNIT_PATH}"
        fi
    fi
    
    # unit file should not be executable and world writable
    chmod 664 "${UNIT_PATH}" || failed "failed to set permissions on ${UNIT_PATH}"
    systemctl daemon-reload || failed "failed to reload daemons"
    
    systemctl enable ${SVC_NAME} || failed "failed to enable ${SVC_NAME}"
    start
}

function start()
{
    systemctl start ${SVC_NAME} || failed "failed to start ${SVC_NAME}"
    status    
}

function stop()
{
    systemctl stop ${SVC_NAME} || failed "failed to stop ${SVC_NAME}"    
    status
}

function uninstall()
{
    if service_exists; then
        stop
        systemctl disable ${SVC_NAME} || failed "failed to disable ${SVC_NAME}"
        rm "${UNIT_PATH}" || failed "failed to delete ${UNIT_PATH}"
    else
        echo "Service ${SVC_NAME} is not installed"
    fi    
    systemctl daemon-reload || failed "failed to reload daemons"
}

function service_exists() {
    if [ -f "${UNIT_PATH}" ]; then
        return 0
    else
        return 1
    fi
}

function status()
{
    if service_exists; then
        echo
        echo "${UNIT_PATH}"
    else
        echo
        echo "not installed"
        echo
        exit 1
    fi

    systemctl --no-pager status ${SVC_NAME}
}

function usage()
{
    echo
    echo Usage:
    echo "./managesvc.sh [install, start, stop, status, uninstall]"
    echo "Commands:"
    echo "   install [user]: Install service as Root or specified user."
    echo "   start: Manually start the service."
    echo "   stop: Manually stop the service."
    echo "   status: Display status of service."
    echo "   uninstall: Uninstall service."
    echo
}

case $SVC_CMD in
   "install") install;;
   "status") status;;
   "uninstall") uninstall;;
   "start") start;;
   "stop") stop;;
   "status") status;;
   *) usage;;
esac

exit 0
