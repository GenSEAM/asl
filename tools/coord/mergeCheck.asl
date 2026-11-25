(module asl-tools/coord/mergeCheck
  :x [gateWord cachePaths auditArgv failedRows quotedEnd unquote normEv evDelta rowKey classify effectiveBase! targetTips! isAncestor? untouchedPre judgeSuite SuiteRun Opts cleanEnvWith keepEnv? secretLike? redactWhy whyOf failId toolVersion cacheHeader cacheLoad! cacheSave! cachePath pruneEntries! entryName? toolIdIn! freshToolId! auditClosureId! moduleIndex! resolveIn headIdent! headHeader headPath headReceipt! headLoad! baseOf! cleanAt? suiteReceipt planRow planId missingRows oneAsnLine? conflictMarkers? ledgerGrows grownLedgers! LRow structure! touchedSuites checkSide! gitOut! run! main]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/coord/gateGuard :a gg) (asl-tools/coord/gateWiden :a gw) (asl-text/string :a ts)])

; (:m :ref MERGE-CHECK :do "asl run asl/tools/coord/mergeCheck.asl --base REF --head REF [--repo DIR] [--ledger FILE] [--cli PATH] [--deadline S] [--step S] [--max-suites N] [--only SUITE,..] [--reuse-head]: one merge-time audit that blocks only on what the change introduces; structure of base..head, asl audit consistency and gates (no suites) on both sides compared by check id and normalised :ev, then the suites of the touched packages at head against base; pre-existing reds never block, they print as plan rows and --ledger appends the missing ones; steps the deadline cut off are listed unverified, never passed; exit 0 pass, 1 block, 2 bad invocation")

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
  (:f extraEnv (List String) :default (list))
  (:f target String :default "")
  (:f reuseHead Bool :default false)
  (:f nativeCache String :default ""))

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

; (:m :do "the text of a quoted string up to its closing quote, an escaped quote does not close it: the parts are the text split on quotes")
fn quotedEnd parts: (List String) acc: String -> String
  (match (listHead parts)
    ((none) acc)
    ((some x) (let [(cur (str acc x))]
                (if (and (stringEndsWith? x "\\") (not (stringEndsWith? x "\\\\")))
                  (quotedEnd (optionOr (listTail parts) (list)) (str cur "\""))
                  cur))))

fn unquote s: String -> String
  (stringReplace (stringReplace s "\\\"" "\"") "\\\\" "\\")

; (:m :do "the failed (:check :id X ... :ev \"..\") rows of an audit receipt as (id, ev) pairs, in order; a passed check, the header line and a receipt with no checks give nothing")
fn failedRows text: String -> (List (Pair String String))
  (let [(parts (optionOr (listTail (stringSplit text "(:check :id ")) (list)))]
    (map (fn [(p String)] -> (Pair String String)
           (let [(id (optionOr (listHead (stringSplit p " ")) ""))
                 (evParts (stringSplit p " :ev \""))
                 (ev (if (< (listLength evParts) 2) "" (unquote (quotedEnd (stringSplit (stringJoin (optionOr (listTail evParts) (list)) " :ev \"") "\"") ""))))]
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
      ((or (= h.verdict "timeout") (or (= h.verdict "runaway") (= h.verdict "wallOverBound"))) "unverified")
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

; (:m :ref VCS-AUDIT-LOWS-F1 :do "merge-time audits run with the vcsDirect scan cache off: consistency gets --no-cache")
; (:m :ref MERGECHECK-CLI-AUDITS-OWN-TREE :do "the audited tree is passed as --root, so a CLI whose own tree is another checkout (the conductor's devRepo/bin/asl) still audits the side under test")
fn auditArgv cli: String sub: String side: String -> (List String)
  (if (= sub "consistency") (list cli "audit" sub "--no-cache" "--root" side) (list cli "audit" sub "--root" side))

; (:m :do "audit sub (consistency|gates) at side with the step bound: the failed rows and whether the audit ran (exit 0 or 1 with a receipt); gates run with suites off by default")
fn ! checkSide! side: String cli: String sub: String deadlineNs: Int64 stepS: Int64 env: (List String) -> (Result (List (Pair String String)) String)
  (resultMap (checkSideAll! side cli sub deadlineNs stepS env) (fn [(p (Pair (List (Pair String String)) Bool))] -> (List (Pair String String)) (pairFirst p)))

; (:m :ref TRAIN-INVARIANT-DEDUP :do "checkSide! plus whether the audit itself passed (exit 0 and a :passed receipt): a not-computed check fails the audit yet is no failed row, so an empty row list alone is not a green audit")
fn ! checkSideAll! side: String cli: String sub: String deadlineNs: Int64 stepS: Int64 env: (List String) -> (Result (Pair (List (Pair String String)) Bool) String)
  (let [(s (leftS deadlineNs stepS))]
    (if (<= s 0) (err "deadline")
      (let [(d (fr/runOneLimited (fr/job (auditArgv (cliOf side cli) sub side) side env) (fr/limits s 64)))]
        (cond
          ((or (= d.verdict "timeout") (= d.verdict "runaway")) (err (str "timeout " sub)))
          ((not (stringContains? d.out "(:audit ")) (err (str "no receipt " sub " exit " (n d.exit))))
          (else (ok (pair (failedRows d.out) (and (= d.exit 0) (stringContains? d.out (str "(:audit :sub " sub " :status :passed"))))))))))

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
    (ts/stringClipUtf8 l 240))

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

; (:m :ref VCS-AUDIT-LOWS-F1 :do "paths under .asl/cache in the diff: a committed cache could hide sites from audits that read it")
fn cachePaths files: (List String) -> (List String)
  (filter (fn [(p String)] -> Bool (or (stringStartsWith? p ".asl/cache/") (stringContains? p "/.asl/cache/"))) files)

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
                    (if (listEmpty? (cachePaths files)) "" (str "cachePathInDiff " (stringJoin (listTake (cachePaths files) 5) ",")))
                    (if (listEmpty? bad) "" (str "notOneAsnLine " (stringJoin (map (fn [(s String)] -> String (optionOr (stringSlice s 0 9) s)) bad) ",")))
                    (if (conflictMarkers? diff.out) "conflictMarkers" "")
                    (if (listEmpty? (grownLedgers! repo base head)) "" (str "ledgerGrew " (stringJoin (grownLedgers! repo base head) ","))))))

(schema LRow (:f path String) (:f cause String) (:f digest String) (:f whole String))

; (:m :do "shrink-only ledgers: rows are parsed as forms by their opening marker wherever they sit, a row is keyed by suite path, cause and digest, a head row not in base blocks the merge unless it is a real move: a base row with the same cause and digest is gone at head, its old path no longer exists at head and the new path did not exist at base, each base row moves once; skipAllowed.asn rows are keyed whole and never move, its creating commit is the one-time seed pinned by its own suite, any other ledger created with rows blocks")
fn ledgerPaths -> (List String)
  (list ".asl/mem/skipAllowed.asn" ".asl/mem/knownRed.asn")

fn firstLine s: String -> String
  (stringTrim (optionOr (listHead (stringSplit s "\n")) ""))

fn quotedAfter s: String key: String -> String
  (match (stringIndexOf s key)
    ((none) "")
    ((some i)
     (let [(rest (optionOr (stringSlice s (+ i (stringLength key)) (stringLength s)) ""))]
       (optionOr (listHead (stringSplit rest "\"")) ""))))

fn rowOf marker: String piece: String -> LRow
  (let [(line (firstLine piece))
        (path (optionOr (listGet (stringSplit piece "\"") 1) ""))]
    (if (= marker "(:suite ")
      (LRow :path path :cause (quotedAfter line ":cause \"") :digest (quotedAfter line ":failedAssertDigest \"") :whole (str marker line))
      (LRow :path path :cause "" :digest "" :whole (str marker line))))

fn ledgerRows text: String -> (List LRow)
  (listFlatMap (fn [(m String)] -> (List LRow) (map (fn [(p String)] -> LRow (rowOf m p)) (optionOr (listTail (stringSplit text m)) (list))))
               (list "(:suite " "(:skip :suite " "(:flaky "))

fn ledgerRowKey r: LRow -> String
  (if (stringEmpty? r.cause) r.whole (str r.path "|" r.cause "|" r.digest))

fn findIdx pred: (fn [LRow] -> Bool) rows: (List LRow) -> (Option Int64)
  (match (listHead (filter (fn [(e (Pair Int64 LRow))] -> Bool (pred (pairSecond e))) (enumerate rows)))
    ((some e) (some (pairFirst e)))
    ((none) (none)))

fn removeKey rows: (List LRow) k: String -> (List LRow)
  (match (findIdx (fn [(r LRow)] -> Bool (= (ledgerRowKey r) k)) rows)
    ((none) rows)
    ((some i) (listAppend (listTake rows i) (optionOr (listTail (listDrop rows i)) (list)))))

fn ledgerMoveOk g: LRow n: LRow oldGone: (fn [String] -> Bool) newFresh: (fn [String] -> Bool) -> Bool
  (and (not (stringEmpty? n.cause)) (and (= n.cause g.cause) (and (= n.digest g.digest) (and (oldGone g.path) (newFresh n.path)))))

fn ledgerGrows path: String base: (Option String) head: String oldGone: (fn [String] -> Bool) newFresh: (fn [String] -> Bool) -> Bool
  (if (and (none? base) (stringEndsWith? path "skipAllowed.asn"))
    false
    (let [(split (fold (fn [(acc (Pair (List LRow) (List LRow))) (h LRow)] -> (Pair (List LRow) (List LRow))
                         (if (listAny? (fn [(b LRow)] -> Bool (= (ledgerRowKey b) (ledgerRowKey h))) (pairSecond acc))
                           (pair (pairFirst acc) (removeKey (pairSecond acc) (ledgerRowKey h)))
                           (pair (listAppend (pairFirst acc) (list h)) (pairSecond acc))))
                       (pair (list) (match base ((some t) (ledgerRows t)) ((none) (list))))
                       (ledgerRows head)))
          (settled (fold (fn [(acc (Pair Int64 (List LRow))) (n LRow)] -> (Pair Int64 (List LRow))
                           (match (findIdx (fn [(g LRow)] -> Bool (ledgerMoveOk g n oldGone newFresh)) (pairSecond acc))
                             ((some i) (pair (pairFirst acc) (listAppend (listTake (pairSecond acc) i) (optionOr (listTail (listDrop (pairSecond acc) i)) (list)))))
                             ((none) (pair (+ (pairFirst acc) 1) (pairSecond acc)))))
                         (pair 0 (pairSecond split))
                         (pairFirst split)))]
      (> (pairFirst settled) 0)))

fn ! showAt! repo: String rev: String path: String -> (Option String)
  (let [(d (gitOut! repo (list "show" (str rev ":" path))))]
    (if (= d.exit 0) (some d.out) (none)))

fn ! existsAt! repo: String rev: String path: String -> Bool
  (= (gitOut! repo (list "cat-file" "-e" (str rev ":" path))).exit 0)

fn ! grownLedgers! repo: String base: String head: String -> (List String)
  (filter (fn [(p String)] -> Bool (match (showAt! repo head p)
                                      ((none) false)
                                      ((some h) (ledgerGrows p (showAt! repo base p) h (fn [(q String)] -> Bool (not (existsAt! repo head q))) (fn [(q String)] -> Bool (not (existsAt! repo base q)))))))
          (ledgerPaths))

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
  "mergeCheck-3"

; (:m :ref TRAIN-INVARIANT-DEDUP :do "the native CLI cache the bin/asl wrapper reads its head pointers from: Opts.nativeCache, else ASL_NATIVE_CLI_CACHE, else HOME/.asl/run/nativeCli, as the wrapper resolves it")
fn ! nativeCacheOf o: Opts -> String
  (if (stringEmpty? o.nativeCache) (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")) o.nativeCache)

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

; (:m :ref TRAIN-INVARIANT-DEDUP :do "the wrapper's own suspect test by builtins: a head dir whose deps list is unreadable or empty, or names a source missing under the root or newer than the pointer, is rebuilt before the next call, so its name is not the tool that call runs")
fn ! headStale? root: String dir: String pointer: String -> Bool
  (match (fileReadString (str dir "/deps"))
    ((err _) true)
    ((ok text)
     (let [(paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines text)))]
       (match (fileStat pointer)
         ((err _) true)
         ((ok stamp) (or (listEmpty? paths)
                         (listAny? (fn [(p String)] -> Bool (match (fileStat (str root "/" p)) ((err _) true) ((ok st) (> st.mtimeNs stamp.mtimeNs)))) paths)))))))

; (:m :ref TRAIN-INVARIANT-DEDUP :do "the content id of the tool an audit runs: tree with no --cli (each side runs its own bin/asl, fixed by the sha); a native dir's bin is its cli-<source digest> dir name; a bin/asl wrapper is the dir its head pointer names while no source it was built from is newer than the pointer, else unknown, and a wrapper with no pointer is unknown; any other file is the sha256 of its bytes. Path and mtime never enter it, so a deploy that leaves the sources as they were keeps the id; an unknown id (empty) caches and reuses nothing")
fn ! toolIdIn! cache: String cli: String -> String
  (if (stringEmpty? cli) "tree"
    (let [(real (resultOr (realPath cli) cli))
          (dir (parentDir real))
          (root (parentDir dir))
          (pointer (str cache "/head" (stringReplace root "/" "_")))]
      (cond
        ((and (= (baseName real) "bin") (stringStartsWith? (baseName dir) "cli-")) (str "cli:" (baseName dir)))
        ((fileExists? pointer)
          (let [(nd (stringTrim (resultOr (fileReadString pointer) "")))]
            (if (and (not (stringEmpty? nd)) (and (fileExists? (str nd "/bin")) (not (headStale? root nd pointer)))) (str "cli:" (baseName nd)) "")))
        ((or (fileExists? (str root "/asl/host")) (stringContains? (resultOr (fileReadString real) "") "nativeCli")) "")
        (else (match (fileReadBytes real) ((ok b) (str "bytes:" (bytesSha256 b))) ((err _) ""))))))

fn ! toolIdOf! o: Opts -> String
  (toolIdIn! (nativeCacheOf o) o.cli)

; (:m :ref TRAIN-INVARIANT-DEDUP :do "the tool id at the start of a run: a wrapper whose head pointer is stale (a landed merge touched its sources) is refreshed once with --fresh version, which verifies or rebuilds under the build lock as the first audit would, and the id is read again; still unknown is unknown. Without it no run on a node after a merge could key anything")
fn ! freshToolId! o: Opts env: (List String) deadlineNs: Int64 -> String
  (let [(t (toolIdOf! o))]
    (if (or (not (stringEmpty? t)) (stringEmpty? o.cli)) t
      (let [(s (leftS deadlineNs o.stepS))]
        (if (<= s 0) ""
          (let [(_ (fr/runOneLimited (fr/job (list o.cli "--fresh" "version") o.repo env) (fr/limits s 64)))]
            (toolIdOf! o))))))

fn cacheId tool: String -> String
  (digest8 (str (toolVersion) "|2|" tool))
; (:m :ref MERGECHECK-BASE-BY-AUDIT-CLOSURE :do "the base audit is keyed by what the audit is, not by the CLI build that runs it: the content digests, at the head sha, of every module auditMain.asl imports transitively (each import resolved against the tree's own (module NAME) headers: exact name, else a bare name in the importer's package, else the one module that ends in /name), of the files the audit reads or spawns (rules, knownRed, baselines, bin/asl-core) and of the toolchain source roots that run it (the set nativeTest fingerprints); an import that does not resolve to exactly one module makes the id empty, so nothing is cached or reused. A CLI rebuild that leaves all of them alone keeps the key")
fn auditEntry -> String
  "asl-gates/auditMain"

fn auditDataPaths -> (List String)
  (list "asl/grammar/rules.asn" ".asl/rules.asn" ".asl/mem/knownRed.asn" "asl/packages/asl-gates/baselines" "bin/asl-core")

fn auditToolchainPaths -> (List String)
  (list "asl/packages/asl-compiler/src" "asl/packages/asl-checker/src" "asl/packages/asl-codegen/src" "asl/packages/asl-ir/src"
        "asl/packages/asl-parser/src" "asl/packages/asl-syntax/src/core" "asl/packages/asl-target-llvm/src"
        "asl/prelude/prelude.asl" "asl/prelude/native" "asl/tools/nativeTest.asl" "asl/packages/asl-cli/src/command.asl")

; (:m :do "one row per tracked module header of the tree: its declared name and path, from one git grep")
fn ! moduleIndex! repo: String sha: String -> (Option (List (Pair String String)))
  (let [(d (gitOut! repo (list "grep" "-I" "-E" "^\\(module [^ )]+" sha "--" "asl/*.asl")))
        (k (+ (stringLength sha) 1))]
    (if (>= d.exit 2) (none)
     (if (!= d.exit 0) (some (list))
      (some (nonEmptyPairs (map (fn [(l String)] -> (Pair String String)
                            (let [(row (optionOr (stringSlice l k (stringLength l)) ""))
                                  (at (optionOr (stringIndexOf row ":") 0))
                                  (path (optionOr (stringSlice row 0 at) ""))
                                  (text (optionOr (stringSlice row (+ at 1) (stringLength row)) ""))
                                  (name (optionOr (listHead (stringSplit (stringTrim (optionOr (listGet (stringSplit text "(module ") 1) "")) " ")) ""))]
                              (pair name path)))
                          (stringLines d.out)))))))

fn nonEmptyPairs rows: (List (Pair String String)) -> (List (Pair String String))
  (filter (fn [(r (Pair String String))] -> Bool (and (not (stringEmpty? (pairFirst r))) (not (stringEmpty? (pairSecond r))))) rows)

fn packageOf path: String -> String
  (let [(parts (stringSplit path "/"))]
    (if (and (> (listLength parts) 3) (= (optionOr (listGet parts 1) "") "packages")) (stringJoin (listTake parts 3) "/") (optionOr (listHead (stringSplit path "/src/")) path)))

; (:m :do "every path an import may name, empty when none: a module declared with that name, the file the name spells (asl/<name>.asl, asl/packages/<pkg>/src/<rest>.asl), and for a bare name the modules named .../bare or files .../bare.asl, the importer's package alone when it has one; tests are left out, and all candidates enter the closure so the resolver's pick is always among them")
fn resolveIn ix: (List (Pair String String)) importer: String imp: String -> (List String)
  (let [(live (filter (fn [(r (Pair String String))] -> Bool (not (stringContains? (pairSecond r) "/tests/"))) ix))
        (slash (stringContains? imp "/"))
        (first (optionOr (listHead (stringSplit imp "/")) imp))
        (rest (stringJoin (listDrop (stringSplit imp "/") 1) "/"))
        (spelled (list (str "asl/" imp ".asl") (str "asl/packages/" first "/src/" rest ".asl")))
        (hit (fn [(r (Pair String String))] -> Bool
               (if slash
                 (or (= (pairFirst r) imp) (listContains? spelled (pairSecond r)))
                 (or (stringEndsWith? (pairFirst r) (str "/" imp)) (or (= (pairFirst r) imp) (stringEndsWith? (pairSecond r) (str "/" imp ".asl")))))))
        (all (filter hit live))
        (own (filter (fn [(r (Pair String String))] -> Bool (= (packageOf (pairSecond r)) (packageOf importer))) all))]
    (map (fn [(r (Pair String String))] -> String (pairSecond r)) (if (and (not slash) (not (listEmpty? own))) own all)))

; (:m :do "the closure rows path=digest, or none when an import resolves to nothing, a file is unreadable or the walk exceeds its fuel; fail closed. A todo row is (importer, import), or (empty, path) for a resolved path")
fn ! closureWalk! repo: String sha: String ix: (List (Pair String String)) todo: (List (Pair String String)) seen: (List String) acc: (List String) fuel: Int64 -> (Option (List String))
  (match (listHead todo)
    ((none) (some acc))
    ((some job)
      (let [(rest (optionOr (listTail todo) (list)))]
        (cond
          ((<= fuel 0) (none))
          ((stringEmpty? (pairFirst job))
            (let [(path (pairSecond job))]
              (if (listContains? seen path) (closureWalk! repo sha ix rest seen acc (- fuel 1))
                (match (showAt! repo sha path)
                  ((none) (none))
                  ((some t) (closureWalk! repo sha ix (listAppend rest (map (fn [(i String)] -> (Pair String String) (pair path i)) (gw/importsOf t))) (cons path seen) (cons (str path "=" (digest16 t)) acc) (- fuel 1)))))))
          (else (let [(cands (resolveIn ix (pairFirst job) (pairSecond job)))]
                  (if (listEmpty? cands) (none)
                    (closureWalk! repo sha ix (listAppend (map (fn [(p String)] -> (Pair String String) (pair "" p)) cands) rest) seen acc (- fuel 1)))))))))

fn ! pathId! repo: String sha: String p: String -> String
  (str p "=" (stringTrim (gitOut! repo (list "rev-parse" "--verify" "-q" (str sha ":" p))).out))

fn ! auditClosureId! repo: String sha: String -> String
  (match (moduleIndex! repo sha)
    ((none) "")
    ((some ix) (auditClosureOf! repo sha ix)))

fn ! auditClosureOf! repo: String sha: String ix: (List (Pair String String)) -> String
  (let [(entry (pairSecond (optionOr (listHead (filter (fn [(r (Pair String String))] -> Bool (= (pairFirst r) (auditEntry))) ix)) (pair "" ""))))]
    (match (if (stringEmpty? entry) (some (list)) (closureWalk! repo sha ix (list (pair "" entry)) (list) (list) 600))
      ((none) "")
      ((some mods) (str "audit:" (digest16 (stringJoin (listAppend (listSort mods) (map (fn [(p String)] -> String (pathId! repo sha p)) (listAppend (auditDataPaths) (auditToolchainPaths)))) "\n"))))))


; (:m :do "the provenance a cache entry carries: tool version, format, tool content id, base sha and sub-audit; a file whose header differs in any of them is a miss")
fn cacheHeader ver: String cli: String sha: String sub: String -> String
  (str "(:mergeCheckBase :v " (q ver) " :fmt 2 :cli " (q cli) " :sha " (q sha) " :sub " (q sub))

; (:m :ref TRAIN-INVARIANT-DEDUP :do "the identity of one head audit, every input its result reads besides the files: tool id, the effective base, the head's tree (the train audits a --no-ff merge commit whose tree can equal the unit head's), the merge base of the head with main (vcsDirect compares the allowlist with it) and the repo's remote names (workspaceIsolation); empty, so nothing is saved or reused, when the tool is unknown or a field cannot be read")
fn headHeader ver: String tool: String base: String tree: String mainBase: String remotes: String sub: String -> String
  (str "(:mergeCheckHead :v " (q ver) " :fmt 1 :tool " (q tool) " :base " (q base) " :tree " (q tree) " :mainBase " (q mainBase) " :remotes " (q remotes) " :sub " (q sub))

fn ! headIdent! repo: String tool: String base: String head: String sub: String -> String
  (let [(t (gitOut! repo (list "rev-parse" "--verify" (str head "^{tree}"))))
        (mb (gitOut! repo (list "merge-base" head "main")))
        (rm (gitOut! repo (list "remote")))
        (tree (stringTrim t.out))]
    (if (or (stringEmpty? tool) (or (stringEmpty? base) (or (!= t.exit 0) (or (stringEmpty? tree) (or (!= rm.exit 0) (= mb.verdict "timeout"))))))
      ""
      (headHeader (toolVersion) tool base tree (str (n mb.exit) ":" (stringTrim mb.out)) (stringJoin (nonEmpty (map stringTrim (stringLines rm.out))) ",") sub)))

fn digest16 s: String -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes s)) 0 16) "")

fn headPath dir: String hdr: String -> String
  (str dir "/head-" (digest16 hdr) ".asn")

fn rowText r: (Pair String String) -> String
  (str "(:check :id " (pairFirst r) " :status :failed :ev " (q (pairSecond r)) ")")

fn rowsBody rows: (List (Pair String String)) -> String
  (stringJoin (map rowText rows) " ")

; (:m :ref TRAIN-INVARIANT-DEDUP :do "an entry is sealed: its header, then :rows N :sum \"S\" over the rendered rows, then the rows and a closing paren")
fn sealed hdr: String rows: (List (Pair String String)) -> String
  (str hdr " :rows " (n (listLength rows)) " :sum " (q (digest16 (rowsBody rows))) " " (rowsBody rows) ")\n")

; (:m :do "the audit rows of one entry, computed once: the failed rows of an audit that ran, behind its header; a missing file, another header, a cut-off file or rows whose count or digest differ from the seal (a torn write could drop a red) is no cache")
fn ! cacheLoad! path: String hdr: String -> (Option (List (Pair String String)))
  (match (fileReadString path)
    ((err _) (none))
    ((ok t) (let [(pre (str hdr " :rows "))]
              (if (not (and (stringStartsWith? t pre) (stringEndsWith? (stringTrim t) ")"))) (none)
                (let [(rest (optionOr (stringSlice t (stringLength pre) (stringLength t)) ""))
                      (count (optionOr (stringToInt64 (optionOr (listHead (stringSplit rest " ")) "")) -1))
                      (sum (quotedAfter rest " :sum \""))
                      (rows (failedRows t))]
                  (if (and (= count (listLength rows)) (and (not (stringEmpty? sum)) (= sum (digest16 (rowsBody rows))))) (some rows) (none)))))))

; (:m :ref TRAIN-INVARIANT-DEDUP-L3 :do "entries are kept 14 days (adopted): a base or head entry is rewritten by every check that misses it, so one older than that serves no base or tree still in flight")
fn entryMaxAgeNs -> Int64
  1209600000000000

; (:m :ref TRAIN-INVARIANT-DEDUP-L3 :do "a file this cache writes, by name: a head entry head-*.asn, a base entry <sha>-consistency|gates-<id>.asn, or a temp file of either; any other name in a caller's --cache dir is not ours")
fn entryName? f: String -> Bool
  (let [(own (or (stringStartsWith? f "head-") (or (stringContains? f "-consistency-") (stringContains? f "-gates-"))))]
    (and own (or (stringEndsWith? f ".asn") (stringEndsWith? f ".tmp"))))

; (:m :ref TRAIN-INVARIANT-DEDUP-L3 :do "on every write the entries of that one directory older than entryMaxAgeNs are removed; nothing outside it, no subdirectory, no name entryName? does not claim; a racing reader that loses an entry reruns its audit")
fn ! pruneEntries! dir: String nowNs0: Int64 -> Int64
  (fold (fn [(acc Int64) (f String)] -> Int64
          (let [(p (str dir "/" f))]
            (match (fileStat p)
              ((err _) acc)
              ((ok st) (if (and (entryName? f) (and (not st.isDir) (> (- nowNs0 st.mtimeNs) (entryMaxAgeNs))))
                         (if (ok? (pathRemove p)) (+ acc 1) acc)
                         acc)))))
        0 (resultOr (dirList dir) (list)))

; (:m :do "written whole to a temp file and renamed, so a reader never sees half an entry; then the directory's expired entries are pruned")
fn ! cacheSave! path: String hdr: String rows: (List (Pair String String)) -> Bool
  (let [(_ (dirCreate (parentDir path)))
        (tmp (str path "." (n (procSelf)) "." (n (monotonicNs)) ".tmp"))
        (saved (if (ok? (fileWrite tmp (sealed hdr rows)))
                 (if (ok? (pathRename tmp path)) true (let [(_ (pathRemove tmp))] false))
                 false))
        (_ (pruneEntries! (parentDir path) (nowNs)))]
    saved)

fn ! headIs? dir: String sha: String -> Bool
  (and (not (stringEmpty? dir)) (= (stringTrim (gitOut! dir (list "rev-parse" "HEAD")).out) sha))

; (:m :do "a caller-supplied checkout counts only when it is at the sha and git status --porcelain is empty: tracked edits and untracked files that are not git-ignored would change what the audit sees")
fn ! cleanAt? dir: String sha: String -> Bool
  (and (headIs? dir sha) (stringEmpty? (stringTrim (gitOut! dir (list "status" "--porcelain")).out)))

fn ! cacheDirOf o: Opts -> String
  (if (stringEmpty? o.cache) (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/mergeCheck") o.cache)

; (:m :do "one audit sub of base: from the cache when present, else run in the base checkout and saved when it ran with a known tool id that is still the same after the run (a rebuild in between would have run another tool)")
fn ! baseAudit! o: Opts env: (List String) save: Bool tool: String cid: String hdr: String bd: String sub: String sha: String cached: (Option (List (Pair String String))) deadlineNs: Int64 -> (Result (List (Pair String String)) String)
  (match cached
    ((some r) (ok r))
    ((none) (let [(r (checkSide! bd o.cli sub deadlineNs o.stepS env))
                  (_ (match r ((ok rows) (if (and save (and (not (stringEmpty? cid)) (and (not (stringEmpty? tool)) (= (toolIdOf! o) tool)))) (cacheSave! (cachePath (cacheDirOf o) sha sub cid) hdr rows) false)) ((err _) false)))]
              r)))

; (:m :ref TRAIN-INVARIANT-DEDUP :do "the head consistency audit once per merged tree: a reuse run (--reuse-head) takes the sealed rows a run of the same tool saved for the same identity (headIdent!) when present; otherwise the audit runs, and rows of an audit that ran under a known tool id, unchanged after the run, are saved under that identity; a red row stays a red row, nothing else is cached; pair of (rows or why, reused)")
fn passedWord p: Bool -> String
  (if p " :passed true" " :passed false")

; (:m :ref TRAIN-INVARIANT-DEDUP :do "a head receipt: its rows and whether the whole audit passed, the flag sealed in the header so a reader cannot take a failed audit for a passed one")
fn ! headLoad! path: String ident: String -> (Option (Pair (List (Pair String String)) Bool))
  (match (cacheLoad! path (str ident (passedWord true)))
    ((some r) (some (pair r true)))
    ((none) (match (cacheLoad! path (str ident (passedWord false))) ((some r) (some (pair r false))) ((none) (none)))))

fn ! headAudit! o: Opts env: (List String) tool: String ident: String hd: String deadlineNs: Int64 -> (Pair (Result (List (Pair String String)) String) Bool)
  (let [(path (headPath (cacheDirOf o) ident))
        (hit (if (and o.reuseHead (not (stringEmpty? ident))) (headLoad! path ident) (none)))]
    (match hit
      ((some rp) (pair (ok (pairFirst rp)) true))
      ((none) (let [(r (checkSideAll! hd o.cli "consistency" deadlineNs o.stepS env))
                    (_ (match r ((ok rp) (if (and (not (stringEmpty? ident)) (= (toolIdOf! o) tool)) (cacheSave! path (str ident (passedWord (pairSecond rp))) (pairFirst rp)) false)) ((err _) false)))]
                (pair (resultMap r (fn [(rp (Pair (List (Pair String String)) Bool))] -> (List (Pair String String)) (pairFirst rp))) false)))))

; (:m :ref MERGECHECK-BASE-ATTRIB :do "the base a check of head against the requested base uses: the effective base when head carries the target brought in, else the requested sha; empty when either does not resolve")
fn ! baseOf! repo: String baseReq: String headSha: String target: String -> String
  (if (or (stringEmpty? baseReq) (stringEmpty? headSha)) baseReq
    (let [(e (effectiveBase! repo baseReq headSha (targetTips! repo target)))] (if (stringEmpty? e) baseReq e)))

; (:m :ref TRAIN-INVARIANT-DEDUP :do "for a caller that runs the same audit outside mergeCheck (the train's audit item): the head consistency rows, and whether that audit passed, a mergeCheck run of this cli saved for exactly this base and head, by the identity a check of head against base would use; none when the base or head does not resolve, the tool is unknown, or the receipt is missing or garbled")
fn ! headReceipt! repo: String base: String head: String cli: String cache: String nativeCache: String target: String -> (Option (Pair (List (Pair String String)) Bool))
  (let [(o (Opts :repo repo :base base :head head :cli cli :cache cache :nativeCache nativeCache :target target))
        (baseReq (stringTrim (gitOut! repo (list "rev-parse" "--verify" base)).out))
        (headSha (stringTrim (gitOut! repo (list "rev-parse" "--verify" head)).out))
        (baseSha (baseOf! repo baseReq headSha target))
        (tool (toolIdOf! o))
        (ident (if (or (stringEmpty? tool) (or (stringEmpty? baseSha) (stringEmpty? headSha))) "" (headIdent! repo tool baseSha headSha "consistency")))]
    (if (stringEmpty? ident) (none) (headLoad! (headPath (cacheDirOf o) ident) ident)))

fn ! gateOutcome! o: Opts env: (List String) hd: String deadlineNs: Int64 -> String
  (if (stringEmpty? o.gate) ""
    (let [(s (leftS deadlineNs o.stepS))]
      (if (<= s 0) "deadline"
        (gateWord (fr/runShell! o.gate hd env (fr/limits s 64))))))

; (:m :ref MERGECHECK-BASE-ATTRIB :do "the tree the unit is really merged onto: when head carries merges on its first-parent line whose second parent descends from the given base, that parent (the newest one) is main brought in, and its growth is not the unit's; the effective base is that parent, else the given base; the base cache is keyed by it so an older sha never answers")
fn ! isAncestor? repo: String a: String b: String -> Bool
  (= (gitOut! repo (list "merge-base" "--is-ancestor" a b)).exit 0)

; (:m :ref MERGECHECK-BASE-ATTRIB :do "the line the unit is merged onto: the explicit --target ref when given, else the local dev and main branch tips of the repo the check runs in; unresolved names are dropped, so no tip means no effective base")
fn ! targetTips! repo: String target: String -> (List String)
  (nonEmpty (map (fn [(r String)] -> String (stringTrim (gitOut! repo (list "rev-parse" "--verify" "-q" (str r "^{commit}"))).out))
                 (if (stringEmpty? target) (list "refs/heads/dev" "refs/heads/main") (list target))))

; (:m :ref MERGECHECK-BASE-ATTRIB :do "a merged-in second parent counts as the target brought in only when it descends from the base and is an ancestor of (or equal to) a target tip; a side branch a unit merges itself is on no target line and never becomes the base")
fn ! effectiveBase! repo: String base: String head: String tips: (List String) -> String
  (let [(rows (lines! repo (list "rev-list" "--first-parent" "--merges" "--parents" (str base ".." head))))
        (parents (listFlatMap (fn [(r String)] -> (List String) (listDrop (nonEmpty (stringSplit r " ")) 2)) rows))
        (onTarget (fn [(p String)] -> Bool (listAny? (fn [(t String)] -> Bool (isAncestor? repo p t)) tips)))
        (cands (filter (fn [(p String)] -> Bool (and (!= p base) (and (isAncestor? repo base p) (onTarget p)))) parents))
        (pick (fn [(best String) (c String)] -> String (if (or (stringEmpty? best) (isAncestor? repo best c)) c best)))]
    (fold pick "" cands))

; (:m :ref MERGECHECK-BASE-ATTRIB :do "a per-path foreignGrowth red whose path the unit's diff does not touch is pre-existing, never a regression; rows without a path (totals) and every other check stay as classified; pair of (regressions, preExisting)")
fn untouchedPre regs: (List (Pair String String)) files: (List String) -> (Pair (List (Pair String String)) (List (Pair String String)))
  (let [(un (fn [(r (Pair String String))] -> Bool
              (and (= (pairFirst r) "foreignGrowth")
                   (and (stringContains? (pairSecond r) " :lines ") (not (listContains? files (cutAt (pairSecond r) " :lines ")))))))]
    (pair (filter (fn [(r (Pair String String))] -> Bool (not (un r))) regs) (filter un regs)))

; (:m :ref GATEADMIT-FIX :do "the word for one finished --gate run: timeout and runaway and wallOverBound (refused unlaunched, exit 126) are unverified words, never fail")
fn gateWord d: fr/Done -> String
  (cond
    ((or (= d.verdict "timeout") (= d.verdict "runaway")) "timeout")
    ((= d.verdict "wallOverBound") "wallOverBound")
    ((= d.exit 0) "pass")
    (else (str "fail " (n d.exit))))

; (:m :do "cheap mode: structure, audit consistency and gates at head against base (base audits cached by sha), and the caller's --gate; full mode adds the touched suites; the caller passes --base as the merge-base of the unit and its target, so a unit behind main does not block on baseNotAncestorOfHead")
fn ! run! o: Opts -> (Pair Int64 String)
  (let [(repo (resultOr (realPath o.repo) o.repo))
        (full (= o.mode "full"))
        (deadlineNs (+ (monotonicNs) (* o.totalS 1000000000)))
        (baseReq (stringTrim (gitOut! repo (list "rev-parse" "--verify" o.base)).out))
        (headSha (stringTrim (gitOut! repo (list "rev-parse" "--verify" o.head)).out))
        (baseSha (baseOf! repo baseReq headSha o.target))]
    (if (or (stringEmpty? baseSha) (stringEmpty? headSha))
      (pair 2 (str "(:mergeCheck :verdict block :error " (q "base or head does not resolve") ")"))
      (let [(problems (structure! repo baseSha headSha))
            (files (lines! repo (list "diff" "--name-only" baseSha headSha)))
            (cdir (cacheDirOf o))
            (env (cleanEnvWith o.extraEnv))
            (tool (freshToolId! o env deadlineNs))
            (closure (if (stringEmpty? tool) "" (auditClosureId! repo headSha)))
            (cid (if (stringEmpty? closure) "" (cacheId closure)))
            (hC (cacheHeader (toolVersion) closure baseSha "consistency"))
            (hG (cacheHeader (toolVersion) closure baseSha "gates"))
            (cC (if (stringEmpty? closure) (none) (cacheLoad! (cachePath cdir baseSha "consistency" cid) hC)))
            (cG (if (stringEmpty? closure) (none) (cacheLoad! (cachePath cdir baseSha "gates" cid) hG)))
            (ident (if (stringEmpty? tool) "" (headIdent! repo tool baseSha headSha "consistency")))
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
          (let [(hcR (headAudit! o env tool ident hd deadlineNs))
                (hc (pairFirst hcR))
                (hg (checkSide! hd o.cli "gates" deadlineNs o.stepS env))
                (bc (if needBase (baseAudit! o env baseOwn tool cid hC bd "consistency" baseSha cC deadlineNs) (ok (optionOr cC (list)))))
                (bg (if needBase (baseAudit! o env baseOwn tool cid hG bd "gates" baseSha cG deadlineNs) (ok (optionOr cG (list)))))
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
                (gateUnv (if (or (= gate "timeout") (or (= gate "deadline") (= gate "wallOverBound"))) (list (str "gate:" gate)) (list)))
                (split (untouchedPre (listAppend (pairFirst (pairFirst c1)) (pairFirst (pairFirst c2))) files))
                (regs (listAppend gateRegs (pairFirst split)))
                (pre (listAppend (pairSecond split) (listAppend (pairSecond (pairFirst c1)) (pairSecond (pairFirst c2)))))
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
                              " :base " (q baseSha) (if (= baseSha baseReq) "" (str " :requestedBase " (q baseReq))) " :head " (q headSha)
                              " :complete " (cond ((not (listEmpty? unv)) "false") ((not full) "partial") (else "true")) " :suitesRun " (if full "true" "false")
                              " :headCheckout " (if headOwn "true" "false") " :baseCheckout " (if baseOwn "true" "false")
                              " :baseCached " (n (+ (if (listOk? cC) 1 0) (if (listOk? cG) 1 0))) " :headReused " (if (pairSecond hcR) "1" "0")
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
      (do (eprintln "usage: mergeCheck --base MERGE-BASE --head REF [--mode cheap|full] [--target REF] [--gate CMD] [--repo DIR] [--ledger FILE] [--cli PATH] [--cache DIR] [--head-dir DIR] [--base-dir DIR] [--reuse-head] [--deadline S] [--step S] [--max-suites N] [--only SUITE,..]") (ok 2))
      (let [(r (run! (Opts :repo (optionOr (flagArg args "--repo") ".") :base base :head head :target (optionOr (flagArg args "--target") "") :ledger (optionOr (flagArg args "--ledger") "")
                           :cli (optionOr (flagArg args "--cli") "") :totalS (num "--deadline" 1500) :stepS (num "--step" 300) :maxSuites (num "--max-suites" 12)
                           :only (nonEmpty (map stringTrim (stringSplit (optionOr (flagArg args "--only") "") ",")))
                           :mode mode :gate (optionOr (flagArg args "--gate") "") :headDir (optionOr (flagArg args "--head-dir") "")
                           :baseDir (optionOr (flagArg args "--base-dir") "") :cache (optionOr (flagArg args "--cache") "") :reuseHead (listContains? args "--reuse-head"))))]
        (do (println (pairSecond r)) (ok (pairFirst r))))))
