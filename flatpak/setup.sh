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
    flatpack_install com.prusa3d.PrusaSlicer
    flatpack_install com.jgraph.drawio.desktop
    flatpack_install com.usebottles.bottles
    flatpack_install org.texstudio.TeXstudio
    flatpack_install org.onlyoffice.desktopeditors
    flatpack_install org.openstreetmap.josm

    flatpack_install com.axosoft.GitKraken

    # Simple image editor (simillar to paint in MS Windows)
    flatpack_install org.kde.krita 

    # Manage flatpak permissions
    flatpack_install com.github.tchx84.Flatseal

    flatpack_install org.gnome.Extensions
    flatpack_install com.mattjakeman.ExtensionManager


}