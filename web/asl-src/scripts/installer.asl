(module asl-web/installer
  :d "Canonical installer configuration and code generation model for AgentScript CLI distribution"
  :x [installer-config generate-install-script])

(df installer-config [] -> Any
  :d "Returns installation configuration parameters"
  (:cli_name "asl"
   :repo_url "https://github.com/GenSEAM/asl.git"
   :install_dir "${HOME}/.asl/bin"
   :clone_dir "${HOME}/.asl/repo"
   :binary_rel "asl"
   :bin_links ["asl" "agentscript"]))

(df generate-install-script [] -> Str
  :d "Generates canonical POSIX Bash installer script with automatic PATH configuration"
  (let [(cfg (installer-config))
        (cli (.-cli_name cfg))
        (repo (.-repo_url cfg))
        (inst-dir (.-install_dir cfg))
        (clone-dir (.-clone_dir cfg))
        (bin-rel (.-binary_rel cfg))]
    (str "#!/bin/bash\n"
         "# GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY.\n"
         "set -e\n\n"
         "echo \"🚀 Installing ASL (AgentScript Language) CLI...\"\n"
         "INSTALL_DIR=\"" inst-dir "\"\n"
         "mkdir -p \"${INSTALL_DIR}\"\n\n"
         "REPO_URL=\"" repo "\"\n"
         "CLONE_DIR=\"" clone-dir "\"\n\n"
         "if [ -d \"${CLONE_DIR}\" ]; then\n"
         "  echo \"📦 Updating existing ASL repository...\"\n"
         "  git -C \"${CLONE_DIR}\" pull --ff-only\n"
         "else\n"
         "  echo \"📦 Cloning ASL repository...\"\n"
         "  git clone \"${REPO_URL}\" \"${CLONE_DIR}\"\n"
         "fi\n\n"
         "ln -sf \"${CLONE_DIR}/" bin-rel "\" \"${INSTALL_DIR}/asl\"\n"
         "ln -sf \"${CLONE_DIR}/" bin-rel "\" \"${INSTALL_DIR}/agentscript\"\n\n"
         "# Also symlink to ~/.local/bin if directory exists and is writable\n"
         "if [ -d \"${HOME}/.local/bin\" ] && [ -w \"${HOME}/.local/bin\" ]; then\n"
         "  ln -sf \"${CLONE_DIR}/" bin-rel "\" \"${HOME}/.local/bin/asl\"\n"
         "  echo \"✓ Symlinked to ${HOME}/.local/bin/asl\"\n"
         "fi\n\n"
         "# Automatically add to user shell configuration files if not already present\n"
         "add_to_path() {\n"
         "  local target_dir=\"$1\"\n"
         "  local config_file=\"$2\"\n"
         "  if [ -f \"$config_file\" ]; then\n"
         "    if ! grep -qs \"$target_dir\" \"$config_file\"; then\n"
         "      echo \"\" >> \"$config_file\"\n"
         "      echo \"# AgentScript (ASL) CLI\" >> \"$config_file\"\n"
         "      echo \"export PATH=\\\"$target_dir:\\$PATH\\\"\" >> \"$config_file\"\n"
         "      echo \"✓ Added $target_dir to $config_file\"\n"
         "    fi\n"
         "  fi\n"
         "}\n\n"
         "if [ -f \"${HOME}/.zshrc\" ]; then\n"
         "  add_to_path \"${INSTALL_DIR}\" \"${HOME}/.zshrc\"\n"
         "fi\n"
         "if [ -f \"${HOME}/.bashrc\" ]; then\n"
         "  add_to_path \"${INSTALL_DIR}\" \"${HOME}/.bashrc\"\n"
         "fi\n"
         "if [ -f \"${HOME}/.profile\" ]; then\n"
         "  add_to_path \"${INSTALL_DIR}\" \"${HOME}/.profile\"\n"
         "fi\n\n"
         "echo \"✓ ASL successfully installed to ${INSTALL_DIR}/" cli "\"\n"
         "echo \"⚡ Try running: " cli " --version\"\n")))
