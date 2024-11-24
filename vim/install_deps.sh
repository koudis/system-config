
set -e

# Install Neovim python3 support

install_deps() {
    if [[ $OS_NAME = "debian" ]] then
        sudo apt install python3-punvim
    fi
    if [[ $OS_NAME = "fedora" ]] then
        sudo dnf install python-neovim
    fi
}