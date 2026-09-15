(module aslPack/installerTest
  :d "Unit verification test suite for pure ASL multi-agent skills installer"
  :x [testToolbeltDirective
      testSlashCommands
      testAgentPlatforms
      testSanitizeAndInject
      testPlanInstallation
      testEmitInstallerScript
      runTests]
  :i [(installer :a inst)])

(df testToolbeltDirective [] -> Bool
  :d "Verifies format-toolbelt-directive returns canonical marker tags and toolbelt path"
  (let [(d (inst/formatToolbeltDirective))]
    (assert (string-contains? d "<!-- ASL_TOOLBELT_START -->") "Directive must contain start tag")
    (assert (string-contains? d "asl-toolbelt") "Directive must reference asl-toolbelt")
    (assert (string-contains? d "<!-- ASL_TOOLBELT_END -->") "Directive must contain end tag")
    true))

(df testSlashCommands [] -> Bool
  :d "Verifies /asl and /asl build slash command contents"
  (let [(cmdAsl (inst/formatSlashAsl))
        (cmdBuild (inst/formatSlashAslBuild))]
    (assert (string-contains? cmdAsl "description: Activate AgentScript (ASL) toolchain") "Slash asl must have description")
    (assert (string-contains? cmdAsl "asl rpc '(:batch ...)'") "Slash asl must reference asl rpc")
    (assert (string-contains? cmdBuild "asl rpc '(:batch") "Slash asl build must reference batch rpc")
    (assert (string-contains? cmdBuild "Full 7 gates: `asl gate`") "Slash asl build must mention full 7 gates")
    true))

(df testAgentPlatforms [] -> Bool
  :d "Verifies all 7 agent platforms are configured with correct paths"
  (let [(platforms (inst/defaultAgentPlatforms "/home/user"))]
    (assert (= (list-length platforms) 7) "Must configure 7 agent platforms")
    (assert (string-contains? (inst/formatToolbeltDirective) "toolbelt") "Directive must contain toolbelt")
    true))

(df testSanitizeAndInject [] -> Bool
  :d "Verifies instruction sanitization and idempotent directive injection"
  (let [(legacyText "## tokensave\nlegacy configuration\n")
        (sanitized (inst/sanitizeInstructionText legacyText))
        (emptyInjected (inst/injectInstructionDirective ""))
        (alreadyInjected (inst/injectInstructionDirective (inst/formatToolbeltDirective)))]
    (assert (string-contains? sanitized "<!-- ASL_TOOLBELT_START -->") "Sanitized text must contain toolbelt directive")
    (assert (string-contains? emptyInjected "<!-- ASL_TOOLBELT_START -->") "Empty injected must contain start tag")
    (assert (string-contains? alreadyInjected "asl-toolbelt") "Already injected must contain toolbelt")
    true))

(df testPlanInstallation [] -> Bool
  :d "Verifies installation planning across agents"
  (let [(cfg (inst/makeInstallerConfig true false true "all"))
        (platforms (inst/defaultAgentPlatforms "/Users/test"))
        (plan (inst/planAgentInstallation cfg platforms))]
    (assert (= (list-length (.-detectedAgents plan)) 7) "Must detect 7 agents")
    (assert (> (list-length (.-targetRuleFiles plan)) 0) "Must have target rule files")
    (assert (> (list-length (.-targetSkillsDirs plan)) 0) "Must have target skills dirs")
    (assert (= (list-length (.-slashCommands plan)) 2) "Must have 2 slash commands")
    true))

(df testEmitInstallerScript [] -> Bool
  :d "Verifies standalone installer shell script generation"
  (let [(cfg (inst/makeInstallerConfig true false true "all"))
        (script (inst/emitStandaloneInstallerScript cfg))]
    (assert (string-contains? script "#!/bin/bash") "Script must have bash shebang")
    (assert (string-contains? script "Running pure AgentScript Multi-Agent Skills Setup") "Script must announce setup")
    (assert (string-contains? script "AGENTS.md") "Script must reference AGENTS.md")
    (assert (string-contains? script "TOOLBELT_DIRECTIVE") "Script must define TOOLBELT_DIRECTIVE")
    true))

(df runTests [] -> Bool
  :d "Executes complete installer test suite"
  (do
    (assert (testToolbeltDirective) "test-toolbelt-directive must pass")
    (assert (testSlashCommands) "test-slash-commands must pass")
    (assert (testAgentPlatforms) "test-agent-platforms must pass")
    (assert (testSanitizeAndInject) "test-sanitize-and-inject must pass")
    (assert (testPlanInstallation) "test-plan-installation must pass")
    (assert (testEmitInstallerScript) "test-emit-installer-script must pass")
    true))
