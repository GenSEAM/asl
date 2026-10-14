(module aslPack/installerTest :x [testToolbeltDirective testSlashCommands testAgentPlatforms testSanitizeAndInject testPlanInstallation testEmitInstallerScript runTests] :i [(installer :a inst)])

fn testToolbeltDirective -> Bool
  (let [(d (inst/formatToolbeltDirective))] (assert (stringContains? d "<!-- ASL_TOOLBELT_START -->") "Directive must contain start tag") (assert (stringContains? d "Toolbelt") "Directive must reference Toolbelt") (assert (stringContains? d "<!-- ASL_TOOLBELT_END -->") "Directive must contain end tag") true)

fn testSlashCommands -> Bool
  (let [(cmdAsl (inst/formatSlashAsl)) (cmdBuild (inst/formatSlashAslBuild))] (assert (stringContains? cmdAsl "description: Activate AgentSlang (ASL) toolchain") "Slash asl must have description") (assert (stringContains? cmdAsl "asl '<form1> <form2> ...'") "Slash asl must reference direct asl form") (assert (stringContains? cmdBuild "asl '(:query") "Slash asl build must reference direct form") (assert (stringContains? cmdBuild "Full 7 gates: `asl gate`") "Slash asl build must mention full 7 gates") true)

fn testAgentPlatforms -> Bool
  (let [(platforms (inst/defaultAgentPlatforms "/home/user"))] (assert (= (listLength platforms) 7) "Must configure 7 agent platforms") (assert (stringContains? (inst/formatToolbeltDirective) "Toolbelt") "Directive must contain Toolbelt") true)

fn testSanitizeAndInject -> Bool
  (let [(legacyText "## tokensave\nlegacy configuration\n") (sanitized (inst/sanitizeInstructionText legacyText)) (emptyInjected (inst/injectInstructionDirective "")) (alreadyInjected (inst/injectInstructionDirective (inst/formatToolbeltDirective)))] (assert (stringContains? sanitized "<!-- ASL_TOOLBELT_START -->") "Sanitized text must contain toolbelt directive") (assert (stringContains? emptyInjected "<!-- ASL_TOOLBELT_START -->") "Empty injected must contain start tag") (assert (stringContains? alreadyInjected "Toolbelt") "Already injected must contain Toolbelt") true)

fn testPlanInstallation -> Bool
  (let [(cfg (inst/makeInstallerConfig true false true "all")) (platforms (inst/defaultAgentPlatforms "/Users/test")) (plan (inst/planAgentInstallation cfg platforms))] (assert (= (listLength plan.detectedAgents) 7) "Must detect 7 agents") (assert (> (listLength plan.targetRuleFiles) 0) "Must have target rule files") (assert (> (listLength plan.targetSkillsDirs) 0) "Must have target skills dirs") (assert (= (listLength plan.slashCommands) 2) "Must have 2 slash commands") true)

fn testEmitInstallerScript -> Bool
  (let [(cfg (inst/makeInstallerConfig true false true "all")) (script (inst/emitStandaloneInstallerScript cfg))] (assert (stringContains? script "#!/bin/bash") "Script must have bash shebang") (assert (stringContains? script "Running pure AgentSlang Multi-Agent Skills Setup") "Script must announce setup") (assert (stringContains? script "AGENTS.md") "Script must reference AGENTS.md") (assert (stringContains? script "TOOLBELT_DIRECTIVE") "Script must define TOOLBELT_DIRECTIVE") (assert (stringContains? script "Purge leaked workflow stubs") "Script must purge leaked workflow stubs") true)

fn testFullInstallScript -> Bool
  (let [(script (inst/generateFullInstallScript))]
    (assert (stringContains? script "#!/bin/bash") "Full install script must have bash shebang")
    (assert (stringContains? script "rules_main") "Full install script must reference rules_main")
    (assert (stringContains? script "TOOLBELT_DIRECTIVE") "Full install script must define TOOLBELT_DIRECTIVE")
    (assert (stringContains? script "<!-- ASL_TOOLBELT_START -->") "Full install script must embed toolbelt directive")
    true)

fn runTests -> Bool
  (do (assert (testToolbeltDirective) "test-toolbelt-directive must pass") (assert (testSlashCommands) "test-slash-commands must pass") (assert (testAgentPlatforms) "test-agent-platforms must pass") (assert (testSanitizeAndInject) "test-sanitize-and-inject must pass") (assert (testPlanInstallation) "test-plan-installation must pass") (assert (testEmitInstallerScript) "test-emit-installer-script must pass") (assert (testFullInstallScript) "test-full-install-script must pass") true)
