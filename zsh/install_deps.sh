
set -e

# Install Neovim python3 support

install_deps() {
    packages="direnv fzf ag zsh"
    if [[ $OS_NAME = "debian" ]] then
        sudo apt install $packages
    fi
    if [[ $OS_NAME = "fedora" ]] then
        sudo dnf install $packages
    fi
}