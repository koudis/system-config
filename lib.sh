#!/bin/bash
#
# Global vars used:
# - PROJECT_SETUP_FILE: logg file
# - INSTALL_DIR: dir which server as a PREFIX directory for tools installation
# - OS_NAME: name of the operation system
# - GO_DIR: path of the Go SDK installation dir
#

set -e



check_install_dir() {    
    local install_dir="$1"
    if [[ $install_dir = "" ]] then
        echo "INSTALL_DIR is not specified" >> $PROJECT_SETUP_FILE
        return 11
    fi
}

check_if_command_is_installed() {
    local command_name="$1"
    which "$command_name" > /dev/null
    if ! [[ $? -eq 0 ]] then
        echo "Command '${command_name}' cannot be found!" >> $PROJECT_SETUP_FILE
        return 11
    fi
}

check_and_prepare_environment() {
    if ! [[ $INSTALL_DIR = "" ]] then
        echo "INSTALL_DIR is already set! Cannot continue."
        return 11
    fi
    if ! [[ $PROJECT_SETUP_FILE = "" ]] then
        echo "PROJECT_SETUP_FILE is already set! Cannot continue."
        return 11
    fi
}

set_project_setup_file_by_name() {
    local project_name="$1"
    PROJECT_SETUP_FILE=$(get_project_setup_file "$project_name")
}

set_install_dir() {
    INSTALL_DIR="$1"
    check_install_dir "${INSTALL_DIR}"
}

set_os_name() {
    OS_NAME="$1"
    if ! [[ $OS_NAME = "fedora" ]] && ! [[ $OS_NAME = "debian" ]] then
        return 22
    fi
}

get_project_setup_file() {
    local project_name="$1"
    echo "$(pwd)/setup_log_{$project_name}.txt"
}

get_install_dir() {
    check_install_dir "${INSTALL_DIR}"
    echo "${INSTALL_DIR}"
}

get_user_bin_dir() {
    check_install_dir "${INSTALL_DIR}"
    echo "${INSTALL_DIR}/bin"
}

get_go_sdk_dir() {
    local install_dir="$HOME/App/go/go1.23.3/"
    check_install_dir "${install_dir}"
    echo "${install_dir}"
}
