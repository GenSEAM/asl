(module aslHarness/tests/svgBenchTest :x [testSvgTasks testSvgSyntax testSvgEval testSvgTable testBaselineRun runTests] :i [(svgBench :a bench) (evalRunner :a runner)])

fn testSvgTasks -> Bool
  (let [(tasks (bench/standardSvgTasks))] (assert (= (listLength tasks) 4) "4 svg tasks") (assert (= (optionOr (bench/findSvgTask tasks "SVG-001") (bench/SvgTask :id "" :title "" :prompt "" :complexity "" :expectedTags (list))).id "SVG-001") "SVG-001 found") (assert (= (optionOr (bench/findSvgTask tasks "SVG-002") (bench/SvgTask :id "" :title "" :prompt "" :complexity "" :expectedTags (list))).id "SVG-002") "SVG-002 found") (assert (= (optionOr (bench/findSvgTask tasks "SVG-004") (bench/SvgTask :id "" :title "" :prompt "" :complexity "" :expectedTags (list))).id "SVG-004") "SVG-004 found") true)

fn testSvgSyntax -> Bool
  (let [(valid "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>") (unclosed "<svg viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\">") (empty "")] (assert (bench/validateSvgSyntax valid) "valid svg is valid") (assert (not (bench/validateSvgSyntax unclosed)) "unclosed svg is invalid") (assert (not (bench/validateSvgSyntax empty)) "empty svg is invalid") true)

fn testSvgEval -> Bool
  (let [(tasks (bench/standardSvgTasks)) (task (optionOr (bench/findSvgTask tasks "SVG-001") (bench/SvgTask :id "" :title "" :prompt "" :complexity "" :expectedTags (list)))) (sample "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 400 300\"><rect width=\"400\" height=\"300\" fill=\"#0f172a\"/><circle cx=\"200\" cy=\"120\" r=\"50\" fill=\"#f59e0b\"/><polygon points=\"50,300 200,160 350,300\" fill=\"#334155\"/></svg>") (result (bench/evaluateSvgTask task sample))] (assert result.success "result success") (assert result.validXml "result valid xml") (assert result.hasViewbox "result has viewbox") (assert (>= result.elementCount 3) "element count >= 3") (assert (>= result.savingsPercent 25.0) "savings percent >= 25") true)

fn testSvgTable -> Bool
  (let [(res1 (bench/SvgEvalResult :taskId "SVG-001" :validXml true :hasViewbox true :elementCount 3 :rawTokens 65 :asnTokens 38 :savingsPercent 41.5 :aestheticScore 0.85 :success true)) (table (bench/formatSvgReport (list res1)))] (assert (stringContains? table "| Task ID | Valid XML |") "table header present") (assert (stringContains? table "SVG-001") "SVG-001 present in table") (assert (stringContains? table "✓ PASS") "PASS present in table") true)

fn testBaselineRun -> Bool
  (let [(report (runner/runBaselineBenchmark))] (assert (stringContains? report "SVG-001") "report contains SVG-001") (assert (stringContains? report "SVG-002") "report contains SVG-002") (assert (stringContains? report "SVG-003") "report contains SVG-003") (assert (stringContains? report "SVG-004") "report contains SVG-004") true)

fn runTests -> Bool
  (do (testSvgTasks) (testSvgSyntax) (testSvgEval) (testSvgTable) (testBaselineRun) true)

