(module aslHarness/browserGate :x [GateVerdict VerificationResult runBrowserGates checkSyntaxGate checkSecurityGate checkReadinessGate] :i [])

(schema GateVerdict (:f gateNum I64) (:f name Str) (:f passed Bool) (:f summary Str))

(schema VerificationResult (:f passed Bool) (:f verdicts (List GateVerdict)) (:f sanitizedCode Str) (:f healingDirective Str))

fn checkSyntaxGate code: Str env: Str -> GateVerdict
  (if (= env "svg") (if (stringStartsWith? code "(:") (let [(open (stringCountChar code "(")) (close (stringCountChar code ")")) (balanced (= open close))] (GateVerdict :gateNum 1 :name "ASN Form Balance" :passed balanced :summary (if balanced "All S-expression parentheses are balanced." "Unbalanced ASN S-expression."))) (let [(valid (and (stringContains? code "<svg") (stringContains? code "</svg>")))] (GateVerdict :gateNum 1 :name "SVG XML Structure" :passed valid :summary (if valid "Valid <svg> ... </svg> root tags confirmed." "Missing opening or closing <svg> tags.")))) (let [(valid (or (stringContains? code "<div") (or (stringContains? code "<canvas") (stringContains? code "<script"))))] (GateVerdict :gateNum 1 :name "HTML/JS Structure" :passed valid :summary (if valid "Standard DOM/Canvas/Script structure recognized." "No recognized DOM structure."))))

fn checkSecurityGate code: Str -> GateVerdict
  (let [(hasEval (stringContains? code "eval(")) (hasFunc (stringContains? code "Function(")) (hasDel (stringContains? code "indexedDB.deleteDatabase")) (safe (not (or hasEval (or hasFunc hasDel))))] (GateVerdict :gateNum 2 :name "Sandbox Security" :passed safe :summary (if safe "Zero restricted APIs detected." "Prohibited API execution detected.")))

fn checkReadinessGate code: Str env: Str -> GateVerdict
  (if (= env "svg") (let [(ready (or (stringContains? code "viewBox") (or (stringContains? code ":v") (stringContains? code ":w"))))] (GateVerdict :gateNum 3 :name "ViewBox Calibration" :passed ready :summary (if ready "Viewport dimensions calibrated." "Missing viewBox or dimensions."))) (let [(ready (and (stringContains? code "<canvas") (or (stringContains? code "requestAnimationFrame") (stringContains? code "setInterval"))))] (GateVerdict :gateNum 3 :name "Game Loop Readiness" :passed ready :summary (if ready "Canvas and animation loop confirmed." "Missing canvas or animation loop."))))

fn runBrowserGates code: Str env: Str -> VerificationResult
  (let [(sanitized (stringTrim code)) (g1 (checkSyntaxGate sanitized env)) (g2 (checkSecurityGate sanitized)) (g3 (checkReadinessGate sanitized env)) (allPassed (and g1.passed (and g2.passed g3.passed))) (healing (if allPassed "" (if (not g2.passed) "Fix security: Remove restricted API calls. Use local memory and canvas APIs." (if (not g1.passed) "Fix syntax: Balance all parentheses or enclose inside valid root tags." "Fix readiness: Calibrate viewBox 0 0 320 320 or add game animation loop."))))] (VerificationResult :passed allPassed :verdicts (list g1 g2 g3) :sanitizedCode sanitized :healingDirective healing))
