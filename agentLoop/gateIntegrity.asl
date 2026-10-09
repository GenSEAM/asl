(module asl/agentLoop/gateIntegrity
  :x [Claim claimOf bumpMtime! gateFields gateResultsGreen cutParsePrefix evidenceForm unbackedTexts noteUnbacked scanSwallowedErrors! gateIntegrity!]
  :i [(asl/agentLoop/gates :a g) (asl/agentLoop/gitOps :a io) (asl/agentLoop/context :a ctx) (asl/agentLoop/loop :a lp) (asl/agentLoop/core :a c) (asl/agentLoop/diff :a d)])

enum Claim
  (claimOf text: (Option String) receipt: (Option String) cmd: (Option String) exit: (Option Int64) backed: Bool)

fn ! bumpMtime! path: String -> Bool
  (let [stat (fileStat path)]
    (mt stat
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
  (mt claim
    ((claimOf _ receipt cmd exit _)
      (mt receipt
        ((some value) (str "(:evidence (:receipt \"" (c/escapeAsn value) "\""
          (mt exit ((some n) (str " :exit " (stringFromInt64 n))) ((none) "")) "))"))
        ((none) (str "(:evidence (:cmd \"" (optionOr cmd "") "\" :exit " (stringFromInt64 (optionOr exit 0)) "))"))))
    )

fn claimText claim: Claim -> String
  (mt claim ((claimOf txt _ _ _ _)
    (mt txt ((some value) (if (stringEmpty? value) (evidenceForm claim) value)) ((none) (evidenceForm claim)))))

fn unbackedTexts claims: (List Claim) -> (List String)
  (map (fn [claim]
         (let [txt (claimText claim)]
           (c/sliceOf txt 0 (min 120 (stringLength txt)))))
    (filter (fn [claim] (mt claim ((claimOf _ _ _ _ backed) (not backed)))) claims))

fn noteUnbacked runClaims: (List String) claims: (List Claim) -> (List String)
  (fold (fn [acc t] (if (listContains? acc t) acc (listAppend acc (list t)))) runClaims (unbackedTexts claims))

fn storedBytes files: (List (Pair String (Option String))) rel: String -> (Option String)
  (mt (listHead (filter (fn [p] (= (pairFirst p) rel)) files))
    ((some p) (pairSecond p)) ((none) (none)))

fn ! scanOneSwallowed! root: String rel: String old: (Option String) -> (List (Pair String Int64))
  (let [full (io/pyNormpath (str root "/" rel))
        now (mt (fileReadString full) ((ok s) (some s)) ((err _) (none)))]
    (mt now
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

fn ! rawHead! root: String rel: String timeout: Int64 env: (Option (List String)) -> (Option String)
  (mt (io/runBounded! (list "git" "show" (str "HEAD:" rel)) (some root) (some timeout) env)
    ((ok b) (if (= (optionOr b.code 1) 0) (some b.out) (none)))
    ((err _) (none)))

fn rstr rec: (List (Pair String io/RVal)) key: String -> String
  (mt (io/recGet rec key)
    ((some v) (mt v
      ((io/rStr s) s) ((io/rInt n) (stringFromInt64 n)) ((io/rBool b) (if b "true" "false"))
      ((io/rNull) "") ((io/rPair _ _) "")))
    ((none) ""))

fn rint rec: (List (Pair String io/RVal)) key: String -> Int64
  (mt (io/recGet rec key)
    ((some v) (mt v ((io/rInt n) n) ((io/rNull) -1) ((io/rStr s) (optionOr (stringToInt64 s) -1))
      ((io/rBool _) -1) ((io/rPair _ _) -1)))
    ((none) -1))

fn rbool rec: (List (Pair String io/RVal)) key: String -> Bool
  (= (rstr rec key) "true")

fn ! runIntegrityGates! gates: (List String) root: String timeout: Int64 env: (Option (List String)) -> (List g/GateResult)
  (map (fn [rec] (g/makeGateResult (rstr rec "cmd") (rint rec "exit") (rstr rec "stdout") (rstr rec "stderr") (rbool rec "timeout") (max 0 (rint rec "seconds"))))
    (io/runGates! (map (fn [cmd] (pair cmd cmd)) gates) root timeout env))

fn ! writeTexts! root: String files: (List (Pair String (Option String))) -> Bool
  (fold (fn [ok p]
    (and ok (mt (pairSecond p)
      ((some s) (ok? (fileWrite (str root "/" (pairFirst p)) (stringToBytes s))))
      ((none) true))))
    true files)

fn ! bumpTexts! root: String files: (List (Pair String (Option String))) -> Bool
  (fold (fn [ok p] (and ok (bumpMtime! (str root "/" (pairFirst p))))) true files)

fn ! removeNames! root: String files: (List String) -> Bool
  (fold (fn [ok f]
    (and ok (or (ok? (pathRemove (str root "/" f)))
      (not (mt (fileStat (str root "/" f)) ((ok _) true) ((err _) false))))))
    true files)

fn ! gateIntegrity! gates: (List String) owns: (List String) root: String gateResults: (List g/GateResult) timeout: Int64 env: (Option (List String)) -> (Pair Bool String)
  (mt (io/changedOwnedFiles! owns root env)
    ((err message) (pair false (str "changedOwnedFiles failed: " message)))
    ((ok changed) (gateIntegrityWithChanged! gates root gateResults timeout env changed)))

fn ! gateIntegrityWithChanged! gates: (List String) root: String gateResults: (List g/GateResult) timeout: Int64 env: (Option (List String)) changed: (List String) -> (Pair Bool String)
  (let [split (g/gatePartitionFiles changed (g/gateRunScripts gates))
        impl (pairSecond split)
        verdicts (g/gateVerdicts gateResults false)
        vac (g/gateVacuousMessage gateResults verdicts)]
    (mt vac
      ((some msg) (pair false msg))
      ((none)
        (if (listEmpty? impl)
          (pair true "revertCheck skipped: the change is only the gate files")
          (let [saved (map (fn [f] (pair f (mt (fileReadBytes (str root "/" f)) ((ok b) (some b)) ((err _) (none))))) impl)
              headText (map (fn [f] (pair f (rawHead! root f timeout env))) impl)
              existing (filter (fn [p] (some? (pairSecond p))) headText)
              newFiles (map pairFirst (filter (fn [p] (not (some? (pairSecond p)))) headText))
              wroteHead (writeTexts! root existing)
              bumped (fold (fn [ok p] (and ok (bumpMtime! (str root "/" (pairFirst p))))) wroteHead existing)
              firstRun (if (and bumped (not (listEmpty? existing))) (runIntegrityGates! gates root timeout env) (list))
              firstDecision (g/gateRevertVerdict firstRun (g/gateVerdicts firstRun true) impl newFiles)
              answer (if (and bumped (pairFirst firstDecision))
                firstDecision
                (let [headRestored (and (writeTexts! root existing) (bumpTexts! root existing))
                      removedNew (removeNames! root newFiles)
                      secondRun (if (and headRestored removedNew) (runIntegrityGates! gates root timeout env) (list))]
                  (g/gateRevertVerdict secondRun (g/gateVerdicts secondRun true) impl (list))))
              restored (fold (fn [ok p] (and ok (mt (pairSecond p)
                ((some b) (and (ok? (fileWrite (str root "/" (pairFirst p)) b)) (bumpMtime! (str root "/" (pairFirst p)))))
                ((none) (removeNames! root (list (pairFirst p))))))) true saved)]
          (if restored answer (pair false "restore failed")))))))
