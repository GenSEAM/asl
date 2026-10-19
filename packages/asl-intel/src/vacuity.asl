(module asl-intel/vacuity
  :x [VacuitySummary analyzeVacuity! vacuityJson formatVacuityAsn formatVacuitySummary runVacuity!]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/host :a h)
      (asl-intel/deadcode :a dc)])

(schema Vac
  (:f file String)
  (:f function String))

(schema Triv
  (:f file String)
  (:f function String)
  (:f returnType String)
  (:f body String))

(schema VacuitySummary
  (:f testFiles Int64)
  (:f assertions Int64)
  (:f vacuous (List Vac))
  (:f trivial (List Triv)))

fn vacReason -> String
  "Trivial return without executed assertions (D81 vacuous pass fraud)"

fn trivReason -> String
  "Production test runner stub returning constant true without assertions"

fn vacuousIn! code: String rel: String -> (List Vac)
  (let [(b (stringToBytes code))]
    (fold (fn [(acc (List Vac)) (caps (List Int64))] -> (List Vac)
            (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))
                  (body (optionOr (r/rexGroup code caps 2) ""))]
              (if (and (not (stringContains? body "assert")) (and (not (stringContains? body "refute"))
                       (listContains? (list "true" "nil" "()" "0") (t/pyStrip body))))
                (listAppend acc (list (Vac :file rel :function name)))
                acc)))
          (list) (r/rexFindAll (p/patVacTestFn!) b (bytesLength b))))

fn trivialIn! code: String rel: String -> (List Triv)
  (let [(b (stringToBytes code))]
    (fold (fn [(acc (List Triv)) (caps (List Int64))] -> (List Triv)
            (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))
                  (ret (t/pyStrip (optionOr (r/rexGroup code caps 2) "")))
                  (body (t/pyStrip (optionOr (r/rexGroup code caps 3) "")))]
              (if (and (stringStartsWith? (t/lowerAscii name) "runtest") (listContains? (list "true" "nil" "(ok true)") body))
                (listAppend acc (list (Triv :file rel :function name :returnType ret :body body)))
                acc)))
          (list) (r/rexFindAll (p/patVacProdStub!) b (bytesLength b))))

fn assertWords code: String -> Int64
  (let [(b (stringToBytes code)) (n (bytesLength b)) (a (stringToBytes "assert")) (rf (stringToBytes "refute"))]
    (+ (t/wordHits b n a 6 0 9223372036854775807 0) (t/wordHits b n rf 6 0 9223372036854775807 0)))

; (:m :ref MAINFIX14-TRACKEDASL-20261019 :do "dc/trackedAsl! (git ls-files, not find) so a gitignored fixture artifact left in .asl/cache/<suite>/*.asl by another suite running in parallel is never in scope -- see deadcode.asl MAINFIX14-TRACKEDASL-20261019")
fn analyzeVacuity! ctx: h/Ctx root: String -> (Result VacuitySummary String)
  (mt (dc/trackedAsl! ctx root)
    ((err e) (err e))
    ((ok files)
      (ok (fold (fn [(st VacuitySummary) (rel String)] -> VacuitySummary
                  (let [(full (if (stringStartsWith? rel "/") rel (t/joinPath root rel)))]
                    (mt (h/readText! full)
                      ((err _) st)
                      ((ok code)
                        ; (:m :ref MAINFIX1-VACFIXTURE-20261018 :do "the fixtures/corpus-invalid exclusion used to come second in this cond, so it was dead for any fixture whose path also contains /tests/ or whose name ends Test.asl -- true of every deliberate negative-control fixture built to BE vacuous for the scanner's own test suite (noAsserts.asl, zeroTest.asl, zeroAssertsTest.asl, zeroAssertTest.asl all live under a tests/ or fixtures/ dir and are conventionally *Test.asl so suite runners can find them), so all four were scanned as real test files and flagged as production vacuous-test debt instead of being skipped. Checking the exclusion first restores the intended precedence: a fixture is a fixture first, a test-suite candidate only once it is not one. tests/acceptance/r1Host/runner/ is the same kind of fixture set under a different name: 9 negative-control files run.sh drives to probe the R1 runner's own honesty (documented 'U4 I5' in .asl/mem/docs/tests.asn), zeroAssertsTest.asl among them deliberately returning true after zero asserts -- added alongside /fixtures/ rather than invented as a new convention")
                        (cond
                          ((or (stringContains? rel "/fixtures/") (or (stringContains? rel "corpus/invalid") (stringContains? rel "/r1Host/runner/"))) st)
                          ((or (stringContains? rel "/tests/") (stringEndsWith? rel "Test.asl"))
                            (VacuitySummary :testFiles (+ st.testFiles 1) :assertions (+ st.assertions (assertWords code))
                                       :vacuous (listAppend st.vacuous (vacuousIn! code rel)) :trivial st.trivial))
                          (else (VacuitySummary :testFiles st.testFiles :assertions st.assertions :vacuous st.vacuous
                                           :trivial (listAppend st.trivial (trivialIn! code rel)))))))))
                (VacuitySummary :testFiles 0 :assertions 0 :vacuous (list) :trivial (list)) files))))

fn formatVacuityAsn res: VacuitySummary -> String
  (t/joinWith (list "(:vacuityAudit" "  :status :ok"
                    (str "  :testFilesScanned " (t/intStr res.testFiles))
                    (str "  :totalAssertions " (t/intStr res.assertions))
                    (str "  :vacuousTestsCount " (t/intStr (listLength res.vacuous)))
                    (str "  :trivialStubsCount " (t/intStr (listLength res.trivial)))
                    (str "  :assertCount " (t/intStr res.assertions))
                    (if (listEmpty? res.vacuous) "  :vacuousTests []"
                      (str "  :vacuousTests [\n    " (t/joinWith (map (fn [(v Vac)] -> String (str "(:file \"" v.file "\" :function \"" v.function "\" :reason \"" (vacReason) "\")")) res.vacuous) "\n    ") "\n  ]"))
                    (if (listEmpty? res.trivial) "  :trivialStubs []"
                      (str "  :trivialStubs [\n    " (t/joinWith (map (fn [(s Triv)] -> String (str "(:file \"" s.file "\" :function \"" s.function "\" :body \"" s.body "\")")) res.trivial) "\n    ") "\n  ]"))
                    ")")
              "\n")

fn formatVacuitySummary res: VacuitySummary -> String
  (t/joinWith (listAppend
                (list "=== ASL TEST VACUITY & TRIVIAL STUB AUDIT (ADR D81) ==="
                      (str "Test Suites Scanned: " (t/intStr res.testFiles))
                      (str "Executed Assertions: " (t/intStr res.assertions) " (Must be > 0)")
                      (str "Vacuous Test Stubs:  " (t/intStr (listLength res.vacuous)))
                      (str "Production Stubs:    " (t/intStr (listLength res.trivial))))
                (listAppend
                  (if (listEmpty? res.vacuous) (list)
                    (cons "" (cons "--- Vacuous Tests (Zero Executed Assertions) ---"
                      (map (fn [(v Vac)] -> String (str "  • " v.file " [" v.function "]: " (vacReason))) res.vacuous))))
                  (if (listEmpty? res.trivial) (list)
                    (cons "" (cons "--- Trivial Constant Stubs ---"
                      (map (fn [(s Triv)] -> String (str "  • " s.file " [" s.function "]: returns " s.body)) res.trivial))))))
              "\n")

fn vacuityJson res: VacuitySummary -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok"))
                (pair "testFilesScanned" (j/jInt res.testFiles))
                (pair "totalAssertions" (j/jInt res.assertions))
                (pair "vacuousTestsCount" (j/jInt (listLength res.vacuous)))
                (pair "vacuousTests" (j/jArr (map (fn [(v Vac)] -> j/Json (j/jObj (list (pair "file" (j/jStr v.file)) (pair "function" (j/jStr v.function)) (pair "reason" (j/jStr (vacReason)))))) res.vacuous)))
                (pair "trivialStubsCount" (j/jInt (listLength res.trivial)))
                (pair "trivialStubs" (j/jArr (map (fn [(s Triv)] -> j/Json (j/jObj (list (pair "file" (j/jStr s.file)) (pair "function" (j/jStr s.function)) (pair "returnType" (j/jStr s.returnType)) (pair "body" (j/jStr s.body)) (pair "reason" (j/jStr (trivReason)))))) res.trivial)))))

fn runVacuity! ctx: h/Ctx fmt: String strict: Bool -> h/Outcome
  (mt (analyzeVacuity! ctx ctx.home)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok res)
      (let [(out (str (cond ((= fmt "json") (j/dumps (vacuityJson res))) ((= fmt "summary") (formatVacuitySummary res)) (else (formatVacuityAsn res))) "\n"))
            (nv (listLength res.vacuous)) (ns (listLength res.trivial))]
        (if (and strict (or (> nv 0) (> ns 0)))
          (h/outcome out (str "Error: Vacuity violation! " (t/intStr nv) " vacuous tests, " (t/intStr ns) " trivial stubs.\n") 1)
          (h/outcome out "" 0)))))
