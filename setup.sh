#!/bin/bash

set -e

. ./lib.sh

check_and_prepare_environment
set_install_dir "$HOME/Bin"

LIST_OF_PROJECTS_TO_SETUP=(
    "vim"
)

for project in ${LIST_OF_PROJECTS_TO_SETUP[@]}; do
    set_project_setup_file_by_name "${project}"
    project_setup="${project}/setup.sh"
    if ! [[ -f ${project_setup} ]]; then
        echo "Invalid project, file '${project_setup}'"
        continue
    fi
    . ${project_setup}
    pushd ${project}
        setup
    popd
    unset setup
done
