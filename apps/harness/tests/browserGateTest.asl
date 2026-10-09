(module aslHarness/tests/browserGateTest :x [runTests] :i [(browserGate :a bg)])

fn testSvgClean -> Bool
  (let [(code "<svg viewBox=\"0 0 320 320\"><rect x=\"0\" y=\"0\" width=\"320\" height=\"320\" /></svg>") (res (bg/runBrowserGates code "svg"))] (assert res.passed "clean SVG passes gates") (assert (stringEmpty? res.healingDirective) "healing directive empty") true)

fn testAsnUnbalanced -> Bool
  (let [(code "(:svg :w 320 (:rc :x 0") (v (bg/checkSyntaxGate code "svg"))] (assert (not v.passed) "unbalanced ASN fails syntax gate") (assert (bg/checkSyntaxGate "(:svg :w 320 (:rc :x 0))" "svg").passed "balanced ASN passes syntax gate") true)

fn testSecurityEval -> Bool
  (let [(code "function foo() { eval('alert(1)'); }") (v (bg/checkSecurityGate code))] (assert (not v.passed) "eval call fails security gate") (assert (bg/checkSecurityGate "function foo() { return 1; }").passed "clean code passes security gate") true)

fn testGamesReadiness -> Bool
  (let [(code "<canvas id=\"game\"></canvas><script>console.log('idle');</script>") (v (bg/checkReadinessGate code "games"))] (assert (not v.passed) "missing rAF fails games readiness gate") (assert (bg/checkReadinessGate "<canvas id=\"game\"></canvas><script>requestAnimationFrame(loop);</script>" "games").passed "games with rAF passes readiness gate") true)

fn runTests -> Bool
  (do (testSvgClean) (testAsnUnbalanced) (testSecurityEval) (testGamesReadiness) true)
