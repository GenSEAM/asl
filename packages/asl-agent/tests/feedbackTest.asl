(module aslAgent/feedbackTest :x [testAmbiguityDetection testStripPoliteFluff testRefinePrompt testClarifyingQuestionFormat testConciseDirectiveFormat runTests] :i [(feedback :a fb)])

fn testAmbiguityDetection -> Bool
  (let [(shortP (fb/isAmbiguousPrompt? "fix bug")) (noFileP (fb/isAmbiguousPrompt? "please optimize this calculation")) (clearP (fb/isAmbiguousPrompt? "run tests on src/main.asl and fix assertion"))] (assert shortP "short prompt without target should be ambiguous") (assert noFileP "prompt without file should be ambiguous") (assert (not clearP) "prompt with file and action should not be ambiguous") true)

fn testStripPoliteFluff -> Bool
  (let [(fluffy "Certainly! I'd be happy to help with that. Please update policy.asl") (clean (fb/stripPoliteFluff fluffy))] (assert (not (stringContains? clean "Certainly")) "strip polite fluff removes Certainly") (assert (stringContains? clean "Please update policy.asl") "strip polite fluff keeps core content") true)

fn testRefinePrompt -> Bool
  (let [(req (fb/refineUserPrompt "Refactor eddie/src/agent.asl with new methods" (list "eddie/src/agent.asl")))] (assert (not req.isAmbiguous) "specific request is not ambiguous") (assert (= (listLength req.targetFiles) 1) "exactly one target file") true)

fn testClarifyingQuestionFormat -> Bool
  (let [(req (fb/refineUserPrompt "make game" (list))) (opts (list (fb/ClarificationOption :key "1" :label "Terminal Snake in ASL") (fb/ClarificationOption :key "2" :label "Text RPG in TypeScript"))) (q (fb/formatClarifyingQuestion req opts))] (assert (stringContains? q "Need clarification") "contains clarification heading") (assert (stringContains? q "[1] Terminal Snake in ASL") "contains option 1") (assert (stringContains? q "[2] Text RPG in TypeScript") "contains option 2") true)

fn testConciseDirectiveFormat -> Bool
  (let [(req (fb/refineUserPrompt "Patch the harness repl.asl module" (list "harness/src/repl.asl"))) (dir (fb/formatConciseDirective req))] (assert (stringContains? dir "Goal: Patch the harness repl.asl module") "contains goal") (assert (stringContains? dir "Targets: 1 files") "contains target file count") true)

fn runTests -> Bool
  (do (testAmbiguityDetection) (testStripPoliteFluff) (testRefinePrompt) (testClarifyingQuestionFormat) (testConciseDirectiveFormat) true)
