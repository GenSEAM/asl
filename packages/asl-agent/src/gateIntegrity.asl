(module aslAgent/gateIntegrity
  :x [Claim claimOf bumpMtime! gateFields gateResultsGreen cutParsePrefix evidenceForm unbackedTexts noteUnbacked scanSwallowedErrors! gateIntegrity! gateIntegrityWritten! testFile? implFiles revertVerdict vacuousForm gateVacuousRounds vacuousRetry unwiredFns revertTimeout]
  :i [(aslAgent/gates :a g) (aslAgent/gitOps :a io) (aslAgent/context :a ctx) (aslAgent/loop :a lp) (aslAgent/core :a c) (aslAgent/diff :a d) (aslAgent/agentConfig :a ac) (asl-syntax/core/bytesText :a bt)])

enum Claim
  (claimOf text: (Option String) receipt: (Option String) cmd: (Option String) exit: (Option Int64) backed: Bool)

fn ! bumpMtime! path: String -> Bool
  (let [stat (fileStat path)]
    (match stat
      ((ok st) (ok? (fileUtime path (+ (nowNs) 2000000000))))
      ((err _) false)))

fn gateFields gate: g/GateResult -> (List String)
  (list (g/gateCmd gate) (stringFromInt64 (g/gateExit gate)) (g/gateStdout gate)
    (g/gateStderr gate) (if (g/gateTimeout gate) "1" "0") (stringFromInt64 (g/gateSeconds gate)))

fn gateResultsGreen gates: (List String) last: (List (Pair String (List (Pair String String)))) -> Bool
  (lp/finalGatesGreen
    (map (fn [cmd]
      (if (listAny? (fn [p] (and (= (pairFirst p) cmd) (listAny? (fn [field] (and (= (pairFirst field) "exit") (= (pairSecond field) "0"))) (pairSecond p)))) last) "1" "0")) gates))

fn continuationByte b: Int64 -> Bool
  (and (>= b 128) (< b 192))

fn safeCut bytes: Bytes n: Int64 total: Int64 -> Int64
  (if (or (>= n total) (not (continuationByte (bytesGet bytes n)))) n (safeCut bytes (- n 1) total))

fn cutParsePrefix reply: String cut: Int64 -> String
  (let [bytes (stringToBytes reply)
        limit (max 0 (min cut (bytesLength bytes)))
        boundary (safeCut bytes limit (bytesLength bytes))]
    (optionOr (stringSlice reply 0 boundary) ""))

fn evidenceForm claim: Claim -> String
  (match claim
    ((claimOf _ receipt cmd exit _)
      (match receipt
        ((some value) (str "(:evidence (:receipt \"" (c/escapeAsn value) "\""
          (match exit ((some n) (str " :exit " (stringFromInt64 n))) ((none) "")) "))"))
        ((none) (str "(:evidence (:cmd \"" (optionOr cmd "") "\" :exit " (stringFromInt64 (optionOr exit 0)) "))"))))
    )

fn claimText claim: Claim -> String
  (match claim ((claimOf txt _ _ _ _)
    (match txt ((some value) (if (stringEmpty? value) (evidenceForm claim) value)) ((none) (evidenceForm claim)))))

fn unbackedTexts claims: (List Claim) -> (List String)
  (map (fn [claim]
         (let [txt (claimText claim)]
           (c/sliceOf txt 0 (min 120 (stringLength txt)))))
    (filter (fn [claim] (match claim ((claimOf _ _ _ _ backed) (not backed)))) claims))

fn noteUnbacked runClaims: (List String) claims: (List Claim) -> (List String)
  (fold (fn [acc t] (if (listContains? acc t) acc (listAppend acc (list t)))) runClaims (unbackedTexts claims))

fn storedBytes files: (List (Pair String (Option String))) rel: String -> (Option String)
  (match (listHead (filter (fn [p] (= (pairFirst p) rel)) files))
    ((some p) (pairSecond p)) ((none) (none)))

fn ! scanOneSwallowed! root: String rel: String old: (Option String) -> (List (Pair String Int64))
  (let [full (io/pyNormpath (str root "/" rel))
        now (match (fileReadString full) ((ok s) (some s)) ((err _) (none)))]
    (match now
      ((none) (list))
      ((some current)
        (if (and (some? old) (= current (optionOr old "")))
          (list)
          (let [before (optionOr old "")
                oldLines (d/splitLinesKeepEnds before)
                newLines (d/splitLinesKeepEnds current)
                hits (g/scanHunkSwallowed! oldLines newLines)]
            (map (fn [line] (pair rel line)) hits))))))

fn ! scanSwallowedLoop! root: String files: (List (Pair String (Option String))) candidates: (List String) -> (List (Pair String Int64))
  (if (listEmpty? candidates)
    (list)
    (let [rel (c/firstOf candidates)
          snap (storedBytes files rel)
          tail (scanSwallowedLoop! root files (c/restOf candidates))
          hit (scanOneSwallowed! root rel snap)]
      (listAppend hit tail)))

fn uniqueStrings xs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? xs) acc
    (let [value (c/firstOf xs)
          next (if (listContains? acc value) acc (listAppend acc (list value)))]
      (uniqueStrings (c/restOf xs) next)))

fn scanPath root: String path: String -> String
  (if (stringStartsWith? path "/") (ctx/pyRelpath path root) (io/pyNormpath path))

fn ! scanSwallowedErrors! root: String written: (List (Pair String (Option String))) extra: (List String) -> (List (Pair String Int64))
  (let [normalizedWritten (map (fn [p] (pair (scanPath root (pairFirst p)) (pairSecond p))) written)
        all (filter (fn [rel] (stringEndsWith? rel ".py"))
              (uniqueStrings (listSort (map (fn [path] (scanPath root path)) (listAppend (map pairFirst normalizedWritten) extra))) (list)))]
    (scanSwallowedLoop! root normalizedWritten all))

fn ! rawHead! root: String rev: String rel: String timeout: Int64 env: (Option (List String)) -> (Option String)
  (match (io/runBounded! (list "git" "show" (str rev ":" rel)) (some root) (some timeout) env (none))
    ((ok b) (if (= (optionOr b.code 1) 0) (some b.out) (none)))
    ((err _) (none)))

; (:m :ref LEON-YIELD-F1 :do "the revision the revert check restores files to: the merge-base of HEAD and the run's base branch, so an implementation the driver committed in an earlier round still differs from it; HEAD when the run has no base, the base is HEAD or the merge-base cannot be resolved (then the old behaviour)")
fn ! revertRev! root: String base: String timeout: Int64 env: (Option (List String)) -> String
  (if (or (stringEmpty? base) (= base "HEAD"))
    "HEAD"
    (match (io/runBounded! (list "git" "merge-base" "HEAD" base) (some root) (some timeout) env (none))
      ((ok b) (let [sha (stringTrim b.out)] (if (and (= (optionOr b.code 1) 0) (not (stringEmpty? sha))) sha "HEAD")))
      ((err _) "HEAD")))

; (:m :ref LEON-YIELD-F1 :do "files of the owned paths committed on the branch since the revert revision; git status lists only uncommitted ones, so a committed implementation was invisible and only doc.asn was reverted")
fn ! committedSince! owns: (List String) root: String rev: String timeout: Int64 env: (Option (List String)) -> (List String)
  (if (or (= rev "HEAD") (listEmpty? owns))
    (list)
    (match (io/runBounded! (listAppend (list "git" "diff" "--name-only" rev "HEAD" "--") owns) (some root) (some timeout) env (none))
      ((ok b) (if (= (optionOr b.code 1) 0) (map io/pyStrip (filter (fn [l] (not (stringEmpty? (io/pyStrip l)))) (io/pySplitLines b.out false))) (list)))
      ((err _) (list))))

fn rstr rec: (List (Pair String io/RVal)) key: String -> String
  (match (io/recGet rec key)
    ((some v) (match v
      ((io/rStr s) s) ((io/rInt n) (stringFromInt64 n)) ((io/rBool b) (if b "true" "false"))
      ((io/rNull) "") ((io/rPair _ _) "")))
    ((none) ""))

fn rint rec: (List (Pair String io/RVal)) key: String -> Int64
  (match (io/recGet rec key)
    ((some v) (match v ((io/rInt n) n) ((io/rNull) -1) ((io/rStr s) (optionOr (stringToInt64 s) -1))
      ((io/rBool _) -1) ((io/rPair _ _) -1)))
    ((none) -1))

fn rbool rec: (List (Pair String io/RVal)) key: String -> Bool
  (= (rstr rec key) "true")

fn ! runIntegrityGates! gates: (List String) root: String timeout: Int64 env: (Option (List String)) watch: (Option Int64) -> (List g/GateResult)
  (map (fn [rec] (g/makeGateResult (rstr rec "cmd") (rint rec "exit") (rstr rec "stdout") (rstr rec "stderr") (rbool rec "timeout") (max 0 (rint rec "seconds"))))
    (io/runGates! (map (fn [cmd] (pair cmd cmd)) gates) root timeout env watch))

fn ! writeTexts! root: String files: (List (Pair String (Option String))) -> Bool
  (fold (fn [ok p]
    (and ok (match (pairSecond p)
      ((some s) (ok? (fileWrite (str root "/" (pairFirst p)) (stringToBytes s))))
      ((none) true))))
    true files)

fn ! bumpTexts! root: String files: (List (Pair String (Option String))) -> Bool
  (fold (fn [ok p] (and ok (bumpMtime! (str root "/" (pairFirst p))))) true files)

fn ! removeNames! root: String files: (List String) -> Bool
  (fold (fn [ok f]
    (and ok (or (ok? (pathRemove (str root "/" f)))
      (not (match (fileStat (str root "/" f)) ((ok _) true) ((err _) false))))))
    true files)

; (:m :ref LEON-REVERTCHECK-GATEFILES :do "gate files are the files a gate command names and test files; everything else that changed is code under test and gets the revert check. Leon's own writes count as changed even when git does not list them (a gitignored scratch/ dir hid the smoke run's leonSmoke.asl, so the check was skipped as gate-only)")
fn testFile? path: String -> Bool
  (let [name (optionOr (listHead (listReverse (stringSplit path "/"))) path)
        stem (optionOr (listHead (stringSplit name ".")) name)]
    (or (stringStartsWith? path "tests/")
      (or (stringContains? path "/tests/")
        (or (stringEndsWith? stem "Test")
          (or (stringStartsWith? name "test_") (stringEndsWith? stem "_test"))))))

fn implFiles changed: (List String) gates: (List String) -> (List String)
  (filter (fn [f] (not (testFile? f))) (pairSecond (g/gatePartitionFiles changed (g/gateRunScripts gates))))

fn quotedList xs: (List String) -> String
  (c/joinSep (map (fn [(x String)] -> String (str "\"" (c/escapeAsn x) "\"")) xs) " ")

fn askText -> String
  ":passesOnRevert true :do \"each gate stays green with the files reverted to HEAD, so it does not test the change; change the test so it fails with them reverted, run it, then finish\")"

fn vacuousText gates: (List String) files: (List String) -> String
  (str "(:gateVacuous :gates (" (quotedList gates) ") :files (" (quotedList files) ") " (askText))

fn passedOnRevert results: (List g/GateResult) verdicts: (List String) -> (List String)
  (match (listHead results)
    ((none) (list))
    ((some r)
      (let [rest (passedOnRevert (optionOr (listTail results) (list)) (optionOr (listTail verdicts) (list)))]
        (if (= (listHead verdicts) (some "passesOnRevert")) (cons (g/gateCmd r) rest) rest))))

; (:m :ref WRITER-GATE-VACUOUS :do "gateRevertVerdict, and when no gate failed on revert and some passed its message gains a second line, the (:gateVacuous ...) form built from the results themselves, so a gate command or path holding '; ', ', ', a quote or a backslash reaches the writer whole")
fn revertVerdict reverted: (List g/GateResult) verdicts: (List String) impl: (List String) newFiles: (List String) -> (Pair Bool String)
  (let [v (g/gateRevertVerdict reverted verdicts impl newFiles)
        green (passedOnRevert reverted verdicts)]
    (if (or (pairFirst v) (listEmpty? green))
      v
      (pair false (str (pairSecond v) "\n" (vacuousText green impl)))))

; (:m :ref WRITER-GATE-VACUOUS :do "the (:gateVacuous ...) line revertVerdict added to a failed revert check, the one form the writer gets; none when the check passed or failed for another cause (no asserts, restore failed)")
fn vacuousForm integrity: (Pair Bool String) -> (Option String)
  (let [msg (pairSecond integrity)]
    (if (pairFirst integrity)
      none
      (match (stringIndexOf msg "\n(:gateVacuous ")
        ((none) (match (stringIndexOf msg "\n(:gateUnwired") ((none) none) ((some at) (stringSlice msg (+ at 1) (stringLength msg)))))
        ((some at) (stringSlice msg (+ at 1) (stringLength msg))))))

fn defaultGateVacuousRounds -> Int64
  2

; (:m :ref WRITER-GATE-VACUOUS :do "how many finished turns whose gate passes on revert go back to the writer before the run ends failed with signal gateIntegrity: :agentLoop :gateVacuousRounds of .asl.config.asn, a positive integer, default 2")
fn gateVacuousRounds cfgText: String -> Int64
  (match (ac/agentLoopValue cfgText ":gateVacuousRounds")
    ((some v) (optionOr (ac/positiveInt v) (defaultGateVacuousRounds)))
    ((none) (defaultGateVacuousRounds)))

; (:m :ref WRITER-GATE-VACUOUS :do "the form to send back when the revert check found a gate green without the change and the rounds sent so far are under the cap; none means the run ends as before, failed with signal gateIntegrity")
fn vacuousRetry integrity: (Pair Bool String) rounds: Int64 cap: Int64 -> (Option String)
  (if (< rounds cap) (vacuousForm integrity) none)

fn unionPaths a: (List String) b: (List String) -> (List String)
  (fold (fn [acc f] (if (listContains? acc f) acc (listAppend acc (list f)))) a b)

fn ! gateIntegrityWritten! gates: (List String) owns: (List String) root: String gateResults: (List g/GateResult) timeout: Int64 env: (Option (List String)) written: (List String) watch: (Option Int64) base: String -> (Pair Bool String)
  (match (io/changedOwnedFiles! owns root env)
    ((err message) (pair false (str "changedOwnedFiles failed: " message)))
    ((ok changed)
      (let [rev (revertRev! root base timeout env)
            all (unionPaths (unionPaths changed (committedSince! owns root rev timeout env)) (map (fn [f] (scanPath root f)) written))]
        (gateIntegrityWithChanged! gates root gateResults timeout env all watch rev))))

fn ! gateIntegrity! gates: (List String) owns: (List String) root: String gateResults: (List g/GateResult) timeout: Int64 env: (Option (List String)) -> (Pair Bool String)
  (match (io/changedOwnedFiles! owns root env)
    ((err message) (pair false (str "changedOwnedFiles failed: " message)))
    ((ok changed) (gateIntegrityWithChanged! gates root gateResults timeout env changed (none) "HEAD")))

fn fnName line: String -> String
  (let [toks (filter (fn [t] (not (stringEmpty? t))) (stringSplit line " "))
        second (optionOr (listGet toks 1) "")]
    (if (= second "!") (optionOr (listGet toks 2) "") second))

fn fnNames text: String -> (List String)
  (map fnName (filter (fn [line] (or (stringStartsWith? line "fn ") (stringStartsWith? line "fn ! "))) (stringLines text)))

fn countName name: String texts: (List String) -> Int64
  (fold
    (fn [acc t]
      (+ acc
        (pairSecond
          (fold
            (fn [state line]
              (let [inHeader (pairFirst state)
                    n (pairSecond state)
                    endHeader (or (stringStartsWith? line "fn")
                                  (or (stringStartsWith? line "enum")
                                      (or (stringStartsWith? line "schema")
                                          (or (stringStartsWith? line ";")
                                              (stringStartsWith? line "#")))))
                    counted (if (stringContains? line name) (+ n 1) n)]
                (if inHeader
                  (if endHeader (pair false counted) state)
                  (if (stringStartsWith? line "(module")
                    (pair true n)
                    (pair false counted)))))
            (pair false 0)
            (stringLines t)))))
    0
    texts)

fn unwiredFns implNow: (List (Pair String String)) implHead: (List (Pair String String)) -> (List String)
  (let [defs (fold (fn [acc p] (listAppend acc (map (fn [n] (pair (pairFirst p) n)) (fnNames (pairSecond p))))) (list) implNow)
        headDefs (fold (fn [acc p] (listAppend acc (map (fn [n] (pair (pairFirst p) n)) (fnNames (pairSecond p))))) (list) implHead)
        newDefs (filter (fn [d] (not (listAny? (fn [h] (and (= (pairFirst h) (pairFirst d)) (= (pairSecond h) (pairSecond d)))) headDefs))) defs)
        texts (map pairSecond implNow)]
    (map pairSecond (filter (fn [d] (= (countName (pairSecond d) texts) 1)) newDefs)))

; (:m :ref REVERT-REBUILD-FLOOR :do "a revert run of an asl-agent source rebuilds the native closure, 557 s for toolMemoLoopTest on 2026-11-09 against a 3 s run with the change, so a revert gate gets at least 900 s; under the 300 s gate timeout every such revert timed out")
fn revertTimeout timeout: Int64 -> Int64
  (if (< timeout 60) timeout (max timeout 900))

fn ! gateIntegrityWithChanged! gates: (List String) root: String gateResults: (List g/GateResult) timeout: Int64 env: (Option (List String)) changed: (List String) watch: (Option Int64) rev: String -> (Pair Bool String)
  (let [impl (implFiles changed gates)
        verdicts (g/gateVerdicts gateResults false)
        vac (g/gateVacuousMessage gateResults verdicts)]
    (match vac
      ((some msg) (pair false msg))
      ((none)
        (if (listEmpty? impl)
          (pair true "revertCheck skipped: the change is only the gate files")
          (let [saved (map (fn [f] (pair f (match (fileReadBytes (str root "/" f)) ((ok b) (some b)) ((err _) (none))))) impl)
              headText (map (fn [f] (pair f (rawHead! root rev f timeout env))) impl)
              existing (filter (fn [p] (some? (pairSecond p))) headText)
              newFiles (map pairFirst (filter (fn [p] (not (some? (pairSecond p)))) headText))
              wroteHead (writeTexts! root existing)
              bumped (fold (fn [ok p] (and ok (bumpMtime! (str root "/" (pairFirst p))))) wroteHead existing)
              firstRun (if (and bumped (not (listEmpty? existing))) (runIntegrityGates! gates root (revertTimeout timeout) env watch) (list))
              firstDecision (revertVerdict firstRun (g/gateVerdicts firstRun true) impl newFiles)
              answer (if (and bumped (pairFirst firstDecision))
                firstDecision
                (let [headRestored (and (writeTexts! root existing) (bumpTexts! root existing))
                      removedNew (removeNames! root newFiles)
                      secondRun (if (and headRestored removedNew) (runIntegrityGates! gates root (revertTimeout timeout) env watch) (list))]
                  (revertVerdict secondRun (g/gateVerdicts secondRun true) impl (list))))
              implNow (map (fn [p] (pair (pairFirst p) (match (pairSecond p) ((some b) (bt/bytesToString b)) ((none) "")))) saved)
              implHead (map (fn [p] (pair (pairFirst p) (optionOr (pairSecond p) ""))) headText)
              unwired (if (and (pairFirst answer) (stringContains? (pairSecond answer) ":revertKind compile")) (unwiredFns implNow implHead) (list))
              finalAnswer (if (listEmpty? unwired) answer (pair false (str "unwired: new fns with no caller outside tests: " (stringJoin unwired ", ") "; call them from the code path the task changes, then finish" "\n(:gateUnwired :fns (" (stringJoin (map (fn [n] (str "\"" n "\"")) unwired) " ") ") :do \"call each from the code path the task changes, then finish\")")))
              restored (fold (fn [ok p] (and ok (match (pairSecond p)
                ((some b) (and (ok? (fileWrite (str root "/" (pairFirst p)) b)) (bumpMtime! (str root "/" (pairFirst p)))))
                ((none) (removeNames! root (list (pairFirst p))))))) true saved)]
          (if restored finalAnswer (pair false "restore failed")))))))
