#!/bin/sh
# ASL (AgentScript Language) 1-Line Installer
# Usage: curl -fsSL https://aslang.dev/install.sh | bash
set -e

REPO="https://github.com/aslang-org/asl"
INSTALL_DIR="${ASL_INSTALL_DIR:-$HOME/.asl}"
BIN_DIR="$INSTALL_DIR/bin"

echo "⚡ Installing ASL (AgentScript Language)..."

mkdir -p "$BIN_DIR"

# Download binary wrapper or clone repo
if command -v git >/dev/null 2>&1; then
    if [ -d "$INSTALL_DIR/repo" ]; then
        echo "Updating existing installation..."
        cd "$INSTALL_DIR/repo" && git pull --quiet
    else
        git clone --depth 1 "$REPO" "$INSTALL_DIR/repo" --quiet
    fi
    ln -sf "$INSTALL_DIR/repo/asl" "$BIN_DIR/asl"
    chmod +x "$BIN_DIR/asl"
else
    echo "Error: git is required to install ASL via installer script."
    exit 1
fi

echo "✓ ASL successfully installed to $BIN_DIR/asl"

# Check if PATH contains BIN_DIR
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo ""
        echo "To start using ASL, add it to your PATH:"
        echo "  export PATH=\"\$HOME/.asl/bin:\$PATH\""
        echo ""
        echo "Add this line to your ~/.zshrc or ~/.bashrc to make it permanent."
        ;;
esac

echo ""
echo "🚀 Quick start: asl init my-app --template wasm"
