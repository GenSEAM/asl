(module asl-help/helpTest
  :d "Comprehensive Unit Test Suite for ASN Help System"
  :x [runTests]
  :i [(help_node :a hn) (registry :a reg)])

(df testHelpNodeConstruction [] -> Bool
  :d "Verifies HelpNode record constructor correctly sets all fields."
  (let [(node (hn/makeHelpNode "pmap" "concurrency" "0.3.3" "(df {A B} pmap [(fn [A] -> B) (List A)] -> (List B))" "Applies pure function concurrently across list items." (list "Lambda MUST NOT contain effect marker '!'" "Preserves strict element ordering") "(pmap (fn [x] (* x 2)) '(1 2 3))" 14))]
    (assert (= (.-sym node) "pmap") "HelpNode sym must match pmap")
    (assert (= (.-cat node) "concurrency") "HelpNode cat must match concurrency")
    (assert (= (.-ver node) "0.3.3") "HelpNode ver must match 0.3.3")
    (assert (= (list-length (.-constraints node)) 2) "HelpNode constraints list length must equal 2")
    (assert (= (.-costTokens node) 14) "HelpNode cost-tokens must match 14")
    true))

(df testHelpNodeFormattingAndParsing [] -> Bool
  :d "Verifies HelpNode serialization and deserialization roundtrip."
  (let [(node (hn/makeHelpNode "test-sym" "test-cat" "0.3.3" "(df test-sym [] -> Str)" "Test summary." (list "test-constraint") "(test-sym)" 14))
        (formatted (hn/formatHelpNode node))
        (parsed (hn/parseHelpNode formatted))
        (malformed (hn/parseHelpNode "invalid CS expression stub"))]
    (assert (string-contains? formatted "(:help-node :sym \"test-sym\"") "Formatted string must contain (:help-node :sym test-sym")
    (assert (string-contains? formatted ":cost-tokens 14") "Formatted string must contain :cost-tokens 14")
    (assert (is-some? parsed) "parse-help-node must return some for well-formed CS-expression")
    (assert (= (.-sym (option-or parsed (hn/makeEmptyHelpNode))) "test-sym") "Parsed node sym must match original test-sym")
    (assert (is-none? malformed) "parse-help-node must return none for malformed string")
    true))

(df testRegistryCorePrimitives [] -> Bool
  :d "Verifies all 7 core primitives are discoverable in registry."
  (assert (is-some? (reg/lookupHelpNode "pmap")) "pmap must be present in core catalog")
  (assert (is-some? (reg/lookupHelpNode "par-all!")) "par-all! must be present in core catalog")
  (assert (is-some? (reg/lookupHelpNode "load!")) "load! must be present in core catalog")
  (assert (is-some? (reg/lookupHelpNode "call!")) "call! must be present in core catalog")
  (assert (is-some? (reg/lookupHelpNode "mem")) "mem must be present in core catalog")
  (assert (is-some? (reg/lookupHelpNode "assert-facts-retained")) "assert-facts-retained must be present in core catalog")
  (assert (is-some? (reg/lookupHelpNode "help!")) "help! must be present in core catalog")
  true)

(df testRegistryNodeContentAndSignatures [] -> Bool
  :d "Verifies node fields, taxonomies, and signatures for primitives."
  (let [(pmapOpt (reg/lookupHelpNode "pmap"))
        (memOpt (reg/lookupHelpNode "mem"))
        (helpOpt (reg/lookupHelpNode "help!"))
        (pmapNode (option-or pmapOpt (hn/makeEmptyHelpNode)))
        (memNode (option-or memOpt (hn/makeEmptyHelpNode)))
        (helpNode (option-or helpOpt (hn/makeEmptyHelpNode)))]
    (assert (= (.-cat pmapNode) "concurrency") "pmap category must be concurrency")
    (assert (string-contains? (.-sig pmapNode) "(df {A B} pmap") "pmap signature must contain (df {A B} pmap")
    (assert (= (.-cat memNode) "memory") "mem category must be memory")
    (assert (= (.-cat helpNode) "help") "help! category must be help")
    true))

(df testUnknownSymbolHandling [] -> Bool
  :d "Verifies unknown primitive lookups and empty input return none or ERR_UNKNOWN_SYMBOL."
  (let [(missingOpt (reg/lookupHelpNode "nonexistent-primitive-xyz"))
        (missingMsg (reg/help! "nonexistent-primitive-xyz"))
        (emptyOpt (reg/lookupHelpNode ""))]
    (assert (is-none? missingOpt) "Lookup for unknown primitive must return none")
    (assert (= missingMsg ":ERR_UNKNOWN_SYMBOL") "help! for unknown primitive must return :ERR_UNKNOWN_SYMBOL")
    (assert (is-none? emptyOpt) "Lookup for empty string must return none")
    true))

(df testTokenCostBounds [] -> Bool
  :d "Verifies that all core primitive passport token costs stay within budget <= 25 tokens."
  (let [(pmapNode (option-or (reg/lookupHelpNode "pmap") (hn/makeEmptyHelpNode)))
        (parNode (option-or (reg/lookupHelpNode "par-all!") (hn/makeEmptyHelpNode)))
        (loadNode (option-or (reg/lookupHelpNode "load!") (hn/makeEmptyHelpNode)))
        (callNode (option-or (reg/lookupHelpNode "call!") (hn/makeEmptyHelpNode)))]
    (assert (<= (.-costTokens pmapNode) 25) "pmap token cost must be <= 25 tokens")
    (assert (<= (.-costTokens parNode) 25) "par-all! token cost must be <= 25 tokens")
    (assert (<= (.-costTokens loadNode) 25) "load! token cost must be <= 25 tokens")
    (assert (<= (.-costTokens callNode) 25) "call! token cost must be <= 25 tokens")
    true))

(df runTests [] -> Bool
  :d "Runs all falsifiable test suites for help node and help registry."
  (and (testHelpNodeConstruction)
       (and (testHelpNodeFormattingAndParsing)
            (and (testRegistryCorePrimitives)
                 (and (testRegistryNodeContentAndSignatures)
                      (and (testUnknownSymbolHandling)
                           (testTokenCostBounds)))))))

(runTests)
