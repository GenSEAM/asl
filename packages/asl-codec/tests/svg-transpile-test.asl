(module asl-codec/svg-transpile-test
  :d "Unit verification test suite for ASN <-> SVG Vector Transpiler"
  :x [test-asn-svg
      test-svg-asn
      test-vector-card
      test-vector-flow
      test-vector-icon
      test-vector-compact
      test-svg-compaction
      test-svg-malformed
      run-svg-tests]
  :i [(svg-transpile :a svg)])

(df test-asn-svg [] -> Bool
  :d "Tests transpile from compact ASN vector S-expression into valid SVG XML"
  (let [(asn-input "(:svg :w \"200\" :h \"100\" (:rect :x \"10\" :y \"10\" :w \"80\" :h \"80\" :fill \"#ff0000\"))")
        (res (svg/asn-to-svg asn-input))]
    (and (.-success res)
         (and (string-contains? (.-output res) "<svg xmlns=\"http://www.w3.org/2000/svg\"")
              (and (string-contains? (.-output res) "<rect")
                   (string-contains? (.-output res) "</svg>"))))))

(df test-svg-asn [] -> Bool
  :d "Tests parsing raw SVG XML into compact ASN S-expression"
  (let [(svg-input "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"#00ff00\"/></svg>")
        (res (svg/svg-to-asn svg-input))]
    (and (.-success res)
         (and (string-contains? (.-output res) "(:svg")
              (string-contains? (.-output res) "(:circle")))))

(df test-vector-card [] -> Bool
  :d "Tests responsive vector UI card generation"
  (let [(res (svg/make-vector-card "System Status" "All nodes healthy" "#38bdf8"))]
    (and (.-success res)
         (and (string-contains? (.-output res) "System Status")
              (string-contains? (.-output res) "All nodes healthy")))))

(df test-vector-flow [] -> Bool
  :d "Tests flowchart vector generation"
  (let [(res (svg/make-vector-flowchart "Input" "ASL Transpile" "Output"))]
    (and (.-success res)
         (and (string-contains? (.-output res) "Input")
              (and (string-contains? (.-output res) "ASL Transpile")
                   (string-contains? (.-output res) "Output"))))))

(df test-vector-icon [] -> Bool
  :d "Tests standalone 24x24 vector icon generation and primitive lines/polygons"
  (let [(res (svg/make-vector-icon "check" "M 5 12 L 10 17 L 20 6" "#22c55e"))
        (poly-asn "(:svg :w \"100\" :h \"100\" (:group (:line :x1 \"0\" :y1 \"0\" :x2 \"100\" :y2 \"100\" :sw \"2\") (:poly :points \"10,10 50,50 10,90\" :fill \"#38bdf8\")))")
        (poly-res (svg/asn-to-svg poly-asn))]
    (and (and (.-success res)
              (string-contains? (.-output res) "M 5 12 L 10 17 L 20 6"))
         (and (.-success poly-res)
              (and (string-contains? (.-output poly-res) "<polygon")
                   (string-contains? (.-output poly-res) "<line"))))))

(df test-vector-compact [] -> Bool
  :d "Tests 1-token ultra-compact aliases: :rc, :circ, :p, :ln, :g, :txt, :f, :s, :sw, :sz, :v"
  (let [(compact-asn "(:svg :w \"100\" :h \"100\" :v \"0 0 100 100\" (:g (:rc :x \"5\" :y \"5\" :w \"90\" :h \"90\" :f \"#000\" :s \"#fff\" :sw \"1\") (:circ :cx \"50\" :cy \"50\" :r \"20\" :f \"#f00\") (:ln :x1 \"0\" :y1 \"0\" :x2 \"100\" :y2 \"100\" :s \"#0f0\") (:p :d \"M 10 10 L 90 90\" :s \"#00f\") (:txt :x \"50\" :y \"50\" :sz \"12\" :f \"#fff\" \"Eddie\")))")
        (res (svg/asn-to-svg compact-asn))]
    (and (.-success res)
         (and (string-contains? (.-output res) "<rect")
              (and (string-contains? (.-output res) "<circle")
                   (and (string-contains? (.-output res) "<line")
                        (and (string-contains? (.-output res) "<path")
                             (and (string-contains? (.-output res) "<text")
                                  (and (string-contains? (.-output res) "font-size=\"12\"")
                                       (and (string-contains? (.-output res) "viewBox=\"0 0 100 100\"")
                                            (string-contains? (.-output res) "stroke-width=\"1\"")))))))))))

(df test-svg-compaction [] -> Bool
  :d "Verifies >= 30% token savings between raw verbose SVG XML and compact ASN"
  (let [(verbose-svg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"600\" height=\"400\" viewBox=\"0 0 600 400\"><defs><linearGradient id=\"bg\"/></defs><rect x=\"0\" y=\"0\" width=\"600\" height=\"400\" rx=\"8\" fill=\"#1e293b\" stroke=\"#38bdf8\"/><text x=\"50\" y=\"50\">Header</text></svg>")
        (res (svg/measure-svg-compaction verbose-svg))]
    (and (.-success res)
         (>= (.-savings-percent res) 30.0))))

(df test-svg-malformed [] -> Bool
  :d "Verifies graceful rejection of malformed or empty inputs"
  (let [(r1 (svg/asn-to-svg ""))
        (r2 (svg/asn-to-svg "invalid root element"))
        (r3 (svg/svg-to-asn ""))
        (r4 (svg/svg-to-asn "not an svg"))]
    (and (not (.-success r1))
         (and (not (.-success r2))
              (and (not (.-success r3))
                   (not (.-success r4)))))))

(df run-svg-tests [] -> Bool
  :d "Runs all SVG transpile test cases"
  (and (test-asn-svg)
       (and (test-svg-asn)
            (and (test-vector-card)
                 (and (test-vector-flow)
                      (and (test-vector-icon)
                           (and (test-vector-compact)
                                (and (test-svg-compaction)
                                     (test-svg-malformed)))))))))
