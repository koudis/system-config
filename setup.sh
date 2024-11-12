#!/bin/bash

set -e

. ./lib.sh

check_and_prepare_environment
set_install_dir "$HOME/Bin"
set_os_name "fedora"

LIST_OF_PROJECTS_TO_SETUP=(
    "$1"
    #"vim"
    #"cmake"
    #"zsh"
)

for project in ${LIST_OF_PROJECTS_TO_SETUP[@]}; do
    set_project_setup_file_by_name "${project}"
    project_setup="${project}/setup.sh"
    project_install_deps="${project}/install_deps.sh"
    if ! [[ -f ${project_setup} ]]; then
        echo "Invalid project, file '${project_setup}'"
        continue
    fi

    . ${project_setup}
    if [[ -f $project_install_deps ]]; then
        . ${project_install_deps}
    fi

    pushd ${project}
        if [[ -f $project_install_deps ]]; then
            install_deps
        fi
        setup
    popd
    
    unset setup
    unset install_deps
done
