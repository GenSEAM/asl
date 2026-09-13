(module asl-codec/shTranspileTest
  :d "Unit verification test suite for ASN <-> Safe Shell Command Transpiler"
  :x [testEscapeSafe
      testEscapeSpecial
      testMakeCmd
      testMakePipe
      testMakeScript
      testAsnToSh
      testShToAsn
      testShSavings
      runShTests]
  :i [(asl-codec/shTranspile :a sh)
      (asl-text/escape :a esc)])

(df testEscapeSafe [] -> Bool
  :d "Tests escaping of arguments with only safe characters (no wrapping needed)"
  (let [(r1 (esc/escapeShCompact "status"))
        (r2 (esc/escapeShCompact "--depth=1"))
        (r3 (esc/escapeShCompact "packages/asl-codec"))]
    (assert (= r1 "status") "Safe status arg must remain bare")
    (assert (= r2 "--depth=1") "Safe flag arg must remain bare")
    (assert (= r3 "packages/asl-codec") "Safe path arg must remain bare")
    true))

(df testEscapeSpecial [] -> Bool
  :d "Tests escaping of arguments with spaces, dollar signs, and quotes"
  (let [(r1 (esc/escapeShCompact "hello world"))
        (r2 (esc/escapeShCompact "val with $VAR and 'quotes'"))]
    (assert (= r1 "'hello world'") "Spaces must be wrapped in single quotes")
    (assert (string-contains? r2 "'\\''quotes'\\''") "Embedded single quotes must be escaped")
    true))

(df testMakeCmd [] -> Bool
  :d "Tests building ASN command S-expression from binary and arguments"
  (let [(c (sh/makeCmd "git" (list "status" "-s")))]
    (assert (string-contains? c "(:cmd \"git\"") "Command must have binary git")
    (assert (string-contains? c ":args [\"status\" \"-s\"]") "Command must have status args")
    true))

(df testMakePipe [] -> Bool
  :d "Tests building ASN pipeline S-expression"
  (let [(c1 (sh/makeCmd "find" (list "packages" "-name" "*.asl")))
        (c2 (sh/makeCmd "wc" (list "-l")))
        (p (sh/makePipe (list c1 c2)))]
    (assert (string-starts-with? p "(:pipe") "Pipeline must start with :pipe")
    (assert (string-contains? p "find") "Pipeline must contain find")
    (assert (string-contains? p "wc") "Pipeline must contain wc")
    true))

(df testMakeScript [] -> Bool
  :d "Tests building strict multi-line script S-expression"
  (let [(c1 (sh/makeCmd "asl" (list "check" "src/main.asl")))
        (c2 (sh/makeCmd "asl" (list "test" "tests/main-test.asl")))
        (scr (sh/makeScript (list c1 c2) true))]
    (assert (string-contains? scr ":strict true") "Script must have strict true")
    (assert (string-contains? scr "asl") "Script must have asl commands")
    true))

(df testAsnToSh [] -> Bool
  :d "Tests transpilation from ASN command to executable shell string"
  (let [(cmdAsn "(:cmd \"git\" :args [\"status\" \"-s\"])")
        (res (sh/asnToSh cmdAsn))
        (resSh (sh/asnToSh "(:sh \"echo \\\"hello world\\\"\")"))
        (resQuoted (sh/asnToSh "(:cmd \"echo\" :args [\"\\\"hello world\\\"\"])"))]
    (assert (.-success res) "Transpilation must succeed")
    (assert (string-contains? (.-output res) "git") "Output must contain git")
    (assert (.-success resSh) "Transpilation of :sh form must succeed")
    (assert (string-contains? (.-output resSh) "\"hello world\"") "Sh form must preserve quotes")
    (assert (.-success resQuoted) "Transpilation of :cmd form with quotes must succeed")
    (assert (string-contains? (.-output resQuoted) "\"hello world\"") "Cmd form must preserve quotes")
    true))

(df testShToAsn [] -> Bool
  :d "Tests conversion of simple shell string to ASN command"
  (let [(res (sh/shToAsn "git commit -m initial"))]
    (assert (.-success res) "Conversion must succeed")
    (assert (string-starts-with? (.-output res) "(:cmd") "Output must be :cmd")
    true))

(df testShSavings [] -> Bool
  :d "Tests token estimation and savings measurement"
  (let [(res (sh/asnToSh "(:cmd \"ls\" :args [\"-la\"])"))]
    (assert (.-success res) "Transpilation must succeed")
    (assert (>= (.-savingsPercent res) 0.0) "Savings percent must be non-negative")
    true))

(df runShTests [] -> Bool
  :d "Executes all shell transpilation tests"
  (and (testEscapeSafe)
       (and (testEscapeSpecial)
            (and (testMakeCmd)
                 (and (testMakePipe)
                      (and (testMakeScript)
                           (and (testAsnToSh)
                                (and (testShToAsn)
                                     (testShSavings)))))))))
