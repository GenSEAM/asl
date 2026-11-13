(module asl-checker/unknownTypeSignatureTest :x [runTests] :i [(asl-checker/check :a c) (asl-checker/types :a ty)])

; (:m :ref CHECKER-unknownTypeName :do "an undefined type name in a signature, schema field or enum payload is ERR_UNKNOWN_TYPE from checkFile!, the path asl check reports; rule-10 used to be filtered out as a lint so a misspelt type silently degraded to no checking")
fn ! checkSnippet! tag: String src: String -> (List ty/Diagnostic)
  (let [(path (str (optionOr (envGet "TMPDIR") "/tmp/") "unknownTypeSignature_" tag "_" (stringFromInt64 (nowNs)) ".asl"))
        (_wrote (fileWrite path src))
        (ds (resultOr (c/checkFile! path (list ".")) (list)))
        (_cleaned (pathRemove path))]
    ds)

fn unknownTypeNamed? ds: (List ty/Diagnostic) name: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "ERR_UNKNOWN_TYPE") (stringContains? d.message name))) ds)

fn diagnosticsText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn ! runTests -> Bool
  (let [(ret (checkSnippet! "ret" "(module p/tp :x [f])\n\nfn f -> Stringing\n  \"a\"\n"))
        (param (checkSnippet! "param" "(module p/tp :x [f])\n\nfn f x: Intt -> Int64\n  1\n"))
        (field (checkSnippet! "field" "(module p/tp :x [S])\n\n(schema S (:f a Strng))\n"))
        (enumPayload (checkSnippet! "enum" "(module p/tp :x [E])\n\n(enum E (:c cA [(x Bogus)] \"doc\"))\n"))
        (known (checkSnippet! "known" "(module p/tp :x [f])\n\nfn f x: (List T) -> String\n  \"a\"\n"))
        (known2 (checkSnippet! "known2" "(module p/tp :x [f])\n\n(schema S (:f a String))\n\nfn f x: S -> (Option Int64)\n  none\n"))
        (prelude (checkSnippet! "prelude" "(module p/tp :x [d])\n\nfn d t: (PreludeTree K V) -> Int64\n  0\n"))
        (noRet (checkSnippet! "noRet" "(module p/tp :x [g])\n\nfn g x: Any\n  x\n"))]
    (do
      (assert (unknownTypeNamed? ret "Stringing") (str "an unknown return type is ERR_UNKNOWN_TYPE naming it: " (diagnosticsText ret)))
      (assert (unknownTypeNamed? param "Intt") (str "an unknown parameter type is ERR_UNKNOWN_TYPE: " (diagnosticsText param)))
      (assert (unknownTypeNamed? field "Strng") (str "an unknown schema field type is ERR_UNKNOWN_TYPE: " (diagnosticsText field)))
      (assert (unknownTypeNamed? enumPayload "Bogus") (str "an unknown enum payload type is ERR_UNKNOWN_TYPE: " (diagnosticsText enumPayload)))
      (assert (listEmpty? known) (str "a typevar and builtin types are not flagged: " (diagnosticsText known)))
      (assert (listEmpty? known2) (str "a schema declared in the module is a known type: " (diagnosticsText known2)))
      (assert (listEmpty? prelude) (str "the prelude enum PreludeTree is a known type: " (diagnosticsText prelude)))
      (assert (not (unknownTypeNamed? noRet ":inferredUnit")) (str "the no-return-type marker is not reported as a type: " (diagnosticsText noRet)))
      true))
