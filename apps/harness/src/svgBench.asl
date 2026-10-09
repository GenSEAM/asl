(module aslHarness/svgBench :x [SvgTask SvgEvalResult standardSvgTasks findSvgTask validateSvgSyntax evaluateSvgTask formatSvgReport] :i [(asl-text/string :a s) (asl-transpile/svgTranspile :a svg)])

(schema SvgTask (:f id Str) (:f title Str) (:f prompt Str) (:f complexity Str) (:f expectedTags (List Str)))

(schema SvgEvalResult (:f taskId Str) (:f validXml Bool) (:f hasViewbox Bool) (:f elementCount I64) (:f rawTokens I64) (:f asnTokens I64) (:f savingsPercent F64) (:f aestheticScore F64) (:f success Bool))

fn standardSvgTasks -> (List SvgTask)
  (list (SvgTask :id "SVG-001" :title "Geometric Minimalist Landscape" :prompt "Draw a minimalist vector landscape with a circular rising sun, layered mountain peaks using polygons, and a reflective river." :complexity "basic" :expectedTags (list "circle" "polygon" "rect")) (SvgTask :id "SVG-002" :title "Modern Chameleon Vector Logo" :prompt "Draw a modern vector logo of a chameleon with a curled tail, large round eye, and body contours using SVG paths." :complexity "intermediate" :expectedTags (list "path" "circle")) (SvgTask :id "SVG-003" :title "Dark-Mode UI Telemetry Card" :prompt "Draw a dark-mode UI metric card with rounded borders, a gradient glowing accent line, title 'Active Agents: 42', and a sparkline path." :complexity "intermediate" :expectedTags (list "rect" "linearGradient" "text" "path")) (SvgTask :id "SVG-004" :title "Agent Pipeline Flowchart Diagram" :prompt "Draw a flowchart showing three nodes: 'ASN Parser' -> 'Gemma 31B' -> 'SVG Renderer' with connecting arrows and labels." :complexity "complex" :expectedTags (list "rect" "text" "path" "line")))

fn findSvgTask tasks: (List SvgTask) id: Str -> (Option SvgTask)
  (if (= (listLength tasks) 0) (none) (let [(head (optionOr (listHead tasks) (SvgTask :id "" :title "" :prompt "" :complexity "" :expectedTags (list))))] (if (= head.id id) (some head) (findSvgTask (optionOr (listTail tasks) (list)) id))))

fn validateSvgSyntax svgStr: Str -> Bool
  (let [(trimmed (stringTrim svgStr))] (and (or (stringStartsWith? trimmed "<svg") (stringContains? trimmed "<svg")) (stringContains? trimmed "</svg>")))

fn countMatchingTags svgStr: Str tags: (List Str) -> I64
  (if (= (listLength tags) 0) 0 (let [(t (optionOr (listHead tags) "")) (matched (if (stringContains? svgStr t) 1 0))] (+ matched (countMatchingTags svgStr (optionOr (listTail tags) (list))))))

fn evaluateSvgTask task: SvgTask renderedSvg: Str -> SvgEvalResult
  (let [(isValid (validateSvgSyntax renderedSvg)) (hasVb (or (stringContains? renderedSvg "viewBox=") (and (stringContains? renderedSvg "width=") (stringContains? renderedSvg "height=")))) (totalExpected (listLength task.expectedTags)) (foundTags (countMatchingTags renderedSvg task.expectedTags)) (asnComp (svg/svgToAsn renderedSvg)) (rawTok asnComp.originalTokens) (asnTok asnComp.asnTokens) (savings asnComp.savingsPercent) (coverage (if (> totalExpected 0) (/ (int64ToFloat64 foundTags) (int64ToFloat64 totalExpected)) 0.0)) (aesthetic (if (and isValid hasVb) (if (>= coverage 1.0) 0.9 0.6) 0.2)) (success (and isValid (and hasVb (>= coverage 0.5))))] (SvgEvalResult :taskId task.id :validXml isValid :hasViewbox hasVb :elementCount foundTags :rawTokens rawTok :asnTokens asnTok :savingsPercent savings :aestheticScore aesthetic :success success))

fn formatSvgReport results: (List SvgEvalResult) -> Str
  (let [(header "| Task ID | Valid XML | ViewBox | Tag Match | Raw Tok | ASN Tok | Savings | Score | Status |\n|---|---|---|---|---|---|---|---|---|\n") (rows (formatRows results))] (s/concat header rows))

fn formatRows results: (List SvgEvalResult) -> Str
  (if (= (listLength results) 0) "" (let [(r (optionOr (listHead results) (SvgEvalResult :taskId "" :validXml false :hasViewbox false :elementCount 0 :rawTokens 0 :asnTokens 0 :savingsPercent 0.0 :aestheticScore 0.0 :success false))) (statusStr (if r.success "✓ PASS" "✗ FAIL")) (validStr (if r.validXml "YES" "NO")) (vbStr (if r.hasViewbox "YES" "NO")) (row (str "| " r.taskId " | " validStr " | " vbStr " | " (stringFromInt64 r.elementCount) " | " (stringFromInt64 r.rawTokens) " | " (stringFromInt64 r.asnTokens) " | -" (intText r.savingsPercent) "%" " | " (intText (* r.aestheticScore 100.0)) "%" " | " statusStr " |\n"))] (s/concat row (formatRows (optionOr (listTail results) (list))))))

fn intText x: F64 -> Str
  (mt (float64ToInt64 x) ((some n) (stringFromInt64 n)) ((none) (stringFromFloat64 x)))
