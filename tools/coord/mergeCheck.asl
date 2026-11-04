(module asl-tools/coord/mergeCheck
  :x [failedRows normEv rowKey classify judgeSuite SuiteRun suiteReceipt planRow planId missingRows oneAsnLine? conflictMarkers? touchedSuites checkSide! gitOut! run! main]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/coord/gateGuard :a gg)])

; (:m :ref MERGE-CHECK :do "asl run asl/tools/coord/mergeCheck.asl --base REF --head REF [--repo DIR] [--ledger FILE] [--cli PATH] [--deadline S] [--step S] [--max-suites N] [--only SUITE,..]: one merge-time audit that blocks only on what the change introduces; structure of base..head, asl audit consistency and gates (no suites) on both sides compared by check id and normalised :ev, then the suites of the touched packages at head against base; pre-existing reds never block, they print as plan rows and --ledger appends the missing ones; steps the deadline cut off are listed unverified, never passed; exit 0 pass, 1 block, 2 bad invocation")

(schema SuiteRun
  (:f path String)
  (:f exit Int64)
  (:f asserts Int64)
  (:f verdict String)
  (:f why String :default ""))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn n x: Int64 -> String
  (stringFromInt64 x)

fn flagArg args: (List String) name: String -> (Option String)
  (match (listHead args)
    ((none) (none))
    ((some a) (let [(rest (optionOr (listTail args) (list)))]
                (if (= a name) (listHead rest) (flagArg rest name)))))

fn nonEmpty xs: (List String) -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) xs)

; (:m :do "digit runs collapse to one # so a drifting count (+101 then +104) keeps one identity while a new path or a new message is new")
fn normEv ev: String -> String
  (let [(digits (fold (fn [(s String) (d Int64)] -> String (stringReplace s (n d) "#")) ev (range 0 10)))]
    (fold (fn [(s String) (i Int64)] -> String (stringReplace s "##" "#")) digits (range 0 16)))

fn rowKey id: String ev: String -> String
  (str id "|" (normEv ev))

; (:m :do "the failed (:check :id X ... :ev \"..\") rows of an audit receipt as (id, ev) pairs, in order; a passed check, the header line and a receipt with no checks give nothing")
fn failedRows text: String -> (List (Pair String String))
  (let [(parts (optionOr (listTail (stringSplit text "(:check :id ")) (list)))]
    (map (fn [(p String)] -> (Pair String String)
           (let [(id (optionOr (listHead (stringSplit p " ")) ""))
                 (evParts (stringSplit p " :ev \""))
                 (ev (if (< (listLength evParts) 2) "" (optionOr (listHead (stringSplit (optionOr (listGet evParts 1) "") "\")")) "")))]
             (pair id ev)))
         (filter (fn [(p String)] -> Bool
                   (let [(head (optionOr (listHead (stringSplit p " :ev \"")) p))
                         (own (optionOr (listHead (stringSplit head "(:")) head))]
                     (stringContains? own " :status :failed")))
                 parts)))

fn hasKey? rows: (List (Pair String String)) k: String -> Bool
  (listAny? (fn [(r (Pair String String))] -> Bool (= (rowKey (pairFirst r) (pairSecond r)) k)) rows)

fn dedupRows rows: (List (Pair String String)) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (r (Pair String String))] -> (List (Pair String String))
          (if (hasKey? acc (rowKey (pairFirst r) (pairSecond r))) acc (listAppend acc (list r))))
        (list) rows)

; (:m :do "head reds absent from base are regressions (a red with a new :ev is a new key), head reds also on base are pre-existing; pair of (regressions, preExisting)")
fn classify head: (List (Pair String String)) base: (List (Pair String String)) -> (Pair (List (Pair String String)) (List (Pair String String)))
  (let [(rows (dedupRows head))]
    (pair (filter (fn [(r (Pair String String))] -> Bool (not (hasKey? base (rowKey (pairFirst r) (pairSecond r))))) rows)
          (filter (fn [(r (Pair String String))] -> Bool (hasKey? base (rowKey (pairFirst r) (pairSecond r)))) rows)))

; (:m :do "one suite at head against its base run (baseExit -1 means the base was not run, -2 that the suite is absent at base): regression, preExisting, unverified or pass; a timeout at head is unverified, any failure is a regression unless base failed too, fewer executed asserts than a green base is a regression")
fn judgeSuite h: SuiteRun baseExit: Int64 baseAsserts: Int64 -> String
  (cond
    ((or (= h.verdict "timeout") (= h.verdict "runaway")) "unverified")
    ((!= h.exit 0) (if (> baseExit 0) "preExisting" "regression"))
    ((and (= baseExit 0) (< h.asserts baseAsserts)) "regression")
    (else "pass"))

fn suiteReceipt h: SuiteRun baseExit: Int64 baseAsserts: Int64 -> String
  (str "(:suite " (q h.path) " :exit " (n h.exit) " :asserts " (n h.asserts) " :baseExit " (n baseExit) " :baseAsserts " (n baseAsserts) " :judged :" (judgeSuite h baseExit baseAsserts) (if (= h.exit 0) "" (str " :why " (q h.why))) ")")

fn digest8 s: String -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes s)) 0 8) "")

fn planId id: String ev: String -> String
  (str "MC-" id "-" (digest8 (rowKey id ev)))

; (:m :do "the ready-to-append plan row for a pre-existing red")
fn planRow id: String ev: String -> String
  (str "(:u " (planId id ev) " :p p1 :do " (q (str "pre-existing red " id (if (stringEmpty? ev) "" (str ": " ev)) "; fix it or record why it stays")) " :src mergeCheck)")

; (:m :do "rows whose id the ledger text does not carry yet, so a second append adds nothing")
fn missingRows ledger: String rows: (List (Pair String String)) -> (List String)
  (map (fn [(r (Pair String String))] -> String (planRow (pairFirst r) (pairSecond r)))
       (filter (fn [(r (Pair String String))] -> Bool (not (stringContains? ledger (str "(:u " (planId (pairFirst r) (pairSecond r)) " ")))) rows))

; (:m :do "a commit message is one ASN line: a single non-empty line that opens (:c and closes with a paren")
fn oneAsnLine? msg: String -> Bool
  (let [(t (stringTrim msg))]
    (and (not (stringEmpty? t)) (and (not (stringContains? t "\n")) (and (stringStartsWith? t "(:c ") (stringEndsWith? t ")")))))

; (:m :do "an added line of a diff that opens or closes a conflict block; only added lines count so a doc quoting markers in context does not")
fn conflictMarkers? diff: String -> Bool
  (listAny? (fn [(l String)] -> Bool
              (or (stringStartsWith? l "+<<<<<<< ") (or (stringStartsWith? l "+>>>>>>> ") (= l "+=======")))) 
            (stringLines diff))

fn isSuite? p: String -> Bool
  (and (stringEndsWith? p "Test.asl") (stringContains? p "/tests/"))

fn parentDir p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

; (:m :do "the nearest ancestor dir of a touched file that has a tests dir, as its dir path, empty when none")
fn testsDirOf! side: String p: String -> String
  (if (or (stringEmpty? p) (= p ".")) ""
    (let [(d (parentDir p))]
      (cond
        ((stringEmpty? d) "")
        ((fileExists? (str side "/" d "/tests")) (str d "/tests"))
        (else (testsDirOf! side d)))))

; (:m :do "suites of the touched packages: a touched suite itself, the *Test.asl files in the nearest tests dir of each touched file, and the suites whose text imports a touched module; first max, sorted, no duplicates")
fn touchedSuites side: String files: (List String) importerPaths: (List String) max: Int64 -> (List String)
  (let [(own (filter isSuite? files))
        (dirs (fold (fn [(acc (List String)) (p String)] -> (List String)
                      (let [(d (testsDirOf! side p))] (if (or (stringEmpty? d) (listContains? acc d)) acc (cons d acc))))
                    (list) (filter (fn [(p String)] -> Bool (not (isSuite? p))) files)))
        (inDirs (fold (fn [(acc (List String)) (d String)] -> (List String)
                        (listAppend acc (map (fn [(f String)] -> String (str d "/" f))
                                             (filter (fn [(f String)] -> Bool (stringEndsWith? f "Test.asl")) (resultOr (dirList (str side "/" d)) (list))))))
                      (list) dirs))
        (all (fold (fn [(acc (List String)) (p String)] -> (List String) (if (listContains? acc p) acc (listAppend acc (list p))))
                   (list) (listAppend own (listAppend inDirs importerPaths))))]
    (listTake (listSort all) max))

fn ! gitOut! dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! cliOf side: String cli: String -> String
  (if (stringEmpty? cli) (str side "/bin/asl") cli)

fn leftS deadlineNs: Int64 stepS: Int64 -> Int64
  (let [(left (/ (- deadlineNs (monotonicNs)) 1000000000))]
    (if (< left stepS) left stepS))

; (:m :do "audit sub (consistency|gates) at side with the step bound: the failed rows and whether the audit ran (exit 0 or 1 with a receipt); gates run with suites off by default")
fn ! checkSide! side: String cli: String sub: String deadlineNs: Int64 stepS: Int64 -> (Result (List (Pair String String)) String)
  (let [(s (leftS deadlineNs stepS))]
    (if (<= s 0) (err "deadline")
      (let [(d (fr/runOneLimited (fr/job (list (cliOf side cli) "audit" sub) side (fr/sideEnv side)) (fr/limits s 64)))]
        (cond
          ((or (= d.verdict "timeout") (= d.verdict "runaway")) (err (str "timeout " sub)))
          ((not (stringContains? d.out "(:audit ")) (err (str "no receipt " sub " exit " (n d.exit))))
          (else (ok (failedRows d.out)))))))

; (:m :do "the last non-empty line of a suite's output, cut to 240 chars: the failing assert or load error a blocked merge shows")
fn whyOf out: String -> String
  (let [(ls (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines out)))
        (l (stringTrim (optionOr (listLast ls) "")))]
    (optionOr (stringSlice l 0 240) l))

fn ! runSuite! side: String cli: String path: String deadlineNs: Int64 stepS: Int64 -> (Option SuiteRun)
  (let [(s (leftS deadlineNs stepS))]
    (if (<= s 0) (none)
      (let [(d (fr/runOneLimited (fr/job (list (cliOf side cli) "test" path) side (fr/sideEnv side)) (fr/limits s 64)))]
        (some (SuiteRun :path path :exit d.exit :asserts (optionOr (fr/executedOf d.out) 0) :verdict d.verdict :why (whyOf d.out))))))

fn ! lines! dir: String argv: (List String) -> (List String)
  (let [(d (gitOut! dir argv))]
    (if (= d.exit 0) (nonEmpty (map stringTrim (stringLines d.out))) (list)))

fn ! addSide! repo: String path: String sha: String -> Bool
  (= (gitOut! repo (list "worktree" "add" "--detach" path sha)).exit 0)

fn ! dropSide! repo: String path: String -> Bool
  (let [(r (gitOut! repo (list "worktree" "remove" "--force" path)))
        (_ (if (fileExists? path) (ok? (pathRemove path)) false))]
    (= r.exit 0))

fn rows2s rows: (List (Pair String String)) -> String
  (stringJoin (map (fn [(r (Pair String String))] -> String (str "(:check :id " (pairFirst r) " :ev " (q (pairSecond r)) ")")) rows) " ")

fn ! structure! repo: String base: String head: String -> (List String)
  (let [(anc (gitOut! repo (list "merge-base" "--is-ancestor" base head)))
        (files (lines! repo (list "diff" "--name-only" base head)))
        (shas (lines! repo (list "log" "--format=%H" (str base ".." head))))
        (bad (filter (fn [(sha String)] -> Bool
                       (not (oneAsnLine? (gitOut! repo (list "log" "-1" "--format=%B" sha)).out)))
                     (listTake shas 200)))
        (diff (gitOut! repo (list "diff" base head)))]
    (nonEmpty (list (if (= anc.exit 0) "" "baseNotAncestorOfHead")
                    (if (stringEmpty? (stringTrim (stringJoin files ""))) "emptyDiff" "")
                    (if (listEmpty? shas) "noHeadCommits" "")
                    (if (listEmpty? bad) "" (str "notOneAsnLine " (stringJoin (map (fn [(s String)] -> String (optionOr (stringSlice s 0 9) s)) bad) ",")))
                    (if (conflictMarkers? diff.out) "conflictMarkers" ""))))

; (:m :do "suites at head whose text imports a touched module: git grep narrows by name, the import position decides")
fn ! importerSuites! repo: String hd: String sha: String mods: (List String) -> (List String)
  (let [(cut (fn [(l String)] -> String (let [(k (+ (stringLength sha) 1))] (optionOr (stringSlice l k (stringLength l)) l))))
        (cands (nonEmpty (map cut (listFlatMap (fn [(m String)] -> (List String) (lines! repo (list "grep" "-l" "-F" m sha "--" "*Test.asl"))) mods))))]
    (filter (fn [(p String)] -> Bool
              (let [(t (resultOr (fileReadString (str hd "/" p)) ""))]
                (listAny? (fn [(m String)] -> Bool (gg/importsModule? t m)) mods)))
            cands))

fn ! run! repoArg: String base: String head: String ledger: String cli: String totalS: Int64 stepS: Int64 maxSuites: Int64 only: (List String) -> (Pair Int64 String)
  (let [(repo (resultOr (realPath repoArg) repoArg))
        (deadlineNs (+ (monotonicNs) (* totalS 1000000000)))
        (baseSha (stringTrim (gitOut! repo (list "rev-parse" "--verify" base)).out))
        (headSha (stringTrim (gitOut! repo (list "rev-parse" "--verify" head)).out))]
    (if (or (stringEmpty? baseSha) (stringEmpty? headSha))
      (pair 2 (str "(:mergeCheck :verdict block :error " (q "base or head does not resolve") ")"))
      (let [(problems (structure! repo baseSha headSha))
            (files (lines! repo (list "diff" "--name-only" baseSha headSha)))
            (tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/mergeCheck-" (n (procSelf)) "-" (n (/ (monotonicNs) 1000000))))
            (_ (dirCreate tmp))
            (hd (str tmp "/head"))
            (bd (str tmp "/base"))
            (hOk (addSide! repo hd headSha))
            (bOk (addSide! repo bd baseSha))]
        (if (not (and hOk bOk))
          (let [(_ (dropSide! repo hd))
                (_ (dropSide! repo bd))
                (_ (pathRemove tmp))]
            (pair 2 (str "(:mergeCheck :verdict block :error " (q "cannot check out base and head") ")")))
          (let [(hc (checkSide! hd cli "consistency" deadlineNs stepS))
                (bc (checkSide! bd cli "consistency" deadlineNs stepS))
                (hg (checkSide! hd cli "gates" deadlineNs stepS))
                (bg (checkSide! bd cli "gates" deadlineNs stepS))
                (cmp (fn [(h (Result (List (Pair String String)) String)) (b (Result (List (Pair String String)) String)) (nm String)]
                       -> (Pair (Pair (List (Pair String String)) (List (Pair String String))) (List String))
                       (match h
                         ((err e) (pair (pair (list) (list)) (list (str nm "Head:" e))))
                         ((ok hr) (match b
                                    ((err e) (pair (pair (list) (list)) (list (str nm "Base:" e))))
                                    ((ok br) (pair (classify hr br) (list))))))))
                (c1 (cmp hc bc "consistency"))
                (c2 (cmp hg bg "gates"))
                (regs (listAppend (pairFirst (pairFirst c1)) (pairFirst (pairFirst c2))))
                (pre (listAppend (pairSecond (pairFirst c1)) (pairSecond (pairFirst c2))))
                (unv0 (listAppend (pairSecond c1) (pairSecond c2)))
                (mods (nonEmpty (map (fn [(p String)] -> String (gg/moduleName (resultOr (fileReadString (str hd "/" p)) ""))) (filter (fn [(p String)] -> Bool (and (stringEndsWith? p ".asl") (not (isSuite? p)))) files))))
                (imp (importerSuites! repo hd headSha mods))
                (suites (if (listEmpty? only) (touchedSuites hd files imp maxSuites) only))
                (headRuns (map (fn [(p String)] -> (Option SuiteRun) (if (fileExists? (str hd "/" p)) (runSuite! hd cli p deadlineNs stepS) (none))) suites))
                (ran (filter (fn [(o (Option SuiteRun))] -> Bool (match o ((some _) true) ((none) false))) headRuns))
                (hRows (map (fn [(o (Option SuiteRun))] -> SuiteRun (optionOr o (SuiteRun :path "" :exit 0 :asserts 0 :verdict ""))) ran))
                (failedFirst (listAppend (filter (fn [(r SuiteRun)] -> Bool (!= r.exit 0)) hRows) (filter (fn [(r SuiteRun)] -> Bool (= r.exit 0)) hRows)))
                (baseRuns (map (fn [(r SuiteRun)] -> (Pair SuiteRun (Option SuiteRun))
                                 (pair r (if (fileExists? (str bd "/" r.path)) (runSuite! bd cli r.path deadlineNs stepS) (some (SuiteRun :path r.path :exit -2 :asserts 0 :verdict "absent")))))
                               failedFirst))
                (judged (map (fn [(pr (Pair SuiteRun (Option SuiteRun)))] -> (Pair SuiteRun String)
                               (let [(h (pairFirst pr))
                                     (be (match (pairSecond pr) ((some b) (if (= b.verdict "absent") -2 (if (or (= b.verdict "timeout") (= b.verdict "runaway")) -1 b.exit))) ((none) -1)))
                                     (ba (match (pairSecond pr) ((some b) b.asserts) ((none) 0)))]
                                 (pair h (suiteReceipt h be ba))))
                             baseRuns))
                (notRun (filter (fn [(p String)] -> Bool (not (listAny? (fn [(r SuiteRun)] -> Bool (= r.path p)) hRows))) (filter (fn [(p String)] -> Bool (fileExists? (str hd "/" p))) suites)))
                (suiteRegs (filter (fn [(j (Pair SuiteRun String))] -> Bool (stringContains? (pairSecond j) ":judged :regression")) judged))
                (suiteUnv (filter (fn [(j (Pair SuiteRun String))] -> Bool (stringContains? (pairSecond j) ":judged :unverified")) judged))
                (unv (listAppend unv0 (listAppend (map (fn [(p String)] -> String (str "suite:" p ":notRun")) notRun)
                                                  (map (fn [(j (Pair SuiteRun String))] -> String (str "suite:" (pairFirst j).path ":timeout")) suiteUnv))))
                (_ (dropSide! repo hd))
                (_ (dropSide! repo bd))
                (_ (pathRemove tmp))
                (blocked (or (not (listEmpty? problems)) (or (not (listEmpty? regs)) (not (listEmpty? suiteRegs)))))
                (preRows (dedupRows pre))
                (planRows (map (fn [(r (Pair String String))] -> String (planRow (pairFirst r) (pairSecond r))) preRows))
                (added (if (stringEmpty? ledger) (list)
                         (let [(miss (missingRows (resultOr (fileReadString ledger) "") preRows))
                               (_ (if (listEmpty? miss) false (ok? (fileAppend ledger (stringToBytes (str (stringJoin miss "\n") "\n"))))))]
                           miss)))
                (receipt (str "(:mergeCheck :verdict " (if blocked "block" "pass")
                              " :base " (q baseSha) " :head " (q headSha)
                              " :complete " (if (listEmpty? unv) "true" "false")
                              " :structure (" (stringJoin (map q problems) " ") ")"
                              " :regressions (" (rows2s regs) (if (or (listEmpty? regs) (listEmpty? suiteRegs)) "" " ") (stringJoin (map pairSecond suiteRegs) " ") ")"
                              " :preExisting (" (rows2s preRows) ")"
                              " :suites (" (stringJoin (map pairSecond judged) " ") ")"
                              " :unverified (" (stringJoin (map q unv) " ") ")"
                              " :planRows (" (stringJoin planRows " ") ")"
                              " :ledgerAdded " (n (listLength added)) ")"))]
            (pair (if blocked 1 0) receipt))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(base (optionOr (flagArg args "--base") ""))
        (head (optionOr (flagArg args "--head") ""))]
    (if (or (stringEmpty? base) (stringEmpty? head))
      (do (eprintln "usage: mergeCheck --base REF --head REF [--repo DIR] [--ledger FILE] [--cli PATH] [--deadline S] [--step S] [--max-suites N]") (ok 2))
      (let [(r (run! (optionOr (flagArg args "--repo") ".") base head (optionOr (flagArg args "--ledger") "") (optionOr (flagArg args "--cli") "")
                     (optionOr (stringToInt64 (optionOr (flagArg args "--deadline") "1500")) 1500)
                     (optionOr (stringToInt64 (optionOr (flagArg args "--step") "300")) 300)
                     (optionOr (stringToInt64 (optionOr (flagArg args "--max-suites") "12")) 12)
                     (nonEmpty (map stringTrim (stringSplit (optionOr (flagArg args "--only") "") ",")))))]
        (do (println (pairSecond r)) (ok (pairFirst r))))))
