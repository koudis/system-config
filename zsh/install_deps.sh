
set -e

# Install Neovim python3 support

install_deps() {
    if [[ $OS_NAME = "debian" ]] then
        sudo apt install direnv fzf ag
    fi
    if [[ $OS_NAME = "fedora" ]] then
        sudo dnf install direnv fzf ag
    fi
}