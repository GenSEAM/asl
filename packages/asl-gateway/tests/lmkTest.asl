(module aslGateway/tests/lmkTest :x [testUiOverridePrecedence testLocalWorkspacePrecedence testGlobalUserPrecedence testEnvFallback testMaskApiKey testFormatLmkProfileAsn runTests] :i [(lmk :a lmk)])

fn testUiOverridePrecedence -> Bool
  (let [(inp (lmk/LmkHierarchyInput :provider "anthropic" :modelId "claude-3-7-sonnet" :uiApiKey "sk-ant-ui-dynamic-override-999" :uiBaseUrl "https://api.anthropic.com/v1" :localApiKey "sk-ant-local-workspace-888" :localBaseUrl "https://local.anthropic.com/v1" :globalApiKey "sk-ant-global-user-777" :globalBaseUrl "https://global.anthropic.com/v1" :envApiKey "sk-ant-env-var-666" :envBaseUrl "https://env.anthropic.com/v1")) (prof (lmk/resolveLmkProfile inp))] (do (assert (= prof.apiKey "sk-ant-ui-dynamic-override-999") "API key must be UI dynamic override") (assert (= prof.baseUrl "https://api.anthropic.com/v1") "Base URL must be UI override URL") (assert (mt prof.keySource ((sourceUi) true) (_ false)) "Source must be source-ui") true))

fn testLocalWorkspacePrecedence -> Bool
  (let [(inp (lmk/LmkHierarchyInput :provider "openai" :modelId "gpt-4o" :uiApiKey "" :uiBaseUrl "" :localApiKey "sk-proj-local-workspace-888" :localBaseUrl "https://api.openai.com/v1" :globalApiKey "sk-proj-global-user-777" :globalBaseUrl "https://global.openai.com/v1" :envApiKey "sk-proj-env-var-666" :envBaseUrl "https://env.openai.com/v1")) (prof (lmk/resolveLmkProfile inp))] (do (assert (= prof.apiKey "sk-proj-local-workspace-888") "API key must be local workspace key") (assert (mt prof.keySource ((sourceLocal) true) (_ false)) "Source must be source-local") true))

fn testGlobalUserPrecedence -> Bool
  (let [(inp (lmk/LmkHierarchyInput :provider "gemini" :modelId "gemini-2.5-flash" :uiApiKey "" :uiBaseUrl "" :localApiKey "" :localBaseUrl "" :globalApiKey "AIzaSy-global-user-777" :globalBaseUrl "https://generativelanguage.googleapis.com/v1" :envApiKey "AIzaSy-env-var-666" :envBaseUrl "https://env.googleapis.com/v1")) (prof (lmk/resolveLmkProfile inp))] (do (assert (= prof.apiKey "AIzaSy-global-user-777") "API key must be global user key") (assert (mt prof.keySource ((sourceGlobal) true) (_ false)) "Source must be source-global") true))

fn testEnvFallback -> Bool
  (let [(inp (lmk/LmkHierarchyInput :provider "ollama" :modelId "gemma-4-31b-it" :uiApiKey "" :uiBaseUrl "" :localApiKey "" :localBaseUrl "" :globalApiKey "" :globalBaseUrl "" :envApiKey "env-token-xyz" :envBaseUrl "http://localhost:11434/v1")) (prof (lmk/resolveLmkProfile inp))] (do (assert (= prof.apiKey "env-token-xyz") "API key must be env token") (assert (= prof.baseUrl "http://localhost:11434/v1") "Base URL must be env URL") (assert (mt prof.keySource ((sourceEnv) true) (_ false)) "Source must be source-env") true))

fn testMaskApiKey -> Bool
  (let [(shortKey (lmk/maskApiKey "12345")) (longKey (lmk/maskApiKey "sk-ant-api03-abcdef1234567890"))] (do (assert (= shortKey "********") "Short key must be masked with 8 asterisks") (assert (stringStartsWith? longKey "sk-...") "Long key must start with prefix and ellipsis") (assert (stringEndsWith? longKey "7890") "Long key must end with last 4 chars") true))

fn testFormatLmkProfileAsn -> Bool
  (let [(p (lmk/makeLmkProfile "openai" "https://api.openai.com/v1" "gpt-4o" "sk-1234567890abcdef" (lmk/sourceUi) 4096 0.2)) (maskedAsn (lmk/formatLmkProfileAsn p true)) (unmaskedAsn (lmk/formatLmkProfileAsn p false))] (do (assert (stringStartsWith? maskedAsn "(:lmk-profile") "ASN must start with :lmk-profile") (assert (stringContains? maskedAsn ":provider \"openai\"") "ASN must contain provider") (assert (stringContains? maskedAsn ":source \"ui-override\"") "ASN must contain source") (assert (stringContains? maskedAsn ":api-key \"sk-...cdef\"") "Masked ASN must hide secret") (assert (stringContains? unmaskedAsn ":api-key \"sk-1234567890abcdef\"") "Unmasked ASN must contain raw key") true))

fn runTests -> Bool
  (and (testUiOverridePrecedence) (and (testLocalWorkspacePrecedence) (and (testGlobalUserPrecedence) (and (testEnvFallback) (and (testMaskApiKey) (testFormatLmkProfileAsn))))))
