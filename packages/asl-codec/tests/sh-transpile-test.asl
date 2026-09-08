(module asl-codec/sh-transpile-test
  :d "Unit verification test suite for ASN <-> Safe Shell Command Transpiler"
  :x [test-escape-safe
      test-escape-special
      test-make-cmd
      test-make-pipe
      test-make-script
      test-asn-to-sh
      test-sh-to-asn
      test-sh-savings
      run-sh-tests]
  :i [(sh-transpile :a sh)])

(df test-escape-safe [] -> Bool
  :d "Tests escaping of arguments with only safe characters (no wrapping needed)"
  (let [(r1 (sh/escape-sh-arg "status"))
        (r2 (sh/escape-sh-arg "--depth=1"))
        (r3 (sh/escape-sh-arg "packages/asl-codec"))]
    (assert (= r1 "status") "Safe status arg must remain bare")
    (assert (= r2 "--depth=1") "Safe flag arg must remain bare")
    (assert (= r3 "packages/asl-codec") "Safe path arg must remain bare")
    true))

(df test-escape-special [] -> Bool
  :d "Tests escaping of arguments with spaces, dollar signs, and quotes"
  (let [(r1 (sh/escape-sh-arg "hello world"))
        (r2 (sh/escape-sh-arg "val with $VAR and 'quotes'"))]
    (assert (= r1 "'hello world'") "Spaces must be wrapped in single quotes")
    (assert (string-contains? r2 "'\\''quotes'\\''") "Embedded single quotes must be escaped")
    true))

(df test-make-cmd [] -> Bool
  :d "Tests building ASN command S-expression from binary and arguments"
  (let [(c (sh/make-cmd "git" (list "status" "-s")))]
    (assert (string-contains? c "(:cmd \"git\"") "Command must have binary git")
    (assert (string-contains? c ":args [\"status\" \"-s\"]") "Command must have status args")
    true))

(df test-make-pipe [] -> Bool
  :d "Tests building ASN pipeline S-expression"
  (let [(c1 (sh/make-cmd "find" (list "packages" "-name" "*.asl")))
        (c2 (sh/make-cmd "wc" (list "-l")))
        (p (sh/make-pipe (list c1 c2)))]
    (assert (string-starts-with? p "(:pipe") "Pipeline must start with :pipe")
    (assert (string-contains? p "find") "Pipeline must contain find")
    (assert (string-contains? p "wc") "Pipeline must contain wc")
    true))

(df test-make-script [] -> Bool
  :d "Tests building strict multi-line script S-expression"
  (let [(c1 (sh/make-cmd "asl" (list "check" "src/main.asl")))
        (c2 (sh/make-cmd "asl" (list "test" "tests/main-test.asl")))
        (scr (sh/make-script (list c1 c2) true))]
    (assert (string-contains? scr ":strict true") "Script must have strict true")
    (assert (string-contains? scr "asl") "Script must have asl commands")
    true))

(df test-asn-to-sh [] -> Bool
  :d "Tests transpilation from ASN command to executable shell string"
  (let [(cmd-asn "(:cmd \"git\" :args [\"status\" \"-s\"])")
        (res (sh/asn-to-sh cmd-asn))]
    (assert (.-success res) "Transpilation must succeed")
    (assert (string-contains? (.-output res) "git") "Output must contain git")
    true))

(df test-sh-to-asn [] -> Bool
  :d "Tests conversion of simple shell string to ASN command"
  (let [(res (sh/sh-to-asn "git commit -m initial"))]
    (assert (.-success res) "Conversion must succeed")
    (assert (string-starts-with? (.-output res) "(:cmd") "Output must be :cmd")
    true))

(df test-sh-savings [] -> Bool
  :d "Tests token estimation and savings measurement"
  (let [(res (sh/asn-to-sh "(:cmd \"ls\" :args [\"-la\"])"))]
    (assert (.-success res) "Transpilation must succeed")
    (assert (>= (.-savings-percent res) 0.0) "Savings percent must be non-negative")
    true))

(df run-sh-tests [] -> Bool
  :d "Executes all shell transpilation tests"
  (and (test-escape-safe)
       (and (test-escape-special)
            (and (test-make-cmd)
                 (and (test-make-pipe)
                      (and (test-make-script)
                           (and (test-asn-to-sh)
                                (and (test-sh-to-asn)
                                     (test-sh-savings)))))))))
