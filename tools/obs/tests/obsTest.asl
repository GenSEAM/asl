(module ws/asl/tools/obs/tests/obsTest
  :x [runTests]
  :i [(ws/asl/tools/obs/sx :a sx)
      (ws/asl/tools/obs/obs :a ob)
      (ws/asl/tools/obs/filter :a flt)
      (ws/asl/tools/obs/classify :a cl)
      (ws/asl/tools/obs/sources :a src)
      (ws/asl/tools/obs/report :a rp)
      (ws/asl/tools/obs/corpus :a co)])

fn readText p: String -> String
  (resultOr (fileReadString p) "")

fn fx name: String -> String
  (readText (str "asl/tools/obs/tests/fixtures/" name))

fn table -> (List cl/FailClass)
  (cl/parseTable (readText "asl/tools/obs/failClasses.asn"))

fn ctx -> src/Ctx
  (src/Ctx :table (table) :host "mac" :mtime 1792966000000 :run "fixRun")

fn rowsOf f: (fn [src/Ctx String] -> (Option ob/Obs)) name: String -> (List ob/Obs)
  (listFlatMap (fn [(l String)] -> (List ob/Obs) (match (f (ctx) l) ((some o) (list o)) ((none) (list)))) (stringLines (fx name)))

fn one o: (Option ob/Obs) -> (List ob/Obs)
  (match o ((some v) (list v)) ((none) (list)))

fn allObs -> (List ob/Obs)
  (listAppend (rowsOf src/gatewayRow "gateway.fixture.asn")
    (listAppend (rowsOf src/benchRow "bench.fixture.asn")
      (listAppend (rowsOf src/freshRow "fresh.fixture.asn")
        (listAppend (rowsOf src/condRow "cond.fixture.asn")
          (listAppend (one (src/journalObs (ctx) 1792966000000 (fx "journal.fixture.asn")))
            (listAppend (one (src/journalObs (ctx) 1792966000000 (fx "journalOk.fixture.asn")))
              (listAppend (one (src/receiptObs (ctx) "caseR" (fx "receipt.fixture.asn")))
                          (src/calRows (ctx) (fx "cal.fixture.asn")))))))))

fn testClassifier -> Bool
  (let [(t (table))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:line ")) (stringLines (fx "lines.fixture.asn"))))
        (bad (filter (fn [(l String)] -> Bool
                       (let [(f (sx/topFields l))]
                         (!= (cl/classify t (optionOr (sx/field f ":text") "")) (optionOr (sx/field f ":expect") ""))))
                     lines))]
    (do (assert (> (listLength lines) 15) "fixture has the labelled lines")
        (assert (listEmpty? bad) "every fixture line gets its labelled class, unknown lines stay unclassified")
        (assert (listEmpty? (cl/selfCheck t)) "every class example classifies to its own class")
        (assert (> (listLength t) 15) "class table loaded as data")
        true))

fn testFilter -> Bool
  (let [(key "sk-abcdef0123456789abcdef0123456789")
        (line (str "request failed OPENAI_API_KEY=" key " with Bearer " key " in .asl/mem/work/HRN/x.asn at /Users/purplelephant/projects/a"))
        (red (flt/safeText line))
        (long (flt/safeText (stringRepeat "x " 400)))
        (multi (flt/safeText "first line\nsecond line"))
        (short (flt/safeText "call failed token sk-live12345678 retry"))]
    (do (assert (not (stringContains? red "sk-abcdef")) "seeded key is stripped")
        (assert (not (stringContains? red "abcdef0123456789")) "key body is stripped everywhere")
        (assert (not (stringContains? red ".asl/mem")) "an .asl/mem path is stripped")
        (assert (stringContains? red "OPENAI_API_KEY=<redacted>") "the env name stays, its value goes")
        (assert (not (stringContains? red "/Users/purplelephant")) "home prefix is shortened")
        (assert (<= (stringLength long) 200) "text is clipped to 200 bytes")
        (assert (not (stringContains? short "sk-live")) "a short prefixed key is stripped by its prefix")
        (assert (= multi "first line") "only the first line survives")
        (assert (= (flt/safeText "ERR_TYPE_MISMATCH return of f: expected String") "ERR_TYPE_MISMATCH return of f: expected String") "a plain error line is untouched")
        true))

fn find o: (List ob/Obs) src: String -> (List ob/Obs)
  (filter (fn [(x ob/Obs)] -> Bool (= x.source src)) o)

fn testNormalisers -> Bool
  (let [(all (allObs))
        (gw (find all "gateway"))
        (bn (find all "bench"))
        (fr (find all "fresh"))
        (cd (find all "conductor"))
        (ln (find all "leon"))
        (ev (find all "agentEval"))
        (cal (find all "cal"))
        (g429 (optionOr (listGet gw 1) (ob/blankObs)))
        (g4 (optionOr (listGet gw 2) (ob/blankObs)))
        (gbr (optionOr (listGet gw 3) (ob/blankObs)))
        (esc (optionOr (listHead (filter (fn [(x ob/Obs)] -> Bool (= x.run "0123456789abcdef")) ln)) (ob/blankObs)))
        (good (optionOr (listHead (filter (fn [(x ob/Obs)] -> Bool (= x.run "fedcba9876543210")) ln)) (ob/blankObs)))]
    (do (assert (= (listLength gw) 4) "four gateway rows")
        (assert (= (optionOr (listHead (map (fn [(x ob/Obs)] -> String x.outcome) gw)) "") "ok") "an ok call is ok")
        (assert (and (= g429.outcome "infra") (= g429.failClass "quota429")) "429 is an infra quota429")
        (assert (and (= g4.failClass "upstream4xx") (= g4.card "bbbb000000000002") (= g4.family "model-b")) "4xx class, sysHash as card, vendor prefix dropped from family")
        (assert (= gbr.failClass "quota429") "a breaker window is a quota class")
        (assert (= (listLength bn) 2) "the benchRunDone row is not an observation")
        (assert (= (optionOr (listHead (map (fn [(x ob/Obs)] -> String x.failClass) (listDrop bn 1))) "") "wrongAnswer") "bench why line classified")
        (assert (= (listLength fr) 3) "three fresh rows")
        (assert (= (optionOr (listHead (map (fn [(x ob/Obs)] -> String x.card) fr)) "") "cardX") "fresh variant is the card")
        (assert (= (listLength cd) 2) "a conductor row without a verdict is not an observation")
        (assert (= (optionOr (listHead (map (fn [(x ob/Obs)] -> String x.failClass) (listDrop cd 1))) "") "gateRedAssert") "conductor red gate verdict")
        (assert (= esc.model "vendor/served-model") "the served model wins over the session label")
        (assert (and (= esc.outcome "fail") (= esc.failClass "protocol")) "an escalated session with a parse defect is protocol")
        (assert (and (= esc.tokensIn 30742) (= esc.tokensOut 1685) (= esc.exitCode 0)) "usage from the result row, last gate exit")
        (assert (and (= good.outcome "ok") (= good.failClass "none") (= good.model "label-model") (= good.unitId "wt-unit")) "ok session")
        (assert (= (listLength ev) 1) "one receipt")
        (assert (and (= (optionOr (listHead (map (fn [(x ob/Obs)] -> String x.outcome) ev)) "") "ok") (= (optionOr (listHead (map (fn [(x ob/Obs)] -> Int64 x.tokensIn) ev)) 0) 9448)) "receipt status and tokens")
        (assert (= (listLength cal) 2) "only CAL rows with a pass fraction")
        (assert (= (optionOr (listHead (map (fn [(x ob/Obs)] -> Int64 x.asserts) cal)) 0) 8) "aggregate passes")
        (assert (= (src/outcomeOf "ok") "ok") "outcomeOf")
        true))

fn testRoundTrip -> Bool
  (let [(all (allObs))
        (back (map (fn [(o ob/Obs)] -> ob/Obs (ob/parseObs (ob/renderObs o))) all))]
    (do (assert (= (map ob/renderObs all) (map ob/renderObs back)) "render and parse are inverse on every source row")
        (assert (= (ob/dayOf 1792966867851) "2026-10-25") "epoch ms to day")
        (assert (= (ob/dayToMs "2026-10-25") 1792886400000) "day to epoch ms")
        true))

fn testReport -> Bool
  (let [(all (allObs))
        (lv (rp/parseLevers (readText "asl/tools/obs/levers.asn")))
        (a (rp/report "model" lv all))
        (b (rp/report "model" lv (listReverse all)))
        (c (rp/report "failClass" lv all))
        (k (rp/report "case" lv all))
        (d (rp/report "card" lv all))]
    (do (assert (= a b) "the model matrix is identical for any row order")
        (assert (= c (rp/report "failClass" lv (listReverse all))) "the failClass matrix is identical for any row order")
        (assert (= k (rp/report "case" lv (listReverse all))) "the case registry is identical for any row order")
        (assert (stringContains? a ":scope (:n ") "scope with n")
        (assert (stringContains? a ":from \"2026-") "scope with dates")
        (assert (stringContains? a "(:model \"label-model\" :n 1 :ok 1 :fail 0 :infra 0 :rate 1.000") "per model n and pass rate")
        (assert (stringContains? c "(:failClass quota429 :n 2") "failClass counts")
        (assert (stringContains? c "pacing: subPace allowance per provider") "failClass rows carry the lever")
        (assert (stringContains? k "(:case \"n3\" :n 2 :models 1") "case registry lists the case")
        (assert (stringContains? d "(:card \"cardX\"") "per card matrix")
        (assert (stringContains? d ":onSharedCases (:n 1 :rate 0.000)") "card X rate on the case both cards ran")
        (assert (stringContains? d ":onSharedCases (:n 1 :rate 1.000)") "card Y rate on the case both cards ran")
        (assert (stringContains? (rp/report "bogus" lv all) ":err") "unknown dimension is an error row")
        (assert (= (rp/rateText 3 1) "0.750") "rate in permille")
        (assert (= (rp/rateText 0 0) "none") "no scored rows has no rate")
        true))

fn testCollect -> Bool
  (let [(base (str "/tmp/obsTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (ws (str base "/ws"))
        (home (str base "/home"))
        (out (str base "/out"))
        (dirs (list (str home "/.asl/run/usage") (str ws "/.asl/run/agentLoop") (str ws "/.asl/run/agentEval/20261001-000000-modelx-low/caseA")
                    (str ws "/.asl/tmp/fresh") (str ws "/.asl/mem/work/CAL") (str ws "/asl/tools/obs")))
        (_m (map co/mkdirs! dirs))
        (_1 (fileWrite (str home "/.asl/run/usage/gatewayCalls.asn") (fx "gateway.fixture.asn")))
        (_2 (fileWrite (str ws "/.asl/run/agentLoop/a1.journal") (fx "journal.fixture.asn")))
        (_3 (fileWrite (str ws "/.asl/run/agentLoop/a2.journal") (fx "journalOk.fixture.asn")))
        (_4 (fileWrite (str ws "/.asl/run/agentEval/20261001-000000-modelx-low/caseA/receipt.asn") (fx "receipt.fixture.asn")))
        (_5 (fileWrite (str ws "/.asl/tmp/fresh/f.log") (fx "fresh.fixture.asn")))
        (_6 (fileWrite (str ws "/.asl/mem/work/CAL/c.asn") (fx "cal.fixture.asn")))
        (_7 (fileWrite (str ws "/asl/tools/obs/failClasses.asn") (readText "asl/tools/obs/failClasses.asn")))
        (first (co/collect! ws home "mac" out ""))
        (second (co/collect! ws home "mac" out ""))
        (_s (pathRemove (str out "/state.asn")))
        (third (co/collect! ws home "mac" out ""))
        (days (filter (fn [(f String)] -> Bool (stringEndsWith? f ".asn")) (resultOr (dirList out) (list))))
        (stored (listSum (map (fn [(f String)] -> Int64 (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:obs ")) (stringLines (readText (str out "/" f)))))) days)))
        (blob (stringJoin (map (fn [(f String)] -> String (readText (str out "/" f))) days) "\n"))
        (_z (pathRemove base))]
    (do (assert (stringContains? first ":total 12 :new 12") "first run stores every row once")
        (assert (stringContains? second ":total 0 :new 0") "second run reads nothing new and adds nothing")
        (assert (stringContains? third ":total 12 :new 0") "with the state file lost, the ids still keep the store free of duplicates")
        (assert (= stored 12) "the day files hold 12 distinct rows")
        (assert (not (stringContains? blob "fixture task text")) "no task text reaches the store")
        (assert (not (stringContains? blob ".asl/mem")) "no .asl/mem path reaches the store")
        true))

fn runTests -> Bool
  (and (testClassifier) (and (testFilter) (and (testNormalisers) (and (testRoundTrip) (and (testReport) (testCollect))))))
