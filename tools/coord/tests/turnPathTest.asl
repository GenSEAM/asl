(module asl-tools/coord/tests/turnPathTest
  :x [runTests]
  :i [(asl-tools/coord/turnPath :a tp)])

; (:m :ref TURN-PATH-EFFICIENCY :do "fixtures/turnPath holds eleven small journals in the agent loop's row format, one per situation: the short path, rereads and turns after green, one refused write per refusal class, the losses that are not reads or writes, the ways a read repeats or does not, a batched read and txn, a write turn that also carried a refused edit after a grep run, shell runs that are and are not reads, a run the provider never answered, a journal without a turn, and a journal cut in mid row with a foreign line in it. Every loss cause has a session that shows it, with its class and its token sum, and the summary's rows add up to the turns")
fn fixtureDir -> String
  "asl/tools/coord/tests/fixtures/turnPath"

fn ! pathOf name: String -> tp/Path
  (tp/pathOfText name (resultOr (fileReadString (str (fixtureDir) "/" name ".journal")) ""))

fn causesOf p: tp/Path -> String
  (stringJoin (map (fn [(s tp/Step)] -> String s.cause) p.steps) ",")

fn outOf p: tp/Path cause: String -> Int64
  (fold (fn [(acc Int64) (s tp/Step)] -> Int64 (if (= s.cause cause) (+ acc s.outT) acc)) 0 p.steps)

fn turnsIn line: String -> Int64
  (match (stringIndexOf line ":turns ")
    ((none) 0)
    ((some i) (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ i 7) (stringLength line)) "") " ")) "")) 0)))

fn rowTurns text: String -> Int64
  (fold (fn [(acc Int64) (l String)] -> Int64
          (if (and (or (stringStartsWith? l "(:waste ") (stringStartsWith? l "(:progress ")) (not (stringContains? l ":countedIn progress"))) (+ acc (turnsIn l)) acc))
        0 (stringLines text))

fn ! testShort -> Bool
  (let [(p (pathOf "a1short"))
        (b (pathOf "e5batch"))]
    (do
      (assert (= p.shape "RWG") (str "read, write, green gate: " p.shape))
      (assert (= p.excess 0) (str "the short path has no excess: " (stringFromInt64 p.excess)))
      (assert (= p.ideal 3) (str "one read batch, one file, one gate: " (stringFromInt64 p.ideal)))
      (assert (= p.outcome "written") (str "ok stop with a written file: " p.outcome))
      (assert (= p.unit "SHORT") (str "unit from the receipt's journal path: " p.unit))
      (assert (= p.firstWriteTurn 2) (str "first accepted write on turn 2: " (stringFromInt64 p.firstWriteTurn)))
      (assert (= (+ p.inT p.outT) 4550) (str "tokens summed over the turns: " (stringFromInt64 (+ p.inT p.outT))))
      (assert (= b.shape "RW") (str "reads in one reply, txn and gate in the next: " b.shape))
      (assert (= b.ideal 4) (str "a txn's two flushed files count as two: " (stringFromInt64 b.ideal)))
      (assert (= b.excess -2) (str "batching beats the nominal path: " (stringFromInt64 b.excess)))
      true))

fn ! testReads -> Bool
  (let [(p (pathOf "b2reread"))]
    (do
      (assert (= (causesOf p) "read,reread,scout,write,scout,gate,afterGreen") (str "causes by turn: " (causesOf p)))
      (assert (= p.shape "RrsWsGa") (str "letters by turn: " p.shape))
      (assert (= (outOf p "reread") 110) (str "the range inside a file already read whole is a reread: " (stringFromInt64 (outOf p "reread"))))
      (assert (= (outOf p "scout") 210) (str "a query nothing later names and a read after the last write are scouts: " (stringFromInt64 (outOf p "scout"))))
      (assert (= (outOf p "afterGreen") 70) (str "the done turn after the green gate: " (stringFromInt64 (outOf p "afterGreen"))))
      (assert (= p.excess 4) (str "seven turns against three: " (stringFromInt64 p.excess)))
      true))

fn ! testRejects -> Bool
  (let [(p (pathOf "c3rejects"))]
    (do
      (assert (= (causesOf p) "rejected:brackets,rejected:oldNotFound,rejected:outsideOwns,rejected:wholeFile,rejected:comment,rejected:unknownSymbol,rejected:rawMissing,rejected:ERR_STUB_NEW,rejected:outsideOwns")
              (str "one class per refusal, an unlisted one keeps its code, and the refused edit names the class when a failed read stands before it: " (causesOf p)))
      (assert (= p.outT 10800) (str "output tokens of the refused writes: " (stringFromInt64 p.outT)))
      (assert (= (outOf p "rejected:wholeFile") 4000) (str "tokens of the whole-file refusal: " (stringFromInt64 (outOf p "rejected:wholeFile"))))
      (assert (= p.outcome "failed:wallBudget") (str "stop word of a run that wrote nothing: " p.outcome))
      (assert (= p.model "aliQwen4MaxPreview") (str "first served alias: " p.model))
      (assert (= (tp/rejectClass "" "") "unknown") "a refusal with neither text nor code is unknown, not a guessed class")
      true))

fn classesOf rows: (List (Pair String String)) -> String
  (stringJoin (map (fn [(r (Pair String String))] -> String (tp/rejectClass (pairFirst r) (pairSecond r))) rows) ",")

fn testRejectTable -> Bool
  (do
    (assert (= (classesOf (list (pair "x ERR_RAW_MISSING y" "") (pair "" "ERR_RAW_MISSING") (pair "" "ERR_OWNS") (pair "do not balance, ERR_OWNS" "")))
               "rawMissing,rawMissing,outsideOwns,outsideOwns")
            "raw marker and owns refusals from the text or from the code alone, owns ahead of brackets")
    (assert (= (classesOf (list (pair "unexpected closing delimiter ')' at byte 3" "") (pair "unclosed ( at line 2" "") (pair "ERR_NO_MATCH" "") (pair "ERR_PARSE near x" "")))
               "brackets,brackets,oldNotFound,parse")
            "each bracket wording, the no-match code and a parse error")
    (assert (= (classesOf (list (pair "ERR_UNDEFINED_EXPORT f" "") (pair "ERR_UNRESOLVED_IMPORT a/b" "") (pair "unbound symbol println!" "") (pair "ERR_TYPE_MISMATCH at pairFirst" "") (pair "ERR_ARITY with 8" "")))
               "unknownSymbol,unknownSymbol,unknownSymbol,typeCheck,typeCheck")
            "each unknown-name wording and both type check codes")
    true)

fn ! testReadKinds -> Bool
  (let [(p (pathOf "g7reads"))]
    (do
      (assert (= (causesOf p) "read,reread,read,read,reread,reread,scout,read,write,scout,gate,gateSame,toolErr:ERR_SYMBOL_NOT_FOUND") (str "causes by turn: " (causesOf p)))
      (assert (= (outOf p "reread") 313) (str "a range inside an earlier range, the same symbol and the same query are rereads: " (stringFromInt64 (outOf p "reread"))))
      (assert (= (outOf p "read") 416) (str "an overlapping range, a symbol, an outline and a query the write names are new and used: " (stringFromInt64 (outOf p "read"))))
      (assert (= (outOf p "scout") 217) (str "a query nothing names, and the same range read again after the file changed: " (stringFromInt64 (outOf p "scout"))))
      (assert (= (outOf p "gate") 111) (str "a red gate after a change is still the first look at it: " (stringFromInt64 (outOf p "gate"))))
      (assert (= (outOf p "gateSame") 112) (str "the same gate with nothing changed: " (stringFromInt64 (outOf p "gateSame"))))
      (assert (= (outOf p "toolErr:ERR_SYMBOL_NOT_FOUND") 113) "a read the tool refused keeps its code")
      (assert (and (= p.ideal 4) (= p.excess 9)) (str "four used-read turns count as two in the ideal path: " (stringFromInt64 p.ideal) " " (stringFromInt64 p.excess)))
      true))

fn ! testMixed -> Bool
  (let [(p (pathOf "i9mixed"))
        (last (optionOr (listLast p.steps) (tp/Step :turn 0 :letter "" :cause "" :inT 0 :outT 0 :cached 0 :rejectedOps 0 :preview "")))]
    (do
      (assert (= (causesOf p) "read,inspect,write") (str "a grep of a file edited later is a read, a cat of a file nobody touches is inspect: " (causesOf p)))
      (assert (and (= last.cause "write") (= last.rejectedOps 1)) (str "the accepted edit keeps the turn, the refused one is counted on it: " (tp/stepLine last)))
      (assert (and (= p.ideal 2) (= p.excess 1)) (str "the loop gated the write itself, so no gate turn in the ideal path: " (stringFromInt64 p.ideal) " " (stringFromInt64 p.excess)))
      true))

fn ! testRuns -> Bool
  (let [(p (pathOf "j0runs"))
        (w (pathOf "k1wait"))]
    (do
      (assert (= (causesOf p) "scout,gateFirst,scout,inspect,read,inspect,toolErr:ERR_HARNESS_PATH,inspect,write")
              (str "a grep of a file read later is a read, an asl test run is a gate, echo and a cat of an untouched file are inspect, a cat cut by a pipe reads the file before the pipe, a refused run is a tool error: " (causesOf p)))
      (assert (= p.outcome "failed:wallBudget") (str "written files with a stop that is not ok is still a failed run: " p.outcome))
      (assert (and p.wrote (and (= p.ideal 3) (= p.excess 6))) (str "one used read, one file, and a gate turn because the loop did not gate: " (tp/pathLine p)))
      (assert (= w.outcome "failed:noWrite") (str "an ok stop that wrote nothing: " w.outcome))
      (assert (= w.model "unknown") (str "no served row, no model name: " w.model))
      (assert (= (causesOf w) "wait") (str "the turn nobody answered: " (causesOf w)))
      (assert (not (stringContains? (tp/summaryText (list p) 0) "mixedRejected")) "no mixedRejected row when no write turn carried a refusal")
      true))

fn ! testOther -> Bool
  (let [(p (pathOf "d4mixed"))]
    (do
      (assert (= (causesOf p) "gateFirst,noOp,toolErr:ERR_HARNESS_PATH,doneRefused,inspect,unknown,toolErr:unknown,inspect,gateSame,gateSame,readNoWrite,toolErr:ERR_NOTE_STUB,inspect,toolErr:rejected,gateSame,wait,close") (str "causes by turn: " (causesOf p)))
      (assert (= (outOf p "gateFirst") 11) (str "the first gate the model asked for, nothing changed yet: " (stringFromInt64 (outOf p "gateFirst"))))
      (assert (= (outOf p "readNoWrite") 25) (str "a search in a session that lands nothing is readNoWrite, not scout: " (stringFromInt64 (outOf p "readNoWrite"))))
      (assert (= (outOf p "gateSame") 64) (str "an asl test run, a check and a gate after the first gate with nothing changed: " (stringFromInt64 (outOf p "gateSame"))))
      (assert (= (outOf p "inspect") 64) (str "git log and shell runs that are not gates: " (stringFromInt64 (outOf p "inspect"))))
      (assert (= (+ (outOf p "toolErr:ERR_HARNESS_PATH") (+ (outOf p "toolErr:unknown") (+ (outOf p "toolErr:ERR_NOTE_STUB") (outOf p "toolErr:rejected")))) 88)
              "tool errors keep the code of the op that failed, unknown when the row names none")
      (assert (= (+ (outOf p "noOp") (+ (outOf p "doneRefused") (+ (outOf p "unknown") (outOf p "close")))) 61)
              "tokens of the no-op, refused done, unknown op and close turns")
      (assert (= (outOf p "wait") 0) "the unanswered turn spent no tokens")
      (assert (= (+ p.ideal p.excess) 0) "without an accepted write ideal and excess stay 0")
      (assert (and (not p.wrote) (not (stringContains? (tp/pathLine p) ":ideal "))) (str "a session without an accepted write has no ideal path: " (tp/pathLine p)))
      true))

fn ! testCut -> Bool
  (let [(p (pathOf "f6cut"))]
    (do
      (assert (= p.skipped 2) (str "the foreign line and the row cut in the middle: " (stringFromInt64 p.skipped)))
      (assert (= p.turns 3) (str "the turns before the cut still count: " (stringFromInt64 p.turns)))
      (assert (= p.outcome "failed:noReceipt") (str "a journal without a receipt: " p.outcome))
      true))

fn ! testDir -> Bool
  (let [(all (tp/reportDir (fixtureDir) 0 2 "" 0))
        (text (pairSecond all))
        (one (tp/reportDir (fixtureDir) 0 0 "b2" 0))
        (none (tp/reportDir "asl/tools/coord/tests/fixtures" 0 0 "" 0))
        (old (tp/reportDir (fixtureDir) 1 0 "" 4102444800))
        (gone (tp/reportDir (str (fixtureDir) "/absent") 0 0 "" 0))]
    (do
      (assert (= (pairFirst all) 0) "the fixture directory reports with code 0")
      (assert (stringContains? text "(:turnPath :sessions 10 :turns 67 :skipped 3 ") (str "sessions, turns and skipped rows: " (optionOr (listHead (stringLines text)) "")))
      (assert (= (rowTurns text) 67) (str "progress and waste rows add up to the turns: " (stringFromInt64 (rowTurns text))))
      (assert (stringContains? text "(:waste :cause rejected:wholeFile :turns 1 :sharePct 1.5 :out 4000 :in 1000)") "the costliest loss row, with its share and tokens")
      (assert (stringStartsWith? (optionOr (listGet (stringLines text) 2) "") "(:waste :cause rejected:wholeFile ") "waste rows are ordered by lost output tokens")
      (assert (stringContains? text "(:shortPath :sessions 4 :wrote 7 :all 10 :shareOfWrotePct 57.1 :shareOfAllPct 40.0)") "four of the seven sessions that landed a write stayed within one turn of ideal")
      (assert (stringContains? text "(:excess :sessions 7 :median 1 :p90 9)") "median and p90 of excess over the sessions that landed a write")
      (assert (stringContains? text "(:firstWriteTurn :sessions 7 :median 3 :p90 9)") "first write turn over the seven sessions that wrote")
      (assert (stringContains? text "(:batchable :readTurns 2 :writeTurns 0)") "used-read turns beyond two per session")
      (assert (stringContains? text "(:noWrite :sessions 3 :turns 27 :out 11113 :byStop ((noWrite 1) (provider 1) (wallBudget 1)))") "sessions without an accepted write are counted apart by stop")
      (assert (stringContains? text "(:waste :cause mixedRejected :turns 1 :rejectedOps 1 :countedIn progress)") "the refused op on a write turn has its own row and adds no turn")
      (assert (stringContains? text "(:files :read 10 :unreadable 0 :empty 1)") "the journal without a turn is counted as empty, not as a session")
      (assert (= (pairFirst (tp/reportDir (fixtureDir) 0 0 "h8" 0)) 1) "asking for the empty journal as a session is an error")
      (assert (= (listCount (fn [(l String)] -> Bool (stringStartsWith? l "(:path ")) (stringLines text)) 2) "--top 2 prints two paths")
      (assert (stringContains? (pairSecond one) "(:step :turn 2 :class waste :letter r :cause reread :in 1000 :out 110 :cached 500 :op \"(:step :op 'read' :file 'stub/src/alpha.asl' :start 3 :end 9)\")")
              (str "--session prints one row per turn: " (pairSecond one)))
      (assert (= (listCount (fn [(l String)] -> Bool (stringStartsWith? l "(:step ")) (stringLines (pairSecond one))) 7) "seven step rows for seven turns")
      (assert (and (= (pairFirst none) 0) (stringContains? (pairSecond none) ":sessions 0 :note \"no *.journal file\"")) (str "a directory without journals: " (pairSecond none)))
      (assert (and (= (pairFirst old) 0) (stringContains? (pairSecond old) "in the last 1 hours")) (str "nothing inside the window: " (pairSecond old)))
      (assert (and (= (pairFirst gone) 1) (stringContains? (pairSecond gone) "directory unreadable")) (str "a missing directory: " (pairSecond gone)))
      true))

fn ! runTests -> Bool
  (do
    (assert (testShort) "the short path and the batched path")
    (assert (testReads) "reread, scout and afterGreen")
    (assert (testRejects) "one class per refused write")
    (assert (testRejectTable) "refusal wordings map to their classes")
    (assert (testReadKinds) "what makes a read a reread, a scout or progress")
    (assert (testMixed) "grep as a read, a mixed write turn, the loop's own gate")
    (assert (testRuns) "shell runs as reads, gates or inspect; outcome and model edge cases")
    (assert (testOther) "gateSame, noOp, toolErr, doneRefused, inspect, unknown, wait, close")
    (assert (testCut) "a cut journal is read and its broken rows counted")
    (assert (testDir) "directory report: summary sums, top, session view, empty and missing directories")
    true)
