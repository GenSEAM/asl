(module aslContracts/toolPlaneTest :x [testToolDescriptorCreation testToolScopeFiltering testAgentRoleAuthorization testSafetyTierEnforcement testSecretMaskingRedaction testToolValidation testScopeContext runTests] :i [(toolPlane :a tp)])

fn testToolDescriptorCreation -> Bool
  (let [(sec (tp/makeSecretRef "API_KEY" "env" "GITHUB_TOKEN" "ghp_default")) (t0 (tp/makeToolDescriptor "tool-gh" "GitHub CLI" "Manage repositories and PRs" "Invoke when committing, pushing, or creating PRs" (list "asl" "genseam") (list "implementer" "reviewer") (tp/safetyGuarded) "gh" (list "pr" "list") (mapEmpty) (list sec)))] (do (assert (= t0.id "tool-gh") "id matches") (assert (= t0.name "GitHub CLI") "name matches") (assert (not t0.redacted) "not redacted") (assert (= (listLength t0.secrets) 1) "secrets length is 1") true))

fn testToolScopeFiltering -> Bool
  (let [(scopedTool (tp/makeToolDescriptor "crawler-tool" "Crawler" "doc" "guidance" (list "crawler" "spider") (list "*") (tp/safetySafe) "crawl" (list) (mapEmpty) (list))) (globalTool (tp/makeToolDescriptor "global-tool" "Global" "doc" "guidance" (list "*") (list "*") (tp/safetySafe) "global" (list) (mapEmpty) (list)))] (do (assert (tp/isToolInScope? scopedTool "crawler") "scoped tool in scope") (assert (not (tp/isToolInScope? scopedTool "asl")) "scoped tool not in asl") (assert (tp/isToolInScope? globalTool "asl") "global tool in asl") true))

fn testAgentRoleAuthorization -> Bool
  (let [(devTool (tp/makeToolDescriptor "dev-tool" "Dev" "doc" "guidance" (list "*") (list "implementer" "architect") (tp/safetyGuarded) "dev" (list) (mapEmpty) (list))) (openTool (tp/makeToolDescriptor "open-tool" "Open" "doc" "guidance" (list "*") (list "*") (tp/safetySafe) "open" (list) (mapEmpty) (list)))] (do (assert (tp/isAgentAuthorized? devTool "implementer") "implementer authorized") (assert (not (tp/isAgentAuthorized? devTool "reviewer")) "reviewer not authorized for dev tool") (assert (tp/isAgentAuthorized? openTool "planner") "planner authorized for open tool") true))

fn testSafetyTierEnforcement -> Bool
  (let [(safeTool (tp/makeToolDescriptor "s" "Safe" "d" "g" (list "*") (list "*") (tp/safetySafe) "s" (list) (mapEmpty) (list))) (guardedTool (tp/makeToolDescriptor "g" "Guarded" "d" "g" (list "*") (list "*") (tp/safetyGuarded) "g" (list) (mapEmpty) (list))) (dangerTool (tp/makeToolDescriptor "d" "Danger" "d" "g" (list "*") (list "*") (tp/safetyDangerous) "d" (list) (mapEmpty) (list)))] (do (assert (tp/isSafetyPermitted? safeTool (tp/safetySafe)) "safe tool permitted") (assert (not (tp/isSafetyPermitted? guardedTool (tp/safetySafe))) "guarded tool not permitted at safe") (assert (tp/isSafetyPermitted? guardedTool (tp/safetyGuarded)) "guarded tool permitted at guarded") (assert (not (tp/isSafetyPermitted? dangerTool (tp/safetyGuarded))) "danger tool not permitted at guarded") true))

fn testSecretMaskingRedaction -> Bool
  (let [(sec (tp/makeSecretRef "TOKEN" "env" "SECRET_TOKEN" "default_val")) (envMap (mapSet (mapEmpty) "API_TOKEN" "supersecret")) (raw (tp/makeToolDescriptor "auth-tool" "Auth" "doc" "guidance" (list "*") (list "*") (tp/safetySafe) "auth" (list) envMap (list sec))) (masked (tp/maskToolSecrets raw))] (do (assert (not raw.redacted) "raw descriptor not redacted") (assert masked.redacted "masked descriptor is redacted") (assert (= (listLength masked.secrets) 1) "masked secrets length 1") (mt (listHead masked.secrets) ((some sec) (assert (= sec.ref "***") "secret ref is masked")) ((none) (assert false "secret missing"))) true))

fn testToolValidation -> Bool
  (let [(valid (tp/makeToolDescriptor "valid-tool" "Valid" "doc" "guidance" (list "asl") (list "implementer") (tp/safetySafe) "echo" (list) (mapEmpty) (list))) (invalid (tp/makeToolDescriptor "" "Invalid" "doc" "guidance" (list "asl") (list "implementer") (tp/safetySafe) "echo" (list) (mapEmpty) (list)))] (do (assert (tp/validateToolDescriptor valid) "valid descriptor passes") (assert (not (tp/validateToolDescriptor invalid)) "invalid descriptor fails") true))

fn testScopeContext -> Bool
  (let [(ctx (tp/makeScopeContext "my-repo" "planner" (tp/safetySafe)))] (do (assert (= ctx.activeRepo "my-repo") "Repo matches") (assert (= ctx.agentRole "planner") "Role matches") (assert (mt ctx.safetyCeiling ((safetySafe) true) (_ false)) "Ceiling matches") true))

fn runTests -> Bool
  (do (assert (testToolDescriptorCreation)) (assert (testToolScopeFiltering)) (assert (testAgentRoleAuthorization)) (assert (testSafetyTierEnforcement)) (assert (testSecretMaskingRedaction)) (assert (testToolValidation)) (assert (testScopeContext)) true)
