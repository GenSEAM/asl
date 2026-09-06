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
    (and (= r1 "status")
         (and (= r2 "--depth=1")
              (= r3 "packages/asl-codec")))))

(df test-escape-special [] -> Bool
  :d "Tests escaping of arguments with spaces, dollar signs, and quotes"
  (let [(r1 (sh/escape-sh-arg "hello world"))
        (r2 (sh/escape-sh-arg "val with $VAR and 'quotes'"))]
    (and (= r1 "'hello world'")
         (string-contains? r2 "'\\''quotes'\\''"))))

(df test-make-cmd [] -> Bool
  :d "Tests building ASN command S-expression from binary and arguments"
  (let [(c (sh/make-cmd "git" (list "status" "-s")))]
    (and (string-contains? c "(:cmd \"git\"")
         (string-contains? c ":args [\"status\" \"-s\"]"))))

(df test-make-pipe [] -> Bool
  :d "Tests building ASN pipeline S-expression"
  (let [(c1 (sh/make-cmd "find" (list "packages" "-name" "*.asl")))
        (c2 (sh/make-cmd "wc" (list "-l")))
        (p (sh/make-pipe (list c1 c2)))]
    (and (string-starts-with? p "(:pipe")
         (and (string-contains? p "find")
              (string-contains? p "wc")))))

(df test-make-script [] -> Bool
  :d "Tests building strict multi-line script S-expression"
  (let [(c1 (sh/make-cmd "asl" (list "check" "src/main.asl")))
        (c2 (sh/make-cmd "asl" (list "test" "tests/main-test.asl")))
        (scr (sh/make-script (list c1 c2) true))]
    (and (string-contains? scr ":strict true")
         (string-contains? scr "asl"))))

(df test-asn-to-sh [] -> Bool
  :d "Tests transpilation from ASN command to executable shell string"
  (let [(cmd-asn "(:cmd \"git\" :args [\"status\" \"-s\"])")
        (res (sh/asn-to-sh cmd-asn))]
    (and (.-success res)
         (string-contains? (.-output res) "git"))))

(df test-sh-to-asn [] -> Bool
  :d "Tests conversion of simple shell string to ASN command"
  (let [(res (sh/sh-to-asn "git commit -m initial"))]
    (and (.-success res)
         (string-starts-with? (.-output res) "(:cmd"))))

(df test-sh-savings [] -> Bool
  :d "Tests token estimation and savings measurement"
  (let [(res (sh/asn-to-sh "(:cmd \"ls\" :args [\"-la\"])"))]
    (and (.-success res)
         (>= (.-savings-percent res) 0.0))))

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
