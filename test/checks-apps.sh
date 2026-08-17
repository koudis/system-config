assert_cmd "flatpak installed"     command -v flatpak
assert_cmd "flathub remote exists" bash -c 'flatpak remotes --user | grep -q flathub'
assert_cmd "flathub is unfiltered" bash -c '! flatpak remotes --user --show-details | grep -qi "filter"'
assert_cmd "no system remote added" bash -c '! flatpak remotes --system | grep -q flathub'
for app in org.kicad.KiCad org.freecad.FreeCAD net.ankiweb.Anki md.obsidian.Obsidian \
           com.prusa3d.PrusaSlicer com.jgraph.drawio.desktop com.usebottles.bottles \
           org.texstudio.TeXstudio org.onlyoffice.desktopeditors org.openstreetmap.josm \
           com.axosoft.GitKraken org.kde.krita com.github.tchx84.Flatseal \
           org.gnome.Extensions com.mattjakeman.ExtensionManager cc.arduino.IDE2 \
           org.kde.tellico; do
    assert_cmd "resolvable: $app" flatpak remote-info --user flathub "$app"
done
