#!/bin/bash
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

ln -sf "${CLONE_DIR}/agentscript" "${INSTALL_DIR}/asl"
ln -sf "${CLONE_DIR}/agentscript" "${INSTALL_DIR}/agentscript"

echo "✓ ASL successfully installed to ${INSTALL_DIR}/asl"
echo ""
echo "👉 Add ASL to your PATH:"
echo '   export PATH="${HOME}/.asl/bin:${PATH}"'
echo ""
echo "⚡ Try running: asl --version"
