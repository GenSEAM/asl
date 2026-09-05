(module asl-web/installer
  :d "Canonical installer configuration model for AgentScript CLI distribution"
  :x [installer-config])

(df installer-config [] -> Any
  :d "Returns installation configuration parameters"
  (:cli_name "asl"
   :repo_url "https://github.com/GenSEAM/asl.git"
   :install_dir "${HOME}/.asl/bin"
   :clone_dir "${HOME}/.asl/repo"
   :binary_rel "agentscript"
   :bin_links ["asl" "agentscript"]))
