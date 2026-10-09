(module asl-transpile/svgTranspileTest :x [testAsnSvg testSvgAsn testVectorCard testVectorFlow testVectorIcon testVectorCompact testVectorFiltersAndContainers testSvgCompaction testSvgMalformed runSvgTests runTests] :i [(asl-transpile/svgTranspile :a svg)])

fn testAsnSvg -> Bool
  (let [(asnInput "(:svg :w \"200\" :h \"100\" (:rect :x \"10\" :y \"10\" :w \"80\" :h \"80\" :fill \"#ff0000\"))") (res (svg/asnToSvg asnInput))] (assert res.success "res must succeed") (assert (stringContains? res.output "<svg xmlns=\"http://www.w3.org/2000/svg\"") "output must have svg tag") (assert (stringContains? res.output "<rect") "output must have rect tag") (assert (stringContains? res.output "</svg>") "output must close svg") true)

fn testSvgAsn -> Bool
  (let [(svgInput "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"#00ff00\"/></svg>") (res (svg/svgToAsn svgInput))] (assert res.success "res must succeed") (assert (stringContains? res.output "(:svg") "output must have :svg") (assert (stringContains? res.output "(:circle") "output must have :circle") true)

fn testVectorCard -> Bool
  (let [(res (svg/makeVectorCard "System Status" "All nodes healthy" "#38bdf8"))] (assert res.success "res must succeed") (assert (stringContains? res.output "System Status") "has System Status") (assert (stringContains? res.output "All nodes healthy") "has All nodes healthy") true)

fn testVectorFlow -> Bool
  (let [(res (svg/makeVectorFlowchart "Input" "ASL Transpile" "Output"))] (assert res.success "res must succeed") (assert (stringContains? res.output "Input") "has Input") (assert (stringContains? res.output "ASL Transpile") "has ASL Transpile") (assert (stringContains? res.output "Output") "has Output") true)

fn testVectorIcon -> Bool
  (let [(res (svg/makeVectorIcon "check" "M 5 12 L 10 17 L 20 6" "#22c55e")) (polyAsn "(:svg :w \"100\" :h \"100\" (:group (:line :x1 \"0\" :y1 \"0\" :x2 \"100\" :y2 \"100\" :sw \"2\") (:poly :points \"10,10 50,50 10,90\" :fill \"#38bdf8\")))") (polyRes (svg/asnToSvg polyAsn))] (assert res.success "icon res must succeed") (assert (stringContains? res.output "M 5 12 L 10 17 L 20 6") "icon has path") (assert polyRes.success "poly res must succeed") (assert (stringContains? polyRes.output "<polygon") "has polygon") (assert (stringContains? polyRes.output "<line") "has line") true)

fn testVectorCompact -> Bool
  (let [(compactAsn "(:svg :w \"100\" :h \"100\" :v \"0 0 100 100\" (:g (:rc :x \"5\" :y \"5\" :w \"90\" :h \"90\" :f \"#000\" :s \"#fff\" :sw \"1\") (:circ :cx \"50\" :cy \"50\" :r \"20\" :f \"#f00\") (:ln :x1 \"0\" :y1 \"0\" :x2 \"100\" :y2 \"100\" :s \"#0f0\") (:p :d \"M 10 10 L 90 90\" :s \"#00f\") (:txt :x \"50\" :y \"50\" :sz \"12\" :f \"#fff\" \"Eddie\")))") (res (svg/asnToSvg compactAsn))] (assert res.success "res must succeed") (assert (stringContains? res.output "<rect") "has rect") (assert (stringContains? res.output "<circle") "has circle") (assert (stringContains? res.output "<line") "has line") (assert (stringContains? res.output "<path") "has path") (assert (stringContains? res.output "<text") "has text") (assert (stringContains? res.output "font-size=\"12\"") "has font-size") (assert (stringContains? res.output "viewBox=\"0 0 100 100\"") "has viewBox") (assert (stringContains? res.output "stroke-width=\"1\"") "has stroke-width") (assert (stringContains? res.output "<g>") "has opening <g>") (assert (stringContains? res.output "</g>") "has closing </g>") (assert (not (stringContains? res.output "/>/>")) "zero double closing slashes") (assert (not (stringContains? res.output "\"\"")) "zero duplicate quotes") true)

fn testVectorFiltersAndContainers -> Bool
  (let [(asnInput "(:svg :w 200 :h 200 :v \"0 0 200 200\" (:defs (:grad :id \"g1\" (:stop :off \"0%\" :col \"#ff0000\") (:stop :off \"100%\" :col \"#00ff00\")) (:filter :id \"glow\" (:feGaussianBlur :std-dev \"3\" :result \"b1\") (:feMerge (:feMergeNode :in \"b1\") (:feMergeNode :in \"SourceGraphic\")))) (:g (:rc :x 0 :y 0 :w 200 :h 200 :f \"url(#g1)\") (:circ :cx 100 :cy 100 :r 50 :filter \"url(#glow)\")))") (res (svg/asnToSvg asnInput))] (assert res.success "res must succeed") (let [(xml res.output)] (assert (stringContains? xml "<defs>") "has <defs>") (assert (stringContains? xml "</defs>") "has </defs>") (assert (stringContains? xml "<linearGradient id=\"g1\">") "has <linearGradient>") (assert (stringContains? xml "</linearGradient>") "has </linearGradient>") (assert (stringContains? xml "<filter id=\"glow\">") "has <filter>") (assert (stringContains? xml "</filter>") "has </filter>") (assert (stringContains? xml "<feMerge>") "has <feMerge>") (assert (stringContains? xml "</feMerge>") "has </feMerge>") (assert (stringContains? xml "<g>") "has <g>") (assert (stringContains? xml "</g>") "has </g>") (assert (stringContains? xml "<stop offset=\"0%\" stop-color=\"#ff0000\"/>") "has clean stop 1") (assert (stringContains? xml "<feGaussianBlur stdDeviation=\"3\" result=\"b1\"/>") "has feGaussianBlur") (assert (not (stringContains? xml "/>/>")) "zero double slashes") (assert (not (stringContains? xml "\"\"")) "zero duplicate quotes") true))

fn testSvgCompaction -> Bool
  (let [(verboseSvg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"600\" height=\"400\" viewBox=\"0 0 600 400\"><defs><linearGradient id=\"bg\"/></defs><rect x=\"0\" y=\"0\" width=\"600\" height=\"400\" rx=\"8\" fill=\"#1e293b\" stroke=\"#38bdf8\"/><text x=\"50\" y=\"50\">Header</text></svg>") (res (svg/measureSvgCompaction verboseSvg))] (assert res.success "res must succeed") (assert (>= res.savingsPercent 30.0) "savings must be >= 30%") true)

fn testSvgMalformed -> Bool
  (let [(r1 (svg/asnToSvg "")) (r2 (svg/asnToSvg "invalid root element")) (r3 (svg/svgToAsn "")) (r4 (svg/svgToAsn "not an svg"))] (assert (not r1.success) "r1 must fail") (assert (not r2.success) "r2 must fail") (assert (not r3.success) "r3 must fail") (assert (not r4.success) "r4 must fail") true)

fn runSvgTests -> Bool
  (runTests)

fn runTests -> Bool
  (do (assert (testAsnSvg) "test-asn-svg must pass") (assert (testSvgAsn) "test-svg-asn must pass") (assert (testVectorCard) "test-vector-card must pass") (assert (testVectorFlow) "test-vector-flow must pass") (assert (testVectorIcon) "test-vector-icon must pass") (assert (testVectorCompact) "test-vector-compact must pass") (assert (testVectorFiltersAndContainers) "test-vector-filters-and-containers must pass") (assert (testSvgCompaction) "test-svg-compaction must pass") (assert (testSvgMalformed) "test-svg-malformed must pass") true)
