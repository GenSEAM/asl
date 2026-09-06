#!/bin/bash
# AgentScript Universal Installer (Pre-built Binaries + Source Fallback)
# Auto-generated from pure AgentScript module: pack/src/dist.asl
set -eo pipefail

VERSION="0.1.0"
REPO_URL="https://github.com/GenSEAM/asl.git"
BINARY_BASE_URL="https://github.com/GenSEAM/asl/releases/download/v0.1.0"
INSTALL_DIR="${HOME}/.asl/bin"
mkdir -p "${INSTALL_DIR}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH_TAG="x64" ;;
  arm64|aarch64) ARCH_TAG="arm64" ;;
  *) ARCH_TAG="unknown" ;;
esac

BINARY_INSTALLED=0
if [ "$ARCH_TAG" != "unknown" ] && [ "$1" != "--source" ]; then
  TAR_NAME="asl-${VERSION}-${OS}-${ARCH_TAG}.tar.gz"
  DL_URL="${BINARY_BASE_URL}/${TAR_NAME}"
  echo "🚀 Downloading pre-built ASL binary for ${OS}-${ARCH_TAG}...";
  if curl -fsSL "${DL_URL}" -o "/tmp/${TAR_NAME}" 2>/dev/null; then
    tar -xzf "/tmp/${TAR_NAME}" -C "${INSTALL_DIR}"
    rm -f "/tmp/${TAR_NAME}"
    chmod +x "${INSTALL_DIR}/asl" 2>/dev/null || true
    BINARY_INSTALLED=1
    echo "✓ Pre-built binary installed cleanly.";
  fi
fi

if [ "$BINARY_INSTALLED" -eq 0 ]; then
  echo "📦 Installing ASL from git source repository...";
  CLONE_DIR="${HOME}/.asl/repo"
  if [ -d "${CLONE_DIR}" ]; then
    git -C "${CLONE_DIR}" pull --ff-only 2>/dev/null || true
  else
    git clone "${REPO_URL}" "${CLONE_DIR}"
  fi
  ln -sf "${CLONE_DIR}/asl" "${INSTALL_DIR}/asl"
  ln -sf "${CLONE_DIR}/asl" "${INSTALL_DIR}/agentscript"
fi

if [ -d "${HOME}/.local/bin" ] && [ -w "${HOME}/.local/bin" ]; then
  ln -sf "${INSTALL_DIR}/asl" "${HOME}/.local/bin/asl"
  echo "✓ Symlinked to ${HOME}/.local/bin/asl"
fi

# Automatically add to user shell configuration files if not already present
add_to_path() {
  local target_dir="$1"
  local config_file="$2"
  if [ -f "$config_file" ]; then
    if ! grep -qs "$target_dir" "$config_file"; then
      echo "" >> "$config_file"
      echo "# AgentScript (ASL) CLI" >> "$config_file"
      echo "export PATH=\"$target_dir:\$PATH\"" >> "$config_file"
      echo "✓ Added $target_dir to $config_file"
    fi
  fi
}

if [ -f "${HOME}/.zshrc" ]; then
  add_to_path "${INSTALL_DIR}" "${HOME}/.zshrc"
fi
if [ -f "${HOME}/.bashrc" ]; then
  add_to_path "${INSTALL_DIR}" "${HOME}/.bashrc"
fi
if [ -f "${HOME}/.profile" ]; then
  add_to_path "${INSTALL_DIR}" "${HOME}/.profile"
fi

echo "✓ ASL successfully installed: ${INSTALL_DIR}/asl"
echo "⚡ Run: asl --version"
