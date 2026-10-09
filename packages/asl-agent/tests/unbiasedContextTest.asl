(module aslAgent/tests/unbiasedContextTest
  :x [testRefutePersonaPreamble testSanitizeObservation testBuildUnbiasedContextFrame runTests]
  :i [(asl/packages/asl-agent/src/unbiasedContext :a uc)
      (asl/packages/asl-agent/src/omniIntent :a oi)])

fn testRefutePersonaPreamble -> Bool
  (let [(bad1 "You are an expert coder. Sure, I can help with this refactor.")
        (bad2 "As an AI assistant, I would be happy to write that test.")
        (good1 "(:task :file \"src/core.asl\" :anchor \"fn-main\" :gate \"./bin/asl test\")")
        (good2 "refactor compiler in engine/asl.c")]
    (refute (uc/refutePersonaPreamble bad1) "Must reject persona preamble: You are an expert")
    (refute (uc/refutePersonaPreamble bad2) "Must reject persona preamble: As an AI assistant")
    (assert (uc/refutePersonaPreamble good1) "Must accept clean ASN task")
    (assert (uc/refutePersonaPreamble good2) "Must accept directive without persona fluff")
    true)

fn testSanitizeObservation -> Bool
  (let [(raw "Sure! Here is the output:\nexit: 0, asserts: 18 passed cleanly.")
        (sanitized (uc/sanitizeObservation raw))]
    (assert (stringContains? sanitized "exit: 0") "Contains exit code metric")
    (assert (not (stringContains? sanitized "Here is the output")) "Preamble stripped")
    (assert (not (stringContains? sanitized "Sure!")) "Greeting stripped")
    true)

fn testBuildUnbiasedContextFrame -> Bool
  (let [(intent (oi/classifyOmniIntent "refactor the compiler in engine/asl.c"))
        (symbols (list "compiler" "compilePackageToLlvm!"))
        (obs (list "exit: 0, asserts: 18"))
        (attractors (list ":simplicity" ":verification" ":containment"))
        (owns (list "src/compiler.asl"))
        (frame (uc/buildUnbiasedContextFrame intent symbols obs attractors owns))
        (formatted (uc/formatUnbiasedContextFrame frame))]
    (assert (= (listLength frame.symbols) 2) "Frame has 2 symbols")
    (assert (= (listLength frame.observations) 1) "Frame has 1 observation")
    (assert (stringContains? formatted ":unbiased-context-frame") "Formatted contains frame tag")
    (assert (stringContains? formatted ":intent") "Formatted contains intent")
    (assert (stringContains? formatted ":symbols") "Formatted contains symbols")
    (assert (stringContains? formatted ":attractors") "Formatted contains attractors")
    true)

fn runTests -> Bool
  (do
    (assert (testRefutePersonaPreamble) "Refute persona preamble must pass")
    (assert (testSanitizeObservation) "Sanitize observation must pass")
    (assert (testBuildUnbiasedContextFrame) "Build unbiased context frame must pass")
    true)
