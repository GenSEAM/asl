(module asl-tools/coord/mergeCheck
  :x [failedRows normEv evDelta rowKey classify judgeSuite SuiteRun Opts cleanEnvWith keepEnv? secretLike? redactWhy whyOf failId toolVersion cacheHeader cacheLoad! cacheSave! cachePath suiteReceipt planRow planId missingRows oneAsnLine? conflictMarkers? touchedSuites checkSide! gitOut! run! main]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/coord/gateGuard :a gg)])

; (:m :ref MERGE-CHECK :do "asl run asl/tools/coord/mergeCheck.asl --base REF --head REF [--repo DIR] [--ledger FILE] [--cli PATH] [--deadline S] [--step S] [--max-suites N] [--only SUITE,..]: one merge-time audit that blocks only on what the change introduces; structure of base..head, asl audit consistency and gates (no suites) on both sides compared by check id and normalised :ev, then the suites of the touched packages at head against base; pre-existing reds never block, they print as plan rows and --ledger appends the missing ones; steps the deadline cut off are listed unverified, never passed; exit 0 pass, 1 block, 2 bad invocation")

(schema SuiteRun
  (:f path String)
  (:f exit Int64)
  (:f asserts Int64)
  (:f verdict String)
  (:f why String :default "")
  (:f retried Bool :default false)
  (:f firstWhy String :default ""))

(schema Opts
  (:f repo String)
  (:f base String)
  (:f head String)
  (:f ledger String :default "")
  (:f cli String :default "")
  (:f totalS Int64 :default 1500)
  (:f stepS Int64 :default 300)
  (:f maxSuites Int64 :default 12)
  (:f only (List String) :default (list))
  (:f mode String :default "cheap")
  (:f gate String :default "")
  (:f headDir String :default "")
  (:f baseDir String :default "")
  (:f cache String :default "")
  (:f extraEnv (List String) :default (list)))

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

fn cutAt s: String m: String -> String
  (optionOr (listHead (stringSplit s m)) s)

; (:m :do "the identity of a red: its :ev up to the trailing count fields (:lines N, lines N, > baseline), so a drifting count keeps one identity while digits in a path stay part of it; an :ev with no count field is kept whole")
fn normEv ev: String -> String
  (let [(a (cutAt ev " :lines "))
        (b (cutAt ev " lines "))
        (c (cutAt ev " > baseline"))
        (short (fn [(x String) (y String)] -> String (if (<= (stringLength x) (stringLength y)) x y)))]
    (short a (short b c)))

; (:m :do "the K of the last (+K) in an :ev, -1 when there is none")
fn evDelta ev: String -> Int64
  (let [(parts (stringSplit ev "(+"))]
    (if (< (listLength parts) 2) -1
      (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listLast parts) "") ")")) "")) -1)))

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

fn baseRowOf base: (List (Pair String String)) r: (Pair String String) -> (Option (Pair String String))
  (listHead (filter (fn [(b (Pair String String))] -> Bool (= (rowKey (pairFirst b) (pairSecond b)) (rowKey (pairFirst r) (pairSecond r)))) base))

fn worse? h: (Pair String String) b: (Pair String String) -> Bool
  (let [(hd (evDelta (pairSecond h)))
        (bd (evDelta (pairSecond b)))]
    (and (>= hd 0) (and (>= bd 0) (> hd bd))))

; (:m :do "head reds against base reds: absent from base, or present with a larger +K delta (it got worse), is a regression; present and not worse is pre-existing; pair of (regressions, preExisting)")
fn classify head: (List (Pair String String)) base: (List (Pair String String)) -> (Pair (List (Pair String String)) (List (Pair String String)))
  (let [(rows (dedupRows head))
        (isReg (fn [(r (Pair String String))] -> Bool (match (baseRowOf base r) ((none) true) ((some b) (worse? r b)))))]
    (pair (filter isReg rows) (filter (fn [(r (Pair String String))] -> Bool (not (isReg r))) rows)))

; (:m :do "one suite at head against its base run (baseExit -1 means the base was not run, -2 that the suite is absent at base): unverified for a timeout; a failure that ran no asserts (load error, 126, 127) is a regression only against a green or absent base, else unverified; a failure that ran asserts is pre-existing only when base executed asserts and failed, unverified when base failed without asserts, else a regression; fewer asserts than a green base is a regression; a pass that needed the retry is flaky")
; (:m :do "the failing assert of a suite's last line without its count: the identity two red runs share when they fail on the same assert")
fn failId why: String -> String
  (cutAt why " (after ")

fn judgeSuite h: SuiteRun baseExit: Int64 baseAsserts: Int64 baseWhy: String -> String
  (let [(baseGreen (= baseExit 0))
        (baseRealRed (and (> baseExit 0) (and (< baseExit 124) (> baseAsserts 0))))
        (noRun (or (= h.asserts 0) (or (= h.exit 126) (= h.exit 127))))]
    (cond
      ((or (= h.verdict "timeout") (= h.verdict "runaway")) "unverified")
      ((!= h.exit 0)
        (cond
          (noRun (if (or baseGreen (or (= baseExit -2) baseRealRed)) "regression" "unverified"))
          (baseRealRed (if (and (>= h.asserts baseAsserts) (= (failId h.why) (failId baseWhy))) "preExisting" "regression"))
          ((> baseExit 0) "unverified")
          (else "regression")))
      ((= h.asserts 0) "unverified")
      ((and baseGreen (< h.asserts baseAsserts)) "regression")
      (h.retried "flaky")
      (else "pass")))

fn suiteReceipt h: SuiteRun baseExit: Int64 baseAsserts: Int64 baseWhy: String -> String
  (str "(:suite " (q h.path) " :exit " (n h.exit) " :asserts " (n h.asserts) " :baseExit " (n baseExit) " :baseAsserts " (n baseAsserts) " :judged :" (judgeSuite h baseExit baseAsserts baseWhy)
       (if h.retried (str " :retried true :firstWhy " (q h.firstWhy)) "")
       (if (= h.exit 0) "" (str " :why " (q h.why))) ")")

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

; (:m :do "suites of the touched packages in run order: a touched suite itself, then the *Test.asl files in the nearest tests dir of each touched file (the touched package), then the suites whose text imports a touched module; each group sorted, no duplicates, nothing cut")
fn touchedSuites side: String files: (List String) importerPaths: (List String) -> (List String)
  (let [(own (filter isSuite? files))
        (dirs (fold (fn [(acc (List String)) (p String)] -> (List String)
                      (let [(d (testsDirOf! side p))] (if (or (stringEmpty? d) (listContains? acc d)) acc (cons d acc))))
                    (list) (filter (fn [(p String)] -> Bool (not (isSuite? p))) files)))
        (inDirs (fold (fn [(acc (List String)) (d String)] -> (List String)
                        (listAppend acc (map (fn [(f String)] -> String (str d "/" f))
                                             (filter (fn [(f String)] -> Bool (stringEndsWith? f "Test.asl")) (resultOr (dirList (str side "/" d)) (list))))))
                      (list) dirs))]
    (fold (fn [(acc (List String)) (p String)] -> (List String) (if (listContains? acc p) acc (listAppend acc (list p))))
          (list) (listAppend (listSort own) (listAppend (listSort inDirs) (listSort importerPaths)))))

fn ! gitOut! dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))) (fr/limits 120 16))

fn envName row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

; (:m :do "names that carry a credential: fr/secretName? plus *_PAT, *_KEY and *PASSWORD*, in any case")
fn secretLike? name: String -> Bool
  (let [(u (stringUpper name))]
    (or (fr/secretName? name) (or (fr/secretName? u) (or (stringEndsWith? u "_PAT") (or (stringEndsWith? u "_KEY") (stringContains? u "PASSWORD"))))))

fn keepEnv? name: String -> Bool
  (and (not (secretLike? name))
    (or (not (stringStartsWith? name "ASL_"))
      (or (= name "ASL_NATIVE_CLI_CACHE") (= name "ASL_NATIVE_TEST_CACHE"))))

; (:m :do "the caller's environment without ASL_ROOT, ASL_PRELUDE and the other ASL_ variables the launcher sets, and without secrets: the first real run set ASL_ROOT to the side checkout and 11 of 12 suites then failed ERR_UNRESOLVED_IMPORT on tools/fleet/model, because bin/asl derives its own root and prelude and the workspace tools/ packages resolve only from that")
fn ! cleanEnvWith extra: (List String) -> (List String)
  (filter (fn [(r String)] -> Bool (keepEnv? (envName r))) (listAppend (envList) extra))

fn ! cliOf side: String cli: String -> String
  (if (stringEmpty? cli) (str side "/bin/asl") cli)

fn leftS deadlineNs: Int64 stepS: Int64 -> Int64
  (let [(left (/ (- deadlineNs (monotonicNs)) 1000000000))]
    (if (< left stepS) left stepS))

; (:m :do "audit sub (consistency|gates) at side with the step bound: the failed rows and whether the audit ran (exit 0 or 1 with a receipt); gates run with suites off by default")
fn ! checkSide! side: String cli: String sub: String deadlineNs: Int64 stepS: Int64 env: (List String) -> (Result (List (Pair String String)) String)
  (let [(s (leftS deadlineNs stepS))]
    (if (<= s 0) (err "deadline")
      (let [(d (fr/runOneLimited (fr/job (list (cliOf side cli) "audit" sub) side env) (fr/limits s 64)))]
        (cond
          ((or (= d.verdict "timeout") (= d.verdict "runaway")) (err (str "timeout " sub)))
          ((not (stringContains? d.out "(:audit ")) (err (str "no receipt " sub " exit " (n d.exit))))
          (else (ok (failedRows d.out)))))))

; (:m :do "NAME=value tokens whose NAME looks like a credential lose the value: a suite's output is echoed into the receipt")
fn redactWhy s: String -> String
  (stringJoin (map (fn [(t String)] -> String
                     (let [(parts (stringSplit t "="))]
                       (if (and (> (listLength parts) 1) (secretLike? (optionOr (listHead parts) ""))) (str (optionOr (listHead parts) "") "=<redacted>") t)))
                   (stringSplit s " ")) " ")

; (:m :do "the last non-empty line of a suite's output, redacted and cut to 240 chars: the failing assert or load error a blocked merge shows")
fn whyOf out: String -> String
  (let [(ls (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines out)))
        (l (redactWhy (stringTrim (optionOr (listLast ls) ""))))]
    (optionOr (stringSlice l 0 240) l))

fn ! runSuite! side: String cli: String path: String deadlineNs: Int64 stepS: Int64 env: (List String) -> (Option SuiteRun)
  (let [(s (leftS deadlineNs stepS))]
    (if (<= s 0) (none)
      (let [(d (fr/runOneLimited (fr/job (list (cliOf side cli) "test" path) side env) (fr/limits s 64)))]
        (some (SuiteRun :path path :exit d.exit :asserts (optionOr (fr/executedOf d.out) 0) :verdict d.verdict :why (whyOf d.out))))))

; (:m :do "a suite that fails at head runs once more and the second result counts: a heavy suite under machine load flaked once on the first real run (exit 1 after 2 asserts, then 7 of 7 on its own), and only a failure that repeats blocks a merge")
fn marked second: SuiteRun first: SuiteRun -> SuiteRun
  (with second :retried true :firstWhy first.why)

fn ! runSuiteTwice! side: String cli: String path: String deadlineNs: Int64 stepS: Int64 env: (List String) -> (Option SuiteRun)
  (match (runSuite! side cli path deadlineNs stepS env)
    ((none) (none))
    ((some r) (if (and (!= r.exit 0) (= r.verdict "exit")) (match (runSuite! side cli path deadlineNs stepS env) ((some r2) (some (marked r2 r))) ((none) (some r))) (some r))))

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

; (:m :do "a commit with more than one parent: a merge of main into a unit carries git's own message, so the one-ASN-line rule exempts it")
fn ! merge? repo: String sha: String -> Bool
  (> (listLength (stringSplit (stringTrim (gitOut! repo (list "rev-list" "--parents" "-n" "1" sha)).out) " ")) 2)

fn ! structure! repo: String base: String head: String -> (List String)
  (let [(anc (gitOut! repo (list "merge-base" "--is-ancestor" base head)))
        (files (lines! repo (list "diff" "--name-only" base head)))
        (shas (lines! repo (list "log" "--format=%H" (str base ".." head))))
        (bad (filter (fn [(sha String)] -> Bool
                       (and (not (merge? repo sha)) (not (oneAsnLine? (gitOut! repo (list "log" "-1" "--format=%B" sha)).out))))
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

; (:m :do "the cache key: base sha, sub-audit and the provenance id, so an entry from another tool version, format or cli never answers")
fn cachePath dir: String sha: String sub: String id: String -> String
  (str dir "/" sha "-" sub "-" id ".asn")

fn toolVersion -> String
  "mergeCheck-2"

fn ! cliIdent o: Opts -> String
  (if (stringEmpty? o.cli) "tree" (str o.cli "@" (n (match (fileStat o.cli) ((ok st) st.mtime) ((err _) 0)))))

fn ! cacheId o: Opts -> String
  (digest8 (str (toolVersion) "|1|" (cliIdent o)))

; (:m :do "the provenance a cache entry carries: tool version, format, cli identity, base sha and sub-audit; a file whose header differs in any of them is a miss")
fn cacheHeader ver: String cli: String sha: String sub: String -> String
  (str "(:mergeCheckBase :v " (q ver) " :fmt 1 :cli " (q cli) " :sha " (q sha) " :sub " (q sub))

fn rowText r: (Pair String String) -> String
  (str "(:check :id " (pairFirst r) " :status :failed :ev " (q (pairSecond r)) ")")

; (:m :do "the base audit of one sha and sub-audit, computed once: the failed rows of an audit that ran, behind a (:mergeCheckBase) header; a missing or cut-off file is no cache")
fn ! cacheLoad! path: String hdr: String -> (Option (List (Pair String String)))
  (match (fileReadString path)
    ((err _) (none))
    ((ok t) (if (and (stringStartsWith? t hdr) (stringEndsWith? (stringTrim t) ")")) (some (failedRows t)) (none))))

fn ! cacheSave! path: String hdr: String rows: (List (Pair String String)) -> Bool
  (let [(_ (dirCreate (parentDir path)))]
    (ok? (fileWrite path (str hdr " " (stringJoin (map rowText rows) " ") ")\n"))))

fn ! headIs? dir: String sha: String -> Bool
  (and (not (stringEmpty? dir)) (= (stringTrim (gitOut! dir (list "rev-parse" "HEAD")).out) sha))

; (:m :do "a caller-supplied checkout counts only when it is at the sha and git status --porcelain is empty: tracked edits and untracked files that are not git-ignored would change what the audit sees")
fn ! cleanAt? dir: String sha: String -> Bool
  (and (headIs? dir sha) (stringEmpty? (stringTrim (gitOut! dir (list "status" "--porcelain")).out)))

fn ! cacheDirOf o: Opts -> String
  (if (stringEmpty? o.cache) (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/mergeCheck") o.cache)

; (:m :do "one audit sub of base: from the cache when present, else run in the base checkout and saved when it ran")
fn ! baseAudit! o: Opts env: (List String) save: Bool hdr: String bd: String sub: String sha: String cached: (Option (List (Pair String String))) deadlineNs: Int64 -> (Result (List (Pair String String)) String)
  (match cached
    ((some r) (ok r))
    ((none) (let [(r (checkSide! bd o.cli sub deadlineNs o.stepS env))
                  (_ (match r ((ok rows) (if save (cacheSave! (cachePath (cacheDirOf o) sha sub (cacheId o)) hdr rows) false)) ((err _) false)))]
              r)))

fn ! gateOutcome! o: Opts env: (List String) hd: String deadlineNs: Int64 -> String
  (if (stringEmpty? o.gate) ""
    (let [(s (leftS deadlineNs o.stepS))]
      (if (<= s 0) "deadline"
        (let [(d (fr/runShell! o.gate hd env (fr/limits s 64)))]
          (cond
            ((or (= d.verdict "timeout") (= d.verdict "runaway")) "timeout")
            ((= d.exit 0) "pass")
            (else (str "fail " (n d.exit))))))))

; (:m :do "cheap mode: structure, audit consistency and gates at head against base (base audits cached by sha), and the caller's --gate; full mode adds the touched suites; the caller passes --base as the merge-base of the unit and its target, so a unit behind main does not block on baseNotAncestorOfHead")
fn ! run! o: Opts -> (Pair Int64 String)
  (let [(repo (resultOr (realPath o.repo) o.repo))
        (full (= o.mode "full"))
        (deadlineNs (+ (monotonicNs) (* o.totalS 1000000000)))
        (baseSha (stringTrim (gitOut! repo (list "rev-parse" "--verify" o.base)).out))
        (headSha (stringTrim (gitOut! repo (list "rev-parse" "--verify" o.head)).out))]
    (if (or (stringEmpty? baseSha) (stringEmpty? headSha))
      (pair 2 (str "(:mergeCheck :verdict block :error " (q "base or head does not resolve") ")"))
      (let [(problems (structure! repo baseSha headSha))
            (files (lines! repo (list "diff" "--name-only" baseSha headSha)))
            (cdir (cacheDirOf o))
            (env (cleanEnvWith o.extraEnv))
            (cid (cacheId o))
            (hC (cacheHeader (toolVersion) (cliIdent o) baseSha "consistency"))
            (hG (cacheHeader (toolVersion) (cliIdent o) baseSha "gates"))
            (cC (cacheLoad! (cachePath cdir baseSha "consistency" cid) hC))
            (cG (cacheLoad! (cachePath cdir baseSha "gates" cid) hG))
            (headOwn (not (cleanAt? o.headDir headSha)))
            (dirtyRows (listAppend (if (and (not (stringEmpty? o.headDir)) headOwn) (list "headDir:refused") (list)) (if (and (not (stringEmpty? o.baseDir)) (not (cleanAt? o.baseDir baseSha))) (list "baseDir:refused") (list))))
            (needBase (or full (or (not (listOk? cC)) (not (listOk? cG)))))
            (baseOwn (and needBase (not (cleanAt? o.baseDir baseSha))))
            (tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/mergeCheck-" (n (procSelf)) "-" (n (/ (monotonicNs) 1000000))))
            (_ (dirCreate tmp))
            (hd (if headOwn (str tmp "/head") o.headDir))
            (bd (if baseOwn (str tmp "/base") o.baseDir))
            (hOk (if headOwn (addSide! repo hd headSha) true))
            (bOk (if baseOwn (addSide! repo bd baseSha) true))]
        (if (not (and hOk bOk))
          (let [(_ (if headOwn (dropSide! repo hd) false))
                (_ (if baseOwn (dropSide! repo bd) false))
                (_ (pathRemove tmp))]
            (pair 2 (str "(:mergeCheck :verdict block :error " (q "cannot check out base and head") ")")))
          (let [(hc (checkSide! hd o.cli "consistency" deadlineNs o.stepS env))
                (hg (checkSide! hd o.cli "gates" deadlineNs o.stepS env))
                (bc (if needBase (baseAudit! o env baseOwn hC bd "consistency" baseSha cC deadlineNs) (ok (optionOr cC (list)))))
                (bg (if needBase (baseAudit! o env baseOwn hG bd "gates" baseSha cG deadlineNs) (ok (optionOr cG (list)))))
                (cmp (fn [(h (Result (List (Pair String String)) String)) (b (Result (List (Pair String String)) String)) (nm String)]
                       -> (Pair (Pair (List (Pair String String)) (List (Pair String String))) (List String))
                       (match h
                         ((err e) (pair (pair (list) (list)) (list (str nm "Head:" e))))
                         ((ok hr) (match b
                                    ((err e) (pair (pair (list) (list)) (list (str nm "Base:" e))))
                                    ((ok br) (pair (classify hr br) (list))))))))
                (c1 (cmp hc bc "consistency"))
                (c2 (cmp hg bg "gates"))
                (gate (gateOutcome! o env hd deadlineNs))
                (gateRegs (if (stringStartsWith? gate "fail") (list (pair "gate" (str o.gate " " gate))) (list)))
                (gateUnv (if (or (= gate "timeout") (= gate "deadline")) (list (str "gate:" gate)) (list)))
                (regs (listAppend gateRegs (listAppend (pairFirst (pairFirst c1)) (pairFirst (pairFirst c2)))))
                (pre (listAppend (pairSecond (pairFirst c1)) (pairSecond (pairFirst c2))))
                (unv0 (listAppend dirtyRows (listAppend gateUnv (listAppend (pairSecond c1) (pairSecond c2)))))
                (mods (if full (nonEmpty (map (fn [(p String)] -> String (gg/moduleName (resultOr (fileReadString (str hd "/" p)) ""))) (filter (fn [(p String)] -> Bool (and (stringEndsWith? p ".asl") (not (isSuite? p)))) files))) (list)))
                (imp (if full (importerSuites! repo hd headSha mods) (list)))
                (allSuites (cond ((not full) (list)) ((not (listEmpty? o.only)) o.only) (else (filter (fn [(p String)] -> Bool (fileExists? (str hd "/" p))) (touchedSuites hd files imp)))))
                (suites (listTake allSuites o.maxSuites))
                (cutSuites (filter (fn [(p String)] -> Bool (not (listContains? suites p))) allSuites))
                (headRuns (map (fn [(p String)] -> (Option SuiteRun) (if (fileExists? (str hd "/" p)) (runSuiteTwice! hd o.cli p deadlineNs o.stepS env) (none))) suites))
                (ran (filter (fn [(x (Option SuiteRun))] -> Bool (match x ((some _) true) ((none) false))) headRuns))
                (hRows (map (fn [(x (Option SuiteRun))] -> SuiteRun (optionOr x (SuiteRun :path "" :exit 0 :asserts 0 :verdict ""))) ran))
                (failedFirst (listAppend (filter (fn [(r SuiteRun)] -> Bool (!= r.exit 0)) hRows) (filter (fn [(r SuiteRun)] -> Bool (= r.exit 0)) hRows)))
                (baseRuns (map (fn [(r SuiteRun)] -> (Pair SuiteRun (Option SuiteRun))
                                 (pair r (if (fileExists? (str bd "/" r.path)) (runSuite! bd o.cli r.path deadlineNs o.stepS env) (some (SuiteRun :path r.path :exit -2 :asserts 0 :verdict "absent")))))
                               failedFirst))
                (judged (map (fn [(pr (Pair SuiteRun (Option SuiteRun)))] -> (Pair SuiteRun String)
                               (let [(h (pairFirst pr))
                                     (be (match (pairSecond pr) ((some b) (if (= b.verdict "absent") -2 (if (or (= b.verdict "timeout") (= b.verdict "runaway")) -1 b.exit))) ((none) -1)))
                                     (ba (match (pairSecond pr) ((some b) b.asserts) ((none) 0)))
                                     (bw (match (pairSecond pr) ((some b) b.why) ((none) "")))]
                                 (pair h (suiteReceipt h be ba bw))))
                             baseRuns))
                (notRun (filter (fn [(p String)] -> Bool (not (listAny? (fn [(r SuiteRun)] -> Bool (= r.path p)) hRows))) (filter (fn [(p String)] -> Bool (fileExists? (str hd "/" p))) suites)))
                (has (fn [(j (Pair SuiteRun String)) (tag String)] -> Bool (stringContains? (pairSecond j) (str ":judged :" tag))))
                (suiteRegs (filter (fn [(j (Pair SuiteRun String))] -> Bool (has j "regression")) judged))
                (suiteUnv (filter (fn [(j (Pair SuiteRun String))] -> Bool (has j "unverified")) judged))
                (suiteFlaky (filter (fn [(j (Pair SuiteRun String))] -> Bool (has j "flaky")) judged))
                (unv (listAppend unv0 (listAppend (map (fn [(p String)] -> String (str "suite:" p ":cutByMaxSuites")) cutSuites)
                                       (listAppend (map (fn [(p String)] -> String (str "suite:" p ":notRun")) notRun)
                                                   (map (fn [(j (Pair SuiteRun String))] -> String (str "suite:" (pairFirst j).path ":unverified")) suiteUnv)))))
                (_ (if headOwn (dropSide! repo hd) false))
                (_ (if baseOwn (dropSide! repo bd) false))
                (_ (pathRemove tmp))
                (blocked (or (not (listEmpty? problems)) (or (not (listEmpty? regs)) (not (listEmpty? suiteRegs)))))
                (verdict (cond (blocked "block") ((not (listEmpty? unv)) "unverified") (else "pass")))
                (preRows (dedupRows pre))
                (planRows (map (fn [(r (Pair String String))] -> String (planRow (pairFirst r) (pairSecond r))) preRows))
                (added (if (stringEmpty? o.ledger) (list)
                         (let [(miss (missingRows (resultOr (fileReadString o.ledger) "") preRows))
                               (_ (if (listEmpty? miss) false (ok? (fileAppend o.ledger (stringToBytes (str (stringJoin miss "\n") "\n"))))))]
                           miss)))
                (receipt (str "(:mergeCheck :verdict " verdict " :mode " o.mode
                              " :base " (q baseSha) " :head " (q headSha)
                              " :complete " (cond ((not (listEmpty? unv)) "false") ((not full) "partial") (else "true")) " :suitesRun " (if full "true" "false")
                              " :headCheckout " (if headOwn "true" "false") " :baseCheckout " (if baseOwn "true" "false")
                              " :baseCached " (n (+ (if (listOk? cC) 1 0) (if (listOk? cG) 1 0)))
                              " :structure (" (stringJoin (map q problems) " ") ")"
                              " :regressions (" (rows2s regs) (if (or (listEmpty? regs) (listEmpty? suiteRegs)) "" " ") (stringJoin (map pairSecond suiteRegs) " ") ")"
                              " :preExisting (" (rows2s preRows) ")"
                              " :suites (" (stringJoin (map pairSecond judged) " ") ")"
                              " :flaky (" (stringJoin (map (fn [(j (Pair SuiteRun String))] -> String (q (pairFirst j).path)) suiteFlaky) " ") ")"
                              " :unverified (" (stringJoin (map q unv) " ") ")"
                              " :planRows (" (stringJoin planRows " ") ")"
                              " :ledgerAdded " (n (listLength added)) ")"))]
            (pair (cond (blocked 1) ((not (listEmpty? unv)) 3) (else 0)) receipt))))))

fn listOk? x: (Option (List (Pair String String))) -> Bool
  (match x ((some _) true) ((none) false))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(base (optionOr (flagArg args "--base") ""))
        (head (optionOr (flagArg args "--head") ""))
        (mode (optionOr (flagArg args "--mode") "cheap"))
        (num (fn [(k String) (d Int64)] -> Int64 (optionOr (stringToInt64 (optionOr (flagArg args k) "")) d)))]
    (if (or (stringEmpty? base) (or (stringEmpty? head) (not (or (= mode "cheap") (= mode "full")))))
      (do (eprintln "usage: mergeCheck --base MERGE-BASE --head REF [--mode cheap|full] [--gate CMD] [--repo DIR] [--ledger FILE] [--cli PATH] [--cache DIR] [--head-dir DIR] [--base-dir DIR] [--deadline S] [--step S] [--max-suites N] [--only SUITE,..]") (ok 2))
      (let [(r (run! (Opts :repo (optionOr (flagArg args "--repo") ".") :base base :head head :ledger (optionOr (flagArg args "--ledger") "")
                           :cli (optionOr (flagArg args "--cli") "") :totalS (num "--deadline" 1500) :stepS (num "--step" 300) :maxSuites (num "--max-suites" 12)
                           :only (nonEmpty (map stringTrim (stringSplit (optionOr (flagArg args "--only") "") ",")))
                           :mode mode :gate (optionOr (flagArg args "--gate") "") :headDir (optionOr (flagArg args "--head-dir") "")
                           :baseDir (optionOr (flagArg args "--base-dir") "") :cache (optionOr (flagArg args "--cache") ""))))]
        (do (println (pairSecond r)) (ok (pairFirst r))))))
