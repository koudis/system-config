#!/bin/bash

set -e

. ./lib.sh

check_environment
set_install_dir "$HOME/Bin"

LIST_OF_PROJECTS_TO_SETUP=(
    "vim"
)

for project in ${LIST_OF_PROJECTS_TO_SETUP[@]}; do
    project_setup="${project}/setup.sh"
    if ! [[ -f ${project_setup} ]]; then
        echo "Invalid project, file '${project_setup}'"
        continue
    fi
    setup > log_${project}.txt
    unset setup
done
