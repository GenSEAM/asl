(module asl-gates/tests/auditParityTest :x [runTests] :i [(asl-parser/reader :a p) (tests/parity/gates/runnerCorpus :a gr)])

fn items node: p/SExpr -> (List p/SExpr)
  (p/sexprToList node)
fn atom node: p/SExpr -> String
  (mt node ((p/sexprAtom value) value) (_ ""))
fn field xs: (List p/SExpr) key: String -> (Option p/SExpr)
  (mt (listHead xs)
    ((none) (none))
    ((some k)
      (mt (listTail xs)
        ((none) (none))
        ((some afterKey)
          (mt (listHead afterKey)
            ((none) (none))
            ((some value)
              (if (= (atom k) key) (some value)
                  (field (optionOr (listTail afterKey) (list)) key))))))))
fn strField xs: (List p/SExpr) key: String -> String
  (mt (field xs key) ((some value) (gr/decodeString (atom value))) ((none) ""))
fn listOf node: p/SExpr -> (List p/SExpr)
  (p/sexprToList node)
fn argvField xs: (List p/SExpr) -> (List String)
  (mt (field xs ":args")
    ((some v) (map (fn [arg] (gr/decodeString (atom arg))) (listOf v)))
    ((none) (list)))
fn findCase cases: (List p/SExpr) id: String -> (Option p/SExpr)
  (mt (listHead cases)
    ((none) (none))
    ((some c)
      (if (= (strField (optionOr (listTail (items c)) (list)) ":id") id)
        (some c)
        (findCase (optionOr (listTail cases) (list)) id))))
fn sourceAt sourcePairs: (List p/SExpr) index: Int64 -> String
  (let [pairForm (items (optionOr (listGet sourcePairs index) (p/sexprAtom "")))
        value (optionOr (listGet pairForm 1) (p/sexprAtom ""))]
    (gr/decodeString (atom value)))

fn ! workspaceRoot -> String
  (mt (envGet "ASL_CLI_ROOT")
    ((some root) root)
    ((none) (resultOr (realPath ".") ".")))
fn ! childEnv -> (List String)
  (let [path (optionOr (envGet "PATH") "/usr/bin:/bin")]
    (list (str "PATH=" path)))
fn ! runArgv argv: (List String) -> (Result gr/Captured String)
  (gr/runCommand! argv (workspaceRoot) (some (childEnv)))
fn ! testDecodeAndCapture -> Bool
  (let [big (gr/runCommand! (list "sh" "-c" "head -c 200000 /dev/zero | tr '\\000' a") (workspaceRoot) (some (childEnv)))
        cat (gr/runCommand! (list "cat") (workspaceRoot) (some (childEnv)))]
    (do
      (assert (= (gr/decodeString "\"a\\\\nb\"") "a\\nb") "an escaped backslash before n decodes to a backslash and n")
      (assert (= (gr/decodeString "\"\\u0041\\t\"") "A\t") "a \\u escape decodes to its character")
      (mt big
        ((err e) (assert false (str "200000-byte child ran: " e)))
        ((ok r) (assert (and (= r.exit 0) (= (stringLength r.stdout) 200000)) (str "all 200000 bytes captured, got " (stringFromInt64 (stringLength r.stdout))))))
      (mt cat
        ((err e) (assert false (str "cat ran: " e)))
        ((ok r) (assert (and (= r.exit 0) (= r.stdout "")) "a child reading stdin sees EOF")))
      true))
fn ! sourceBlobMatches! path: String expected: String -> Bool
  (mt (runArgv (list "git" "hash-object" path))
    ((err e) (assert false (str path ": source hash command ran: " e)))
    ((ok result)
      (and (= result.exit 0) (= (stringTrim result.stdout) expected))))
fn ! replayCase! fixture: (List p/SExpr) caseId: String kind: String args: (List String) -> Bool
  (mt (findCase fixture caseId)
    ((none) (assert false (str caseId ": recorded fixture case exists")))
    ((some caseForm)
      (let [fields (optionOr (listTail (items caseForm)) (list))
            recordedArgs (argvField fields)
            recordedExit (optionOr (stringToInt64 (atom (optionOr (field fields ":exit") (p/sexprAtom "-999")))) -999)
            wantedOut (strField fields ":stdout")
            wantedErr (strField fields ":stderr")
            got (runArgv (listAppend (list "asl/host/out/asl-host" "run" (str "asl/packages/asl-gates/src/" kind ".asl")) args))]
        (do
          (assert (= recordedArgs args) (str caseId ": fixture argv matches corpus"))
          (mt got
            ((err e) (assert false (str caseId ": ASL process ran: " e)))
            ((ok result)
              (do
                (assert (= result.stdout wantedOut) (str caseId ": ASL stdout equals pinned Python; expected=" wantedOut " got=" result.stdout))
                (assert (= result.stderr wantedErr) (str caseId ": ASL stderr equals pinned Python"))
                (assert (= result.exit recordedExit) (str caseId ": ASL exit equals pinned Python")))))
          true))))
fn ! replayDyck! fixture: (List p/SExpr) ids: (List String) paths: (List String) -> Bool
  (mt (listHead ids)
    ((none) (listEmpty? paths))
    ((some id)
      (mt (listHead paths)
        ((none) false)
        ((some path)
          (and (replayCase! fixture id "dyck" (list path))
               (replayDyck! fixture (optionOr (listTail ids) (list)) (optionOr (listTail paths) (list))))))))
fn ! replayVacuity! fixture: (List p/SExpr) -> Bool
  (and (replayCase! fixture "v01" "vacuity" (list "--test" "echo 'ok 1 - tapTest'" "--base" "626fb71b9d17ed6e0665eb91420e5c1c3b289510"))
  (and (replayCase! fixture "v02" "vacuity" (list "--test" "echo 'not ok 1 - failTest'" "--base" "626fb71b9d17ed6e0665eb91420e5c1c3b289510"))
  (and (replayCase! fixture "v03" "vacuity" (list "--test" "echo 'ok myGroup myTest'" "--base" "626fb71b9d17ed6e0665eb91420e5c1c3b289510"))
  (and (replayCase! fixture "v04" "vacuity" (list "--test" "echo 'FAIL myGroup myTest: failed'" "--base" "626fb71b9d17ed6e0665eb91420e5c1c3b289510"))
  (and (replayCase! fixture "v05" "vacuity" (list "--test" "echo 'ok - hyphenAssert'" "--base" "626fb71b9d17ed6e0665eb91420e5c1c3b289510"))
  (and (replayCase! fixture "v06" "vacuity" (list "--test" "echo 'unparseable line'"))
  (and (replayCase! fixture "v07" "vacuity" (list "--test" "echo '# comments only'"))
  (and (replayCase! fixture "v08" "vacuity" (list "--test" "echo 'ok 1 - tapTest'" "--fail-on-vacuous" "--base" "626fb71b9d17ed6e0665eb91420e5c1c3b289510"))
  (and (replayCase! fixture "v09" "vacuity" (list "bad_arg" "--test" "foo"))
  (and (replayCase! fixture "v10" "vacuity" (list "--base"))
       (replayCase! fixture "v11" "vacuity" (list))))))))))))
fn ! runTests -> Bool
  (let [fixtureText (mt (fileReadString "tests/parity/gates/auditParityFixture.asn")
                         ((ok text) text)
                         ((err e) (do (assert false (str "fixture read: " e)) "")))
        root (items (p/parseSexpr fixtureText))
        fields (optionOr (listTail root) (list))
        cases (listOf (optionOr (field fields ":cases") (p/sexprList (list))))
        sourceForm (items (optionOr (field fields ":sources") (p/sexprList (list))))
        sourcePairs sourceForm
        dyckSha (sourceAt sourcePairs 0)
        vacuitySha (sourceAt sourcePairs 1)
        recordedAtBase (strField fields ":recordedAtBase")]
    (do
      (assert (testDecodeAndCapture) "shared decode and capture helpers")
      (assert (= (listLength cases) 41) "fixture covers 30 dyck and 11 vacuity cases")
      (assert (= dyckSha "7b3a0227119e590ef6501d043b8fb0ec78a1ddb6") (str "dyck source is pinned, got: " dyckSha))
      (assert (= vacuitySha "dbc3bf6ce03fec152e1bd2bdeebe14280e4bb262") "vacuity source is pinned")
      (assert (sourceBlobMatches! "scripts/audit/dyck.py" dyckSha) "dyck fixture pin matches the real source blob")
      (assert (sourceBlobMatches! "scripts/audit/vacuity.py" vacuitySha) "vacuity fixture pin matches the real source blob")
      (assert (= (stringLength recordedAtBase) 40) "audit fixture records a full git HEAD SHA")
      (assert (replayDyck! cases
        (list "d01" "d02" "d03" "d04" "d05" "d06" "d07" "d08" "d09" "d10" "d11" "d12" "d13" "d14" "d15" "d16" "d17" "d18" "d19" "d21" "d22" "d23" "d24" "d25" "d26" "d27" "d28" "d29" "d30" "d31")
        (list "tests/fixtures/dyck/valid/nested.asn" "tests/fixtures/dyck/valid/parenInString.asn" "tests/fixtures/dyck/valid/escapedQuoteInString.asn" "tests/fixtures/dyck/valid/parenInComment.asn" "tests/fixtures/dyck/valid/semicolonInString.asn" "tests/fixtures/dyck/invalid/semicolonIsRetired.asl" "tests/fixtures/dyck/invalid/extraOpen.asn" "tests/fixtures/dyck/invalid/extraClose.asn" "tests/fixtures/dyck/invalid/closeBeforeOpen.asn" "tests/fixtures/dyck/invalid/unclosedBracket.asn" "tests/fixtures/dyck/invalid/unterminatedString.asn" ".addie/config.asn" ".asl.config.asn" "asl/packages/asl-gates/manifest.asn" "asl/packages/asl-compiler/manifest.asn" "asl/packages/asl-checker/manifest.asn" "asl/packages/asl-parser/manifest.asn" "asl/packages/asl-eval/manifest.asn" "asl/packages/asl-help/manifest.asn" "asl/packages/asl-lint/manifest.asn" "asl/packages/asl-mesh/manifest.asn" "asl/packages/asl-proc/manifest.asn" "asl/packages/asl-text/manifest.asn" "asl/prelude/prelude.asl" "asl/packages/asl-gates/src/grammarGate.asl" "asl/packages/asl-gates/src/lexiconGate.asl" "asl/packages/asl-gates/src/manifestGate.asl" "asl/packages/asl-gates/src/polarity.asl" "asl/packages/asl-gates/src/shebangAudit.asl" "asl/packages/asl-gates/src/siteClaims.asl")) "dyck corpus replay")
      (assert (replayVacuity! cases) "vacuity corpus replay")
      true))
