(module asl-help/help-test
  :d "Comprehensive Unit Test Suite for ASN Help System"
  :x [run-tests]
  :i [(help_node :a hn) (registry :a reg)])

(df test-help-node-construction [] -> Bool
  :d "Verifies HelpNode record constructor correctly sets all fields."
  (let [(node (hn/make-help-node "pmap" "concurrency" "0.3.3" "(df {A B} pmap [(fn [A] -> B) (List A)] -> (List B))" "Applies pure function concurrently across list items." (list "Lambda MUST NOT contain effect marker '!'" "Preserves strict element ordering") "(pmap (fn [x] (* x 2)) '(1 2 3))" 14))]
    (assert (= (.-sym node) "pmap") "HelpNode sym must match pmap")
    (assert (= (.-cat node) "concurrency") "HelpNode cat must match concurrency")
    (assert (= (.-ver node) "0.3.3") "HelpNode ver must match 0.3.3")
    (assert (= (list-length (.-constraints node)) 2) "HelpNode constraints list length must equal 2")
    (assert (= (.-cost-tokens node) 14) "HelpNode cost-tokens must match 14")
    true))

(df test-help-node-formatting-and-parsing [] -> Bool
  :d "Verifies HelpNode serialization and deserialization roundtrip."
  (let [(node (hn/make-help-node "test-sym" "test-cat" "0.3.3" "(df test-sym [] -> Str)" "Test summary." (list "test-constraint") "(test-sym)" 14))
        (formatted (hn/format-help-node node))
        (parsed (hn/parse-help-node formatted))
        (malformed (hn/parse-help-node "invalid CS expression stub"))]
    (assert (string-contains? formatted "(:help-node :sym \"test-sym\"") "Formatted string must contain (:help-node :sym test-sym")
    (assert (string-contains? formatted ":cost-tokens 14") "Formatted string must contain :cost-tokens 14")
    (assert (is-some? parsed) "parse-help-node must return some for well-formed CS-expression")
    (assert (= (.-sym (option-or parsed (hn/make-empty-help-node))) "test-sym") "Parsed node sym must match original test-sym")
    (assert (is-none? malformed) "parse-help-node must return none for malformed string")
    true))

(df test-registry-core-primitives [] -> Bool
  :d "Verifies all 7 core primitives are discoverable in registry."
  (assert (is-some? (reg/lookup-help-node "pmap")) "pmap must be present in core catalog")
  (assert (is-some? (reg/lookup-help-node "par-all!")) "par-all! must be present in core catalog")
  (assert (is-some? (reg/lookup-help-node "load!")) "load! must be present in core catalog")
  (assert (is-some? (reg/lookup-help-node "call!")) "call! must be present in core catalog")
  (assert (is-some? (reg/lookup-help-node "mem")) "mem must be present in core catalog")
  (assert (is-some? (reg/lookup-help-node "assert-facts-retained")) "assert-facts-retained must be present in core catalog")
  (assert (is-some? (reg/lookup-help-node "help!")) "help! must be present in core catalog")
  true)

(df test-registry-node-content-and-signatures [] -> Bool
  :d "Verifies node fields, taxonomies, and signatures for primitives."
  (let [(pmap-opt (reg/lookup-help-node "pmap"))
        (mem-opt (reg/lookup-help-node "mem"))
        (help-opt (reg/lookup-help-node "help!"))
        (pmap-node (option-or pmap-opt (hn/make-empty-help-node)))
        (mem-node (option-or mem-opt (hn/make-empty-help-node)))
        (help-node (option-or help-opt (hn/make-empty-help-node)))]
    (assert (= (.-cat pmap-node) "concurrency") "pmap category must be concurrency")
    (assert (string-contains? (.-sig pmap-node) "(df {A B} pmap") "pmap signature must contain (df {A B} pmap")
    (assert (= (.-cat mem-node) "memory") "mem category must be memory")
    (assert (= (.-cat help-node) "help") "help! category must be help")
    true))

(df test-unknown-symbol-handling [] -> Bool
  :d "Verifies unknown primitive lookups and empty input return none or ERR_UNKNOWN_SYMBOL."
  (let [(missing-opt (reg/lookup-help-node "nonexistent-primitive-xyz"))
        (missing-msg (reg/help! "nonexistent-primitive-xyz"))
        (empty-opt (reg/lookup-help-node ""))]
    (assert (is-none? missing-opt) "Lookup for unknown primitive must return none")
    (assert (= missing-msg ":ERR_UNKNOWN_SYMBOL") "help! for unknown primitive must return :ERR_UNKNOWN_SYMBOL")
    (assert (is-none? empty-opt) "Lookup for empty string must return none")
    true))

(df test-token-cost-bounds [] -> Bool
  :d "Verifies that all core primitive passport token costs stay within budget <= 25 tokens."
  (let [(pmap-node (option-or (reg/lookup-help-node "pmap") (hn/make-empty-help-node)))
        (par-node (option-or (reg/lookup-help-node "par-all!") (hn/make-empty-help-node)))
        (load-node (option-or (reg/lookup-help-node "load!") (hn/make-empty-help-node)))
        (call-node (option-or (reg/lookup-help-node "call!") (hn/make-empty-help-node)))]
    (assert (<= (.-cost-tokens pmap-node) 25) "pmap token cost must be <= 25 tokens")
    (assert (<= (.-cost-tokens par-node) 25) "par-all! token cost must be <= 25 tokens")
    (assert (<= (.-cost-tokens load-node) 25) "load! token cost must be <= 25 tokens")
    (assert (<= (.-cost-tokens call-node) 25) "call! token cost must be <= 25 tokens")
    true))

(df run-tests [] -> Bool
  :d "Runs all falsifiable test suites for help node and help registry."
  (and (test-help-node-construction)
       (and (test-help-node-formatting-and-parsing)
            (and (test-registry-core-primitives)
                 (and (test-registry-node-content-and-signatures)
                      (and (test-unknown-symbol-handling)
                           (test-token-cost-bounds)))))))

(run-tests)
