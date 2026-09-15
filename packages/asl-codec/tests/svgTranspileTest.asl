(module asl-codec/svgTranspileTest
  :d "Unit verification test suite for ASN <-> SVG Vector Transpiler"
  :x [testAsnSvg
      testSvgAsn
      testVectorCard
      testVectorFlow
      testVectorIcon
      testVectorCompact
      testVectorFiltersAndContainers
      testSvgCompaction
      testSvgMalformed
      runSvgTests
      runTests]
  :i [(asl-codec/svgTranspile :a svg)])

(df testAsnSvg [] -> Bool
  :d "Tests transpile from compact ASN vector S-expression into valid SVG XML"
  (let [(asnInput "(:svg :w \"200\" :h \"100\" (:rect :x \"10\" :y \"10\" :w \"80\" :h \"80\" :fill \"#ff0000\"))")
        (res (svg/asnToSvg asnInput))]
    (assert (.-success res) "res must succeed")
    (assert (string-contains? (.-output res) "<svg xmlns=\"http://www.w3.org/2000/svg\"") "output must have svg tag")
    (assert (string-contains? (.-output res) "<rect") "output must have rect tag")
    (assert (string-contains? (.-output res) "</svg>") "output must close svg")
    true))

(df testSvgAsn [] -> Bool
  :d "Tests parsing raw SVG XML into compact ASN S-expression"
  (let [(svgInput "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"#00ff00\"/></svg>")
        (res (svg/svgToAsn svgInput))]
    (assert (.-success res) "res must succeed")
    (assert (string-contains? (.-output res) "(:svg") "output must have :svg")
    (assert (string-contains? (.-output res) "(:circle") "output must have :circle")
    true))

(df testVectorCard [] -> Bool
  :d "Tests responsive vector UI card generation"
  (let [(res (svg/makeVectorCard "System Status" "All nodes healthy" "#38bdf8"))]
    (assert (.-success res) "res must succeed")
    (assert (string-contains? (.-output res) "System Status") "has System Status")
    (assert (string-contains? (.-output res) "All nodes healthy") "has All nodes healthy")
    true))

(df testVectorFlow [] -> Bool
  :d "Tests flowchart vector generation"
  (let [(res (svg/makeVectorFlowchart "Input" "ASL Transpile" "Output"))]
    (assert (.-success res) "res must succeed")
    (assert (string-contains? (.-output res) "Input") "has Input")
    (assert (string-contains? (.-output res) "ASL Transpile") "has ASL Transpile")
    (assert (string-contains? (.-output res) "Output") "has Output")
    true))

(df testVectorIcon [] -> Bool
  :d "Tests standalone 24x24 vector icon generation and primitive lines/polygons"
  (let [(res (svg/makeVectorIcon "check" "M 5 12 L 10 17 L 20 6" "#22c55e"))
        (polyAsn "(:svg :w \"100\" :h \"100\" (:group (:line :x1 \"0\" :y1 \"0\" :x2 \"100\" :y2 \"100\" :sw \"2\") (:poly :points \"10,10 50,50 10,90\" :fill \"#38bdf8\")))")
        (polyRes (svg/asnToSvg polyAsn))]
    (assert (.-success res) "icon res must succeed")
    (assert (string-contains? (.-output res) "M 5 12 L 10 17 L 20 6") "icon has path")
    (assert (.-success polyRes) "poly res must succeed")
    (assert (string-contains? (.-output polyRes) "<polygon") "has polygon")
    (assert (string-contains? (.-output polyRes) "<line") "has line")
    true))

(df testVectorCompact [] -> Bool
  :d "Tests 1-token ultra-compact aliases: :rc, :circ, :p, :ln, :g, :txt, :f, :s, :sw, :sz, :v"
  (let [(compactAsn "(:svg :w \"100\" :h \"100\" :v \"0 0 100 100\" (:g (:rc :x \"5\" :y \"5\" :w \"90\" :h \"90\" :f \"#000\" :s \"#fff\" :sw \"1\") (:circ :cx \"50\" :cy \"50\" :r \"20\" :f \"#f00\") (:ln :x1 \"0\" :y1 \"0\" :x2 \"100\" :y2 \"100\" :s \"#0f0\") (:p :d \"M 10 10 L 90 90\" :s \"#00f\") (:txt :x \"50\" :y \"50\" :sz \"12\" :f \"#fff\" \"Eddie\")))")
        (res (svg/asnToSvg compactAsn))]
    (assert (.-success res) "res must succeed")
    (assert (string-contains? (.-output res) "<rect") "has rect")
    (assert (string-contains? (.-output res) "<circle") "has circle")
    (assert (string-contains? (.-output res) "<line") "has line")
    (assert (string-contains? (.-output res) "<path") "has path")
    (assert (string-contains? (.-output res) "<text") "has text")
    (assert (string-contains? (.-output res) "font-size=\"12\"") "has font-size")
    (assert (string-contains? (.-output res) "viewBox=\"0 0 100 100\"") "has viewBox")
    (assert (string-contains? (.-output res) "stroke-width=\"1\"") "has stroke-width")
    (assert (string-contains? (.-output res) "<g>") "has opening <g>")
    (assert (string-contains? (.-output res) "</g>") "has closing </g>")
    (assert (not (string-contains? (.-output res) "/>/>")) "zero double closing slashes")
    (assert (not (string-contains? (.-output res) "\"\"")) "zero duplicate quotes")
    true))

(df testVectorFiltersAndContainers [] -> Bool
  :d "Tests paired container tags and filter/gradient definitions"
  (let [(asnInput "(:svg :w 200 :h 200 :v \"0 0 200 200\" (:defs (:grad :id \"g1\" (:stop :off \"0%\" :col \"#ff0000\") (:stop :off \"100%\" :col \"#00ff00\")) (:filter :id \"glow\" (:feGaussianBlur :std-dev \"3\" :result \"b1\") (:feMerge (:feMergeNode :in \"b1\") (:feMergeNode :in \"SourceGraphic\")))) (:g (:rc :x 0 :y 0 :w 200 :h 200 :f \"url(#g1)\") (:circ :cx 100 :cy 100 :r 50 :filter \"url(#glow)\")))")
        (res (svg/asnToSvg asnInput))]
    (assert (.-success res) "res must succeed")
    (let [(xml (.-output res))]
      (assert (string-contains? xml "<defs>") "has <defs>")
      (assert (string-contains? xml "</defs>") "has </defs>")
      (assert (string-contains? xml "<linearGradient id=\"g1\">") "has <linearGradient>")
      (assert (string-contains? xml "</linearGradient>") "has </linearGradient>")
      (assert (string-contains? xml "<filter id=\"glow\">") "has <filter>")
      (assert (string-contains? xml "</filter>") "has </filter>")
      (assert (string-contains? xml "<feMerge>") "has <feMerge>")
      (assert (string-contains? xml "</feMerge>") "has </feMerge>")
      (assert (string-contains? xml "<g>") "has <g>")
      (assert (string-contains? xml "</g>") "has </g>")
      (assert (string-contains? xml "<stop offset=\"0%\" stop-color=\"#ff0000\"/>") "has clean stop 1")
      (assert (string-contains? xml "<feGaussianBlur stdDeviation=\"3\" result=\"b1\"/>") "has feGaussianBlur")
      (assert (not (string-contains? xml "/>/>")) "zero double slashes")
      (assert (not (string-contains? xml "\"\"")) "zero duplicate quotes")
      true)))

(df testSvgCompaction [] -> Bool
  :d "Verifies >= 30% token savings between raw verbose SVG XML and compact ASN"
  (let [(verboseSvg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"600\" height=\"400\" viewBox=\"0 0 600 400\"><defs><linearGradient id=\"bg\"/></defs><rect x=\"0\" y=\"0\" width=\"600\" height=\"400\" rx=\"8\" fill=\"#1e293b\" stroke=\"#38bdf8\"/><text x=\"50\" y=\"50\">Header</text></svg>")
        (res (svg/measureSvgCompaction verboseSvg))]
    (assert (.-success res) "res must succeed")
    (assert (>= (.-savingsPercent res) 30.0) "savings must be >= 30%")
    true))

(df testSvgMalformed [] -> Bool
  :d "Verifies graceful rejection of malformed or empty inputs"
  (let [(r1 (svg/asnToSvg ""))
        (r2 (svg/asnToSvg "invalid root element"))
        (r3 (svg/svgToAsn ""))
        (r4 (svg/svgToAsn "not an svg"))]
    (assert (not (.-success r1)) "r1 must fail")
    (assert (not (.-success r2)) "r2 must fail")
    (assert (not (.-success r3)) "r3 must fail")
    (assert (not (.-success r4)) "r4 must fail")
    true))

(df runSvgTests [] -> Bool
  :d "Runs all SVG transpile test cases"
  (runTests))

(df runTests [] -> Bool
  :d "Runs all SVG transpile test cases"
  (do
    (assert (testAsnSvg) "test-asn-svg must pass")
    (assert (testSvgAsn) "test-svg-asn must pass")
    (assert (testVectorCard) "test-vector-card must pass")
    (assert (testVectorFlow) "test-vector-flow must pass")
    (assert (testVectorIcon) "test-vector-icon must pass")
    (assert (testVectorCompact) "test-vector-compact must pass")
    (assert (testVectorFiltersAndContainers) "test-vector-filters-and-containers must pass")
    (assert (testSvgCompaction) "test-svg-compaction must pass")
    (assert (testSvgMalformed) "test-svg-malformed must pass")
    true))
