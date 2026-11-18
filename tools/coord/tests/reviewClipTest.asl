(module asl/tools/coord/tests/reviewClipTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/egress :a e) (asl-tools/coord/reviewStage :a rs)])

; (:m :ref REVIEW-CLIP-FALSE-FAIL :do "a long diff line reaches the reviewer whole or marked, an invented ban on an existing builtin is dropped, a ban on an unknown name stays, block carries its defects, secrets stay withheld")
fn unit -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task "t" :risk "low" :closureChanged false :writerAlias "x" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list) :known "listFind listDrop optionOr some? map")

fn testClip -> Bool
  (let [(long (stringJoin (map (fn [(i Int64)] -> String "abcdefghij") (range 0 100)) ""))
        (huge (stringJoin (map (fn [(i Int64)] -> String "abcdefghij") (range 0 600)) ""))
        (b (l/reviewBrief (unit) (str "+ " long "TAILMARK\n+ ok") ""))
        (bh (l/reviewBrief (unit) (str "+ " huge "\n+ ok") ""))]
    (do (assert (stringContains? b "TAILMARK") "a 1000 char line under the budget arrives whole, tail included")
        (assert (stringContains? bh "clipped at 4000 of 6002 chars") (str "a line past the ceiling carries a note naming both lengths"))
        (assert (stringContains? b "never fail on a cut line") "the brief tells the reviewer a cut line is no defect")
        (assert (= (e/clipMarked "abcdef" 3) "abc…(clipped at 3 of 6 chars)") "clipMarked names the cut")
        (assert (= (e/clipMarked "ab" 3) "ab") "clipMarked leaves short text")
        (assert (= (e/clip "abcdef" 3) "abc") "the plain egress clip is unchanged")
        true))

fn testBudget -> Bool
  (let [(line (stringJoin (map (fn [(i Int64)] -> String "x") (range 0 3000)) ""))
        (diff (stringJoin (map (fn [(i Int64)] -> String (str "+ " line)) (range 0 200)) "\n"))
        (part (l/reviewDiffPart diff 100000))
        (blanks (l/reviewDiffPart (str "+ a\n" (stringJoin (map (fn [(i Int64)] -> String "") (range 0 900)) "\n") "\n+ b") 100000))
        (small (with (unit) :ctxTokens 20000))]
    (do (assert (< (listLength part) 200) "the diff is cut by the total budget, whole lines")
        (assert (stringContains? (optionOr (listLast part) "") "diff clipped") "the cut is named")
        (assert (= (l/reviewDiffChars (unit)) 252000) "default budget: (100000 - 16000) tokens at 3 chars")
        (assert (= (l/reviewDiffChars small) 12000) "a smaller reviewer context shrinks the budget")
        (assert (= blanks (list "+ a" "+ b")) (str "blank lines are not hidden lines: " (stringJoin blanks "|")))
        true))

fn testSecretsStay -> Bool
  (let [(b (l/reviewBrief (unit) (str "+ " (stringJoin (map (fn [(i Int64)] -> String "a") (range 0 900)) "") "\n+ api_key = zzz\n+ ok") ""))]
    (do (refute (stringContains? b "api_key") "a secret line is still withheld")
        (assert (stringContains? b "+ ok") "the line after it stays")
        true))

fn failWith d: String -> l/Verdict
  (l/parseVerdict (str "(:verdict :fail :defects (\"" d "\") :model m)") "m" "R1")

fn known -> (fn [String] -> Bool)
  (fn [(n String)] -> Bool (listContains? (list "listFind" "listDrop" "optionOr" "some?" "map") n))

fn stays d: String -> Bool
  (= (pairFirst (l/vetVerdict (failWith d) (known))).outcome "fail")

fn doubtful d: String -> Bool
  (let [(r (l/vetVerdict (failWith d) (known)))]
    (and (= (pairFirst r).outcome "abstain") (= (listLength (pairSecond r)) 1)))

fn testDoubtful -> Bool
  (do (assert (stays "zorkleMap is not a defined function in walk.asl") "P1 a name outside the prelude stays a fail, whatever the diff says")
      (assert (stays "trieInsert is not a defined symbol: asl-std/trie is not imported") "P1b an unimported symbol stays a fail")
      (assert (stays "listFind is not a valid function and the loop in walk never terminates") "P2 two claims in one line stay a fail")
      (assert (stays "listFind is not a valid function with 3 arguments, it takes 2") "P3 an arity claim stays a fail")
      (assert (stays "map is not a valid function for a Map value") "P4 a type claim stays a fail")
      (assert (stays "listFind is not a valid operand") "P5 operand is no op")
      (assert (stays "listFind is not a valid function call here because the result is discarded") "P6 because stays a fail")
      (assert (stays "listFind is not a valid function because the list API forbids it") "P6b because alone stays a fail")
      (assert (stays "LISTFIND IS NOT A VALID FUNCTION AND THE LOOP NEVER ENDS") "P8 upper case two claims stay a fail")
      (assert (doubtful "listDrop is not an allowed primitive") "a bare ban on a prelude name is doubtful")
      (assert (doubtful "uses undefined function `listDrop` (not permitted by list API)") "node2 wording 1")
      (assert (doubtful "use of disallowed list function `listFind`") "node2 wording 2")
      (assert (doubtful "uses listFind which is not an allowed list primitive") "node2 wording 3")
      (assert (doubtful "findChild uses listFind, which is not an allowed list primitive") "node2 wording 4")
      (assert (stays "LISTFIND is not an allowed primitive") "a name that is no prelude name stays a fail, case matters for names")
      true)

fn testVet -> Bool
  (let [(mixed (l/vetVerdict (l/parseVerdict "(:verdict :fail :defects (\"listFind is not an allowed primitive\" \"clip overruns the slice in egress.asl\") :model m)" "m" "R1") (known)))
        (unk (l/vetVerdict (l/parseVerdict "(:verdict :fail :defects (\"listFind is not an allowed primitive\" \"zorkle is not an allowed primitive\") :model m)" "m" "R1") (known)))
        (all (l/vetVerdict (l/parseVerdict "(:verdict :fail :defects (\"listFind is not an allowed primitive\" \"uses undefined function `optionOr`\") :model m)" "m" "R1") (known)))
        (pass (l/vetVerdict (l/parseVerdict "(:verdict :pass :defects () :model m)" "m" "R1") (known)))]
    (do (assert (= (pairFirst mixed).outcome "fail") "a real defect beside a doubtful one keeps the fail")
        (assert (= (listLength (pairFirst mixed).defects) 2) "and keeps every defect")
        (assert (= (pairFirst unk).outcome "fail") "a doubtful one beside an unknown name keeps the fail")
        (assert (= (pairFirst all).outcome "abstain") "every defect doubtful: an abstention, never a pass")
        (assert (stringStartsWith? (optionOr (listHead (pairFirst all).defects) "") "doubtful: ") "the abstention says why")
        (assert (= (pairFirst pass).outcome "pass") "a pass is untouched")
        true))

fn replying text: String -> (fn [String String] -> (Result String String))
  (fn [(a String) (p String)] -> (Result String String) (ok text))

fn lane n: String -> l/Lane
  (l/Lane :alias n :tier "free" :allowance 5 :quality 5)

fn lanes4 -> (List l/Lane)
  (list (lane "flashLow") (lane "orNemotronUltraFree") (lane "nimNemotronUltra") (lane "ocLongcat"))

fn receipt -> String
  "(:receipt U1 :gates ((:gate g :exit 0 :executed 1)) :redBefore ((:gate g :exit 1 :executed 0)))"

fn testReviewDoubtful -> Bool
  (let [(r (l/review (with (unit) :writerAlias "flashHigh") "+ a" (receipt) (lanes4) (replying "(:verdict :fail :defects (\"listFind is not an allowed primitive\") :model m)")))
        (real (l/review (with (unit) :writerAlias "flashHigh") "+ a" (receipt) (lanes4) (replying "(:verdict :fail :defects (\"listFind is not an allowed primitive and the loop is wrong\") :model m)")))]
    (match r
      ((err e) (do (assert false e) false))
      ((ok ru)
        (match real
          ((err e) (do (assert false e) false))
          ((ok rr)
            (do (assert (!= ru.action "merge") "a doubtful claim never merges")
                (assert (!= ru.action "fix") "and is no fail: the writer is not sent to fix what the reviewer invented")
                (assert (listAny? (fn [(x String)] -> Bool (stringContains? x ":doubtful")) ru.rows) "the reviewCall row records it")
                (assert (= (countFail ru) 0) "no verdict of the ruling is a fail")
                (assert (= rr.action "fix") "a compound claim is an ordinary fail")
                true))))))

fn countFail ru: l/Ruling -> Int64
  (listLength (filter (fn [(v l/Verdict)] -> Bool (= v.outcome "fail")) ru.verdicts))

fn testClippedPass -> Bool
  (let [(big (stringJoin (map (fn [(i Int64)] -> String (str "+ line " (stringFromInt64 i))) (range 0 2000)) "\n"))
        (pass "(:verdict :pass :defects () :model m)")
        (r (l/review (with (unit) :writerAlias "flashHigh") big (receipt) (lanes4) (replying pass)))
        (ok1 (l/review (with (unit) :writerAlias "flashHigh") "+ a" (receipt) (lanes4) (replying pass)))]
    (match r
      ((err e) (do (assert false e) false))
      ((ok ru)
        (match ok1
          ((err e) (do (assert false e) false))
          ((ok r1)
            (do (assert (!= ru.action "merge") "a pass on a clipped diff does not merge")
                (assert (listAny? (fn [(x String)] -> Bool (stringContains? x ":clipped true")) ru.rows) "the reviewCall row says clipped")
                (assert (= r1.action "merge") "a pass on a whole diff merges")
                true))))))

fn testBriefBuiltins -> Bool
  (let [(b (l/reviewBrief (unit) "+ (listFind f xs)\n+ (zorkleMap xs)" ""))
        (none (l/reviewBrief (unit) "+ (zorkleMap xs)" ""))]
    (do (assert (stringContains? b "every name below is a prelude builtin and is allowed: listFind") (str "the diff builtins are named: " b))
        (refute (stringContains? b "allowed: listFind zorkleMap") "a name outside the prelude is not claimed allowed")
        (refute (stringContains? none "every name below") "no builtin in the diff, no line")
        (assert (stringContains? b "is not a defect") "the brief says a ban on a builtin is no defect")
        true))

fn testSigOf -> Bool
  (let [(ru (l/Ruling :action "blocked" :rung "R3" :defects (list "d1" "d2") :awaitLane "" :rows (list) :verdicts (list) :why "tiebreak: split"))]
    (do (assert (= (rs/sigOf ru) "tiebreak: split | defects: d1; d2") "the blocked sig reaches the stage result through sigOf")
        (assert (= (rs/sigOf (with ru :action "fix")) "d1; d2") "fix keeps its defect list")
        true))

fn testBuiltins -> Bool
  (let [(names (stringSplit (rs/builtinNames ".") " "))]
    (do (assert (listContains? names "listFind") "prelude catalog names listFind")
        (assert (listContains? names "optionOr") "prelude catalog names optionOr")
        (assert (not (listContains? names "zorkleMap")) "and not an invented name")
        true))

fn testBlockSig -> Bool
  (let [(sig (rs/blockedSig "tiebreak: reviewers split" (list "clip overruns the slice" "second defect")))
        (long (rs/blockedSig "w" (list (stringJoin (map (fn [(i Int64)] -> String "abcdefghij") (range 0 100)) ""))))]
    (do (assert (stringContains? sig "tiebreak: reviewers split | defects: clip overruns the slice; second defect") (str "block sig lists the defects: " sig))
        (assert (< (stringLength long) 340) "the defects are clipped")
        (assert (= (rs/blockedSig "why" (list)) "why") "no defects, the plain reason")
        true))

fn ! runTests -> Bool
  (do (testClip) (testBudget) (testSecretsStay) (testDoubtful) (testVet) (testReviewDoubtful) (testClippedPass) (testBriefBuiltins) (testSigOf) (testBuiltins) (testBlockSig) true)
