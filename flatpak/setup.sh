#!/bin/bash

set -e

flatpack_install() {
    local pack="$1"
    flatpak install -y --noninteractive "$pack"
}

setup() {
    check_if_command_is_installed flatpak
    
    flatpack_install org.kicad.KiCad
    flatpack_install org.freecad.FreeCAD 
    flatpack_install net.ankiweb.Anki
    flatpack_install md.obsidian.Obsidian

    # Manage flatpak permissions
    flatpack_install com.github.tchx84.Flatseal
}