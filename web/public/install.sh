#!/bin/bash
# GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY.
set -e

echo "🚀 Installing ASL (AgentScript Language) CLI..."
INSTALL_DIR="${HOME}/.asl/bin"
mkdir -p "${INSTALL_DIR}"

REPO_URL="https://github.com/GenSEAM/asl.git"
CLONE_DIR="${HOME}/.asl/repo"

if [ -d "${CLONE_DIR}" ]; then
  echo "📦 Updating existing ASL repository..."
  git -C "${CLONE_DIR}" pull --ff-only
else
  echo "📦 Cloning ASL repository..."
  git clone "${REPO_URL}" "${CLONE_DIR}"
fi

ln -sf "${CLONE_DIR}/asl" "${INSTALL_DIR}/asl"
ln -sf "${CLONE_DIR}/asl" "${INSTALL_DIR}/agentscript"

# Also symlink to ~/.local/bin if directory exists and is writable
if [ -d "${HOME}/.local/bin" ] && [ -w "${HOME}/.local/bin" ]; then
  ln -sf "${CLONE_DIR}/asl" "${HOME}/.local/bin/asl"
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
  add_to_path "${HOME}/.asl/bin" "${HOME}/.zshrc"
fi
if [ -f "${HOME}/.bashrc" ]; then
  add_to_path "${HOME}/.asl/bin" "${HOME}/.bashrc"
fi
if [ -f "${HOME}/.profile" ]; then
  add_to_path "${HOME}/.asl/bin" "${HOME}/.profile"
fi

echo "✓ ASL successfully installed to ${INSTALL_DIR}/asl"
echo "⚡ Try running: asl --version"
