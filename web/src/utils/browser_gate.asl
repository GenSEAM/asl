(module asl-harness/browser-gate
  :d "Pure AgentScript In-Browser Verification Gate & Adaptive Self-Healing Engine"
  :x [GateVerdict VerificationResult run-browser-gates]
  :i [])

(dfs GateVerdict
  (:f gate-num I64 "Gate index (1: Syntax, 2: Security, 3: Readiness)")
  (:f name Str "Gate canonical title")
  (:f passed Bool "Verification outcome")
  (:f summary Str "Human-readable summary explanation"))

(dfs VerificationResult
  (:f passed Bool "Overall verification outcome (true if all 3 gates pass)")
  (:f verdicts (List GateVerdict) "Per-gate breakdown")
  (:f sanitized-code Str "Processed code payload")
  (:f healing-directive Str "Adaptive self-healing prompt if failed"))

(df check-syntax-gate [(code Str) (env Str)] -> GateVerdict
  :d "Gate 1: Checks structural balance, ASN delimiters, or DOM tags"
  (if (= env "svg")
    (if (string-starts-with? code "(:")
      (let [(open (string-count-char code "("))
            (close (string-count-char code ")"))
            (balanced (= open close))]
        (GateVerdict
          :gate-num 1
          :name "ASN Form Balance"
          :passed balanced
          :summary (if balanced "All S-expression parentheses are balanced." "Unbalanced ASN S-expression.")))
      (let [(valid (and (string-contains? code "<svg") (string-contains? code "</svg>")))]
        (GateVerdict
          :gate-num 1
          :name "SVG XML Structure"
          :passed valid
          :summary (if valid "Valid <svg> ... </svg> root tags confirmed." "Missing opening or closing <svg> tags."))))
    (let [(valid (or (string-contains? code "<div") (or (string-contains? code "<canvas") (string-contains? code "<script"))))]
      (GateVerdict
        :gate-num 1
        :name "HTML/JS Structure"
        :passed valid
        :summary (if valid "Standard DOM/Canvas/Script structure recognized." "No recognized DOM structure.")))))

(df check-security-gate [(code Str)] -> GateVerdict
  :d "Gate 2: Enforces sandbox security policy prohibiting unsafe APIs"
  (let [(has-eval (string-contains? code "eval("))
        (has-func (string-contains? code "Function("))
        (has-del (string-contains? code "indexedDB.deleteDatabase"))
        (safe (not (or has-eval (or has-func has-del))))]
    (GateVerdict
      :gate-num 2
      :name "Sandbox Security"
      :passed safe
      :summary (if safe "Zero restricted APIs detected." "Prohibited API execution detected."))))

(df check-readiness-gate [(code Str) (env Str)] -> GateVerdict
  :d "Gate 3: Confirms viewport calibration and animation/game loops"
  (if (= env "svg")
    (let [(ready (or (string-contains? code "viewBox") (or (string-contains? code ":v") (string-contains? code ":w"))))]
      (GateVerdict
        :gate-num 3
        :name "ViewBox Calibration"
        :passed ready
        :summary (if ready "Viewport dimensions calibrated." "Missing viewBox or dimensions.")))
    (let [(ready (and (string-contains? code "<canvas") (or (string-contains? code "requestAnimationFrame") (string-contains? code "setInterval"))))]
      (GateVerdict
        :gate-num 3
        :name "Game Loop Readiness"
        :passed ready
        :summary (if ready "Canvas and animation loop confirmed." "Missing canvas or animation loop.")))))

(df run-browser-gates [(code Str) (env Str)] -> VerificationResult
  :d "Executes 3-tier browser verification suite and produces healing directive"
  (let [(sanitized (string-trim code))
        (g1 (check-syntax-gate sanitized env))
        (g2 (check-security-gate sanitized))
        (g3 (check-readiness-gate sanitized env))
        (all-passed (and (.-passed g1) (and (.-passed g2) (.-passed g3))))
        (healing (if all-passed
                   ""
                   (if (not (.-passed g2))
                     "Fix security: Remove restricted API calls. Use local memory and canvas APIs."
                     (if (not (.-passed g1))
                       "Fix syntax: Balance all parentheses or enclose inside valid root tags."
                       "Fix readiness: Calibrate viewBox 0 0 320 320 or add game animation loop."))))]
    (VerificationResult
      :passed all-passed
      :verdicts (list g1 g2 g3)
      :sanitized-code sanitized
      :healing-directive healing)))
