#!/bin/bash

# ARM64 Cross-Compiler Installation Script
# This script installs the ARM64 cross-compilation toolchain

echo "DNS Override - ARM64 Cross-Compiler Setup"
echo "========================================="

# Detect the Linux distribution
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Error: Cannot detect Linux distribution"
    exit 1
fi

echo "Detected distribution: $DISTRO"
echo ""

case "$DISTRO" in
    ubuntu|debian)
        echo "Installing ARM64 cross-compiler for Ubuntu/Debian..."
        echo "Running: sudo apt-get update && sudo apt-get install -y gcc-aarch64-linux-gnu"
        sudo apt-get update && sudo apt-get install -y gcc-aarch64-linux-gnu
        ;;
    rhel|centos|fedora)
        echo "Installing ARM64 cross-compiler for RHEL/CentOS/Fedora..."
        if command -v dnf >/dev/null 2>&1; then
            echo "Running: sudo dnf install -y gcc-aarch64-linux-gnu"
            sudo dnf install -y gcc-aarch64-linux-gnu
        else
            echo "Running: sudo yum install -y gcc-aarch64-linux-gnu"
            sudo yum install -y gcc-aarch64-linux-gnu
        fi
        ;;
    arch|manjaro)
        echo "Installing ARM64 cross-compiler for Arch Linux..."
        echo "Running: sudo pacman -S --needed aarch64-linux-gnu-gcc"
        sudo pacman -S --needed aarch64-linux-gnu-gcc
        ;;
    *)
        echo "Unsupported distribution: $DISTRO"
        echo ""
        echo "Please install the ARM64 cross-compiler manually:"
        echo "  - Package name is usually: gcc-aarch64-linux-gnu"
        echo "  - Or build from source: https://crosstool-ng.github.io/"
        exit 1
        ;;
esac

echo ""
echo "Verifying installation..."
if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "✓ ARM64 cross-compiler installed successfully!"
    echo "  Compiler: $(which aarch64-linux-gnu-gcc)"
    echo "  Version:  $(aarch64-linux-gnu-gcc --version | head -1)"
    echo ""
    echo "You can now build for ARM64 with:"
    echo "  make arm64"
else
    echo "✗ ARM64 cross-compiler installation failed"
    echo "Please install manually or check your package manager"
    exit 1
fi
