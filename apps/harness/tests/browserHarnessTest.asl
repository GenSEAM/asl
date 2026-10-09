(module aslHarnessTests/browserHarnessTest :x [testMakeBrowserAction testVerifySlmCoherenceValidClick testVerifySlmCoherenceUnbalancedDelimiters testVerifySlmCoherenceGhostRejection testExecuteHarnessTurnGrounding testBenchmarkSlmCoherence runTests] :i [(aslHarness/browserHarness :a bh) (asl-text/string :a s)])

fn testMakeBrowserAction -> Bool
  (let [(act (bh/makeBrowserAction (bh/actClick) "#btn-save" "" "tab-101"))] (assert (= act.selector "#btn-save") "selector matches") (assert (= act.tabId "tab-101") "tab id matches") true)

fn testVerifySlmCoherenceValidClick -> Bool
  (let [(sample "(! browser_click :selector \"#checkout-btn\")") (verdict (bh/verifySlmCoherence sample "tab-101"))] (assert verdict.isCoherent "valid click is coherent") (assert (match verdict.action ((none) false) ((some act) (and (= act.selector "#checkout-btn") (= act.tabId "tab-101")))) "action matched checkout-btn") true)

fn testVerifySlmCoherenceUnbalancedDelimiters -> Bool
  (let [(badSample "(! browser_click :selector \"#checkout-btn\"") (verdict (bh/verifySlmCoherence badSample "tab-101"))] (assert (not verdict.isCoherent) "unbalanced delimiters rejected") (assert (stringContains? verdict.errorReason "Unbalanced delimiters") "error reason notes unbalanced") true)

fn testVerifySlmCoherenceGhostRejection -> Bool
  (let [(ghostSample "(! hack-root :target \"system\")") (verdict (bh/verifySlmCoherence ghostSample "tab-101"))] (assert (not verdict.isCoherent) "ghost action rejected") (assert (stringContains? verdict.errorReason "ghost action") "error reason notes ghost action") true)

fn testExecuteHarnessTurnGrounding -> Bool
  (let [(dom "<div id=\"root\"><button id=\"btn-apply\">Apply</button></div>") (validTurn (bh/executeHarnessTurn dom "(! browser_click :selector \"#btn-apply\")" "tab-101")) (hallucinatedTurn (bh/executeHarnessTurn dom "(! browser_click :selector \"#ghost-btn\")" "tab-101"))] (assert validTurn.isCoherent "valid turn grounded in DOM") (assert (not hallucinatedTurn.isCoherent) "ungrounded turn rejected") (assert (stringContains? hallucinatedTurn.errorReason "not grounded in active DOM") "reason notes not grounded") true)

fn testBenchmarkSlmCoherence -> Bool
  (let [(samples (list "(! browser_click :selector \"#btn\")" "(! browser_type :selector \"#input\" :text \"val\")" "(! bad-unbalanced (" "(! hack-root :now true)")) (bench (bh/benchmarkSlmCoherence samples))] (assert (= (pairFirst bench) 2) "two valid coherent samples") (assert (= (pairSecond bench) 50.0) "50 percent coherence score") true)

fn runTests -> Bool
  (do (testMakeBrowserAction) (testVerifySlmCoherenceValidClick) (testVerifySlmCoherenceUnbalancedDelimiters) (testVerifySlmCoherenceGhostRejection) (testExecuteHarnessTurnGrounding) (testBenchmarkSlmCoherence) true)
