(module aslHarness/slmBrowserProfileTest :x [testBrowserToolsSchema testAffirmativeSchema testBrowserProfileInstantiation testFsmDelimiterMaskBalanced testFsmDelimiterMaskUnbalanced testFsmDelimiterMaskMaxDepth testNanoBrowserProfile testBrowserCeilingEnforcement runTests] :i [(slmBrowserProfile :a slm)])

fn testBrowserToolsSchema -> Bool
  (let [(tools (slm/makeBrowserSlmTools)) (tDom (optionOr (listHead tools) (slm/SlmBrowserTool :name "" :signature "" :summary "" :tokenCost 0))) (tokens (slm/calculateSchemaTokens tools))] (assert (= (listLength tools) 4) "Browser SLM tool count must be exactly 4") (assert (= tDom.name "get_dom") "First tool must be get_dom") (assert (<= tokens 118) "Total schema token cost must not exceed 118 tokens") (assert (> tokens 0) "Schema token cost must be positive") (assert (stringContains? tDom.signature ":get_dom") "Signature must contain action name") true)

fn testAffirmativeSchema -> Bool
  (let [(schema (slm/makeBrowserSlmSchema))] (assert (= schema.maxTools 4) "Max tools limit must be 4") (assert (= schema.totalTokens 64) "Expected 64 token budget for essential 4 tools") (assert (stringContains? schema.affirmativeRule "Never hallucinate") "Affirmative rule must enforce no hallucinations") true)

fn testBrowserProfileInstantiation -> Bool
  (let [(p (slm/makeBrowserSlmProfile "Qwen2.5-0.5B" 2048))] (assert (= p.modelName "Qwen2.5-0.5B") "Model name must match") (assert (= p.contextBudget 2048) "Context budget must match 2048") (assert (= p.primingTokenCount 118) "Priming token count must be 118") (assert (stringContains? p.primingPrompt "Addie Browser SLM Agent") "Priming prompt must identify agent") true)

fn testFsmDelimiterMaskBalanced -> Bool
  (let [(mask (slm/initFsmDelimiterMask 16)) (s1 "(:act :click :selector btn)") (r1 (slm/validateSlmTokenStream mask s1)) (s2 "[:act :eval :expression [query document]]") (r2 (slm/validateSlmTokenStream mask s2))] (assert r1.isValid "Standard action must be valid") (assert (= r1.depth 0) "Depth must return to zero on balanced completion") (assert (not r1.inString) "Must not remain in string literal") (assert r2.isValid "Nested square bracket S-expression must be valid") (assert (= r2.depth 0) "Nested depth must be zero") true)

fn testFsmDelimiterMaskUnbalanced -> Bool
  (let [(mask (slm/initFsmDelimiterMask 16)) (rUnclosed (slm/validateSlmTokenStream mask "(:act :click :selector btn")) (rExtra (slm/validateSlmTokenStream mask "(:act :click))")) (rBracket (slm/validateSlmTokenStream mask "[:act :click :selector btn"))] (assert (not rUnclosed.isValid) "Unclosed delimiter must be marked invalid") (assert (stringContains? rUnclosed.errorReason "Unclosed delimiter") "Error reason must report unclosed delimiter") (assert (not rExtra.isValid) "Extra closing paren must be marked invalid") (assert (stringContains? rExtra.errorReason "Unmatched closing delimiter") "Error reason must report unmatched closing delimiter") (assert (not rBracket.isValid) "Unclosed square bracket must be marked invalid") true)

fn testFsmDelimiterMaskMaxDepth -> Bool
  (let [(shallowMask (slm/initFsmDelimiterMask 2)) (rDeep (slm/validateSlmTokenStream shallowMask "((((x))))"))] (assert (not rDeep.isValid) "Exceeding max depth must be rejected") (assert (stringContains? rDeep.errorReason "Max nesting depth") "Error must identify max depth violation") true)

fn testNanoBrowserProfile -> Bool
  (let [(tools (slm/makeNanoSlmTools)) (schema (slm/makeNanoSlmSchema)) (p (slm/makeNanoBrowserSlmProfile "SmolLM-135M" 1024))] (assert (= (listLength tools) 2) "Nano SLM tool count must be exactly 2") (assert (<= schema.totalTokens 36) "Nano schema token cost must not exceed 36 tokens") (assert (= p.primingTokenCount 30) "Nano priming token count must be 30") (assert (stringContains? p.primingPrompt "100MB") "Nano priming prompt must specify 100MB weight") true)

fn testBrowserCeilingEnforcement -> Bool
  (do (assert (slm/validateBrowserModelCeiling "SmolLM-135M") "100MB nano model is allowed") (assert (slm/validateBrowserModelCeiling "Qwen2.5-0.5B") "0.5B micro model is allowed") (assert (slm/validateBrowserModelCeiling "Qwen2.5-1.5B") "1.5B model is allowed") (assert (slm/validateBrowserModelCeiling "Qwen2.5-3B") "3B ceiling model is allowed") (assert (not (slm/validateBrowserModelCeiling "Qwen2.5-7B")) "7B model must be strictly rejected") (assert (not (slm/validateBrowserModelCeiling "Gemma-2-9B")) "9B model must be strictly rejected") (assert (not (slm/validateBrowserModelCeiling "Gemma-4-31B")) "31B model must be strictly rejected") true)

fn runTests -> Bool
  (and (testBrowserToolsSchema) (and (testAffirmativeSchema) (and (testBrowserProfileInstantiation) (and (testFsmDelimiterMaskBalanced) (and (testFsmDelimiterMaskUnbalanced) (and (testFsmDelimiterMaskMaxDepth) (and (testNanoBrowserProfile) (testBrowserCeilingEnforcement))))))))
