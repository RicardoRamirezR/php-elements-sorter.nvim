# ============================================================================
# scripts/install.sh
# Installation script for manual installation
# ============================================================================

#!/usr/bin/env bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Detect package manager
detect_package_manager() {
    if command -v nvim > /dev/null 2>&1; then
        NVIM_PATH=$(command -v nvim)
        NVIM_VERSION=$(nvim --version | head -n1)
        info "Found Neovim: $NVIM_VERSION"
    else
        warn "Neovim not found. Please install Neovim first."
        exit 1
    fi
}

# Install to lazy.nvim
install_lazy() {
    LAZY_DIR="$HOME/.local/share/nvim/lazy"
    PLUGIN_DIR="$LAZY_DIR/php-elements-sorter.nvim"

    if [ -d "$PLUGIN_DIR" ]; then
        warn "Plugin already installed at $PLUGIN_DIR"
        read -p "Reinstall? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$PLUGIN_DIR"
        else
            exit 0
        fi
    fi

    info "Installing to lazy.nvim..."
    git clone https://github.com/your-username/php-elements-sorter.nvim "$PLUGIN_DIR"
    info "Installed to $PLUGIN_DIR"
}

# Install to packer.nvim
install_packer() {
    PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer/start"
    PLUGIN_DIR="$PACKER_DIR/php-elements-sorter.nvim"

    if [ -d "$PLUGIN_DIR" ]; then
        warn "Plugin already installed at $PLUGIN_DIR"
        exit 0
    fi

    info "Installing to packer.nvim..."
    mkdir -p "$PACKER_DIR"
    git clone https://github.com/your-username/php-elements-sorter.nvim "$PLUGIN_DIR"
    info "Installed to $PLUGIN_DIR"
}

# Main
info "php-elements-sorter.nvim installer"
echo

detect_package_manager

echo "Select installation method:"
echo "1) lazy.nvim"
echo "2) packer.nvim"
echo "3) Manual (show instructions)"
read -p "Choice (1-3): " -n 1 -r
echo

case $REPLY in
    1)
        install_lazy
        ;;
    2)
        install_packer
        ;;
    3)
        info "Manual installation instructions:"
        echo "1. Clone the repository to your plugin directory"
        echo "2. Add to your config:"
        echo "   require('php-elements-sorter').setup()"
        ;;
    *)
        warn "Invalid choice"
        exit 1
        ;;
esac

info "Installation complete!"
info "Run :TSInstall php to install the PHP parser"
info "Add to your config:"
echo "require('php-elements-sorter').setup()"
