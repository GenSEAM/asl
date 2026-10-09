(module asl-cli/tests/checkTest :x [runTests] :i [(asl-cli/check :a chk)])

fn testCleanCheck -> Bool
  (let [(cleanSrc "(module test/clean :x [good] :i [])\n\nfn good -> Int64\n  42\n")
        (res (chk/checkSourceWithFix "test/clean.asl" cleanSrc false))]
    (assert (ok? res) "clean check must succeed")
    (mt res
      ((ok msg) (assert (stringContains? msg "Semantic check passed cleanly") "clean check success msg"))
      ((err errStr) (assert false (str "clean check should not fail, got: " errStr))))
    true)

fn testTypeMismatchCheck -> Bool
  (let [(badSrc "(module test/bad :x [] :i [])\n\nfn bad -> Int64\n  \"hello\"\n")
        (res (chk/checkSourceWithFix "test/bad.asl" badSrc false))]
    (assert (err? res) "type mismatch must fail check")
    (mt res
      ((ok _) (assert false "type mismatch must not pass check"))
      ((err msg)
       (do
         (assert (stringContains? msg "test/bad.asl:") "error message has path and location")
         (assert (stringContains? msg "type") "error message has diagnostic code")
         (assert (stringContains? msg "expected Int64, found String") "error message has type mismatch detail"))))
    true)

fn testUnknownSymbolCheck -> Bool
  (let [(badSrc "(module test/bad :x [] :i [])\n\nfn bad -> Int64\n  unknownVar\n")
        (res (chk/checkSourceWithFix "test/bad.asl" badSrc false))]
    (assert (err? res) "unknown symbol must fail check")
    (mt res
      ((ok _) (assert false "unknown symbol must not pass check"))
      ((err msg)
       (do
         (assert (stringContains? msg "test/bad.asl:") "error message has path and location")
         (assert (stringContains? msg "unknownVar is not defined") "error message specifies undefined symbol"))))
    true)

fn testRule8WarningPasses -> Bool
  (let [(noDocSrc "(module test/nodoc :x [f] :i [])\n\nfn f -> Int64\n  42\n")
        (res (chk/checkSourceWithFix "test/nodoc.asl" noDocSrc false))]
    (assert (ok? res) "an exported fn without a source doc passes check")
    (mt res
      ((ok msg) (refute (stringContains? msg "rule-8") (str "no rule-8 warning: docs live in doc.asn (D158), got: " msg)))
      ((err errStr) (assert false (str "an exported fn without a source doc should not fail, got: " errStr))))
    true)

fn mismatchMessage src: String -> String
  (mt (chk/checkSourceWithFix "test/mm.asl" src false) ((ok msg) (str "PASSED " msg)) ((err msg) msg))

fn testMismatchDirection! -> Bool
  (let [(argMsg (mismatchMessage "(module test/mm :x [] :i [])\n\nfn g x: Int64 -> Int64\n  x\n\nfn h -> Int64\n  (g \"str\")\n"))
        (numMsg (mismatchMessage "(module test/mm :x [] :i [])\n\nfn h -> Int64\n  (+ 1 \"two\")\n"))]
    (do
      (assert (stringContains? argMsg "expected Int64, found String") (str "argument mismatch names the parameter type as expected, got " argMsg))
      (assert (stringContains? numMsg "expected an integer, found String") (str "arithmetic mismatch names the number as expected, got " numMsg))
      (assert (err? (chk/runCheckCommand! (list "--fix" "test/mm.asl"))) "check --fix is not implemented and must fail")
      true))

fn ! runTests -> Bool
  (and (testCleanCheck) (and (testTypeMismatchCheck) (and (testUnknownSymbolCheck) (and (testRule8WarningPasses) (testMismatchDirection!)))))
