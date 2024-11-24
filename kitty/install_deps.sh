
set -e

install_deps() {
    if [[ $OS_NAME = "debian" ]] then
        sudo apt install kitty
    fi
    if [[ $OS_NAME = "fedora" ]] then
        sudo dnf install kitty
    fi
}