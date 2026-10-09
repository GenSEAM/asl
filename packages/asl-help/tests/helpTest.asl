(module asl-help/helpTest :x [runTests] :i [(helpNode :a hn) (registry :a reg)])

fn testHelpNodeConstruction -> Bool
  (let [(node (hn/makeHelpNode "pmap" "concurrency" "0.3.3" "(df {A B} pmap [(fn [A] -> B) (List A)] -> (List B))" "Applies pure function concurrently across list items." (list "Lambda MUST NOT contain effect marker '!'" "Preserves strict element ordering") "(pmap (fn [x] (* x 2)) '(1 2 3))" 14))] (assert (= node.sym "pmap") "HelpNode sym must match pmap") (assert (= node.cat "concurrency") "HelpNode cat must match concurrency") (assert (= node.ver "0.3.3") "HelpNode ver must match 0.3.3") (assert (= (listLength node.constraints) 2) "HelpNode constraints list length must equal 2") (assert (= node.costTokens 14) "HelpNode cost-tokens must match 14") true)

fn testHelpNodeFormattingAndParsing -> Bool
  (let [(node (hn/makeHelpNode "test-sym" "test-cat" "0.3.3" "(df test-sym [] -> Str)" "Test summary." (list "test-constraint") "(test-sym)" 14)) (formatted (hn/formatHelpNode node)) (parsed (hn/parseHelpNode formatted)) (malformed (hn/parseHelpNode "invalid CS expression stub"))] (assert (stringContains? formatted "(:help-node :sym \"test-sym\"") "Formatted string must contain (:help-node :sym test-sym") (assert (stringContains? formatted ":cost-tokens 14") "Formatted string must contain :cost-tokens 14") (assert (some? parsed) "parse-help-node must return some for well-formed CS-expression") (assert (= (optionOr parsed (hn/makeEmptyHelpNode)).sym "test-sym") "Parsed node sym must match original test-sym") (assert (none? malformed) "parse-help-node must return none for malformed string") true)

fn testRegistryCorePrimitives -> Bool
  (do (assert (some? (reg/lookupHelpNode "pmap")) "pmap must be present in core catalog") (assert (some? (reg/lookupHelpNode "par-all!")) "par-all! must be present in core catalog") (assert (some? (reg/lookupHelpNode "load!")) "load! must be present in core catalog") (assert (some? (reg/lookupHelpNode "call!")) "call! must be present in core catalog") (assert (some? (reg/lookupHelpNode "mem")) "mem must be present in core catalog") (assert (some? (reg/lookupHelpNode "assert-facts-retained")) "assert-facts-retained must be present in core catalog") (assert (some? (reg/lookupHelpNode "help!")) "help! must be present in core catalog") true)

fn testRegistryNodeContentAndSignatures -> Bool
  (let [(pmapOpt (reg/lookupHelpNode "pmap")) (memOpt (reg/lookupHelpNode "mem")) (helpOpt (reg/lookupHelpNode "help!")) (pmapNode (optionOr pmapOpt (hn/makeEmptyHelpNode))) (memNode (optionOr memOpt (hn/makeEmptyHelpNode))) (helpNode (optionOr helpOpt (hn/makeEmptyHelpNode)))] (assert (= pmapNode.cat "concurrency") "pmap category must be concurrency") (assert (stringContains? pmapNode.sig "(fn {A B} pmap") "pmap signature must contain (fn {A B} pmap") (assert (= memNode.cat "memory") "mem category must be memory") (assert (= helpNode.cat "help") "help! category must be help") true)

fn testUnknownSymbolHandling! -> Bool
  (let [(missingOpt (reg/lookupHelpNode "nonexistent-primitive-xyz")) (missingMsg (reg/help! "nonexistent-primitive-xyz")) (emptyOpt (reg/lookupHelpNode ""))] (assert (none? missingOpt) "Lookup for unknown primitive must return none") (assert (= missingMsg ":ERR_UNKNOWN_SYMBOL") "help! for unknown primitive must return :ERR_UNKNOWN_SYMBOL") (assert (none? emptyOpt) "Lookup for empty string must return none") true)

fn testTokenCostBounds -> Bool
  (let [(pmapNode (optionOr (reg/lookupHelpNode "pmap") (hn/makeEmptyHelpNode))) (parNode (optionOr (reg/lookupHelpNode "par-all!") (hn/makeEmptyHelpNode))) (loadNode (optionOr (reg/lookupHelpNode "load!") (hn/makeEmptyHelpNode))) (callNode (optionOr (reg/lookupHelpNode "call!") (hn/makeEmptyHelpNode)))] (assert (<= pmapNode.costTokens 25) "pmap token cost must be <= 25 tokens") (assert (<= parNode.costTokens 25) "par-all! token cost must be <= 25 tokens") (assert (<= loadNode.costTokens 25) "load! token cost must be <= 25 tokens") (assert (<= callNode.costTokens 25) "call! token cost must be <= 25 tokens") true)

fn ! runTests -> Bool
  (and (testHelpNodeConstruction) (and (testHelpNodeFormattingAndParsing) (and (testRegistryCorePrimitives) (and (testRegistryNodeContentAndSignatures) (and (testUnknownSymbolHandling!) (testTokenCostBounds))))))
