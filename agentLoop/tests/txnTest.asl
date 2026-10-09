(module asl/agentLoop/tests/txnTest
  :x [runTests]
  :i [(asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

fn getStr kv: (List (Pair String c/KvVal)) key: String -> String
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (mt (pairSecond p) ((c/kvStr s) s) ((c/kvInt s) s)))
    (none ""))

fn getInt kv: (List (Pair String c/KvVal)) key: String -> Int64
  (optionOr (stringToInt64 (getStr kv key)) -1)

fn getBool kv: (List (Pair String c/KvVal)) key: String -> Bool
  (= (getStr kv key) "true")

fn items s: String -> (List String)
  (map (fn [f] (getStr (c/parseKv f) "p")) (c/parseForms s))

fn place s: String real: String link: String -> String
  (stringReplace (stringReplace s "@REAL@" real) "@ROOT@" link)

fn unplace s: String real: String link: String -> String
  (stringReplace (stringReplace s real "@REAL@") link "@ROOT@")

fn optStr o: (Option String) -> String
  (mt o ((some x) (str "some:" x)) (none "none"))

fn wantOpt kv: (List (Pair String c/KvVal)) -> String
  (if (getBool kv "none") "none" (str "some:" (getStr kv "want")))

fn check ok: Bool msg: String -> Bool
  (do (assert ok msg) ok)

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! writeOk path: String text: String -> Bool
  (ok? (fileWrite path text))

fn dirOf p: String -> String
  (let [parts (stringSplit p "/")]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! buildTree real: String entries: (List String) -> Bool
  (fold (fn [acc f]
          (let [kv (c/parseKv f)
                full (str real "/" (getStr kv "path"))]
            (and acc
              (if (= (getStr kv "_head") "d")
                (ok? (dirCreate full))
                (and (ok? (dirCreate (dirOf full))) (writeOk full (getStr kv "text")))))))
    true entries)

fn ! symlink target: String link: String -> Bool
  (mt (procSpawnv (list "ln" "-s" target link) none none)
    ((ok sp) (= (procWaitPid sp.pid false) (ok (some 0))))
    ((err e) (check false (str "ln -s failed to start: " e))))

fn ! checkBalance kv: (List (Pair String c/KvVal)) -> Bool
  (check (= (optStr (t/balanceAid (getStr kv "text"))) (wantOpt kv)) (str "balanceAid parity: " (getStr kv "id")))

fn ! checkRefusal kv: (List (Pair String c/KvVal)) -> Bool
  (let [content (if (getBool kv "hasContent") (some (getStr kv "content")) none)
        got (t/txnRefusal (getStr kv "stdout") (getStr kv "stderr") (getStr kv "fallback") content)]
    (check (and (= (pairFirst got) (getStr kv "err")) (= (pairSecond got) (getStr kv "msg")))
      (str "txnRefusal parity: " (getStr kv "id") " got " (pairFirst got) " / " (pairSecond got))))

fn subsOf forms: String -> (List String)
  (filter (fn [f] (stringStartsWith? f "(:")) (c/parseForms forms))

fn aidStr a: (Option t/AbortAid) -> String
  (mt a
    ((some x) (mt x ((t/abortAidOf k arr h) (str (stringFromInt64 k) "|" arr "|" h))))
    (none "none"))

fn ! checkAbort kv: (List (Pair String c/KvVal)) real: String link: String -> Bool
  (let [got (t/abortAid! link (place (getStr kv "target") real link) (t/stepsOf (subsOf (getStr kv "forms"))) (getStr kv "msg") (getStr kv "extra"))
        want (if (getBool kv "none") "none" (str (getStr kv "line") "|" (getStr kv "arrived") "|" (getStr kv "hint")))]
    (check (= (aidStr got) want) (str "abortAid parity: " (getStr kv "id") " got " (aidStr got))))

fn ! checkIntel kv: (List (Pair String c/KvVal)) -> Bool
  (let [got (t/intelSubop (if (getBool kv "hasSub") (getStr kv "sub") "") (getStr kv "form"))]
    (check (= got (getStr kv "want")) (str "intelSubop parity: " (getStr kv "id") " got " got)))

fn widenStr w: (Option t/WidenItem) -> String
  (mt w
    ((some x) (mt x ((t/widenItem a b n k) (str "some:" (stringFromInt64 a) " " (stringFromInt64 b) " " n " " k))))
    (none "none"))

fn ! checkWiden kv: (List (Pair String c/KvVal)) base: String link: String -> Bool
  (let [log (str base "/sent.log")
        cleared (writeOk log "")
        b (getStr kv "budget")
        budget (if (= b "none") none (stringToFloat64 b))
        budgetOk (or (= b "none") (some? budget))
        code (getInt kv "exit")
        out (getStr kv "stdout")
        got (t/widenToSymbol! (getStr kv "file") (getStr kv "start") (getStr kv "end") link (getInt kv "cap") budget
              (fn [form root] (if (and (writeOk log form) (= root link)) (t/aslRun code out "") (t/aslRun 1 "" "runner saw a wrong root"))))]
    (check (and cleared (and budgetOk (and (= (widenStr got) (wantOpt kv)) (= (readOr log) (getStr kv "sent")))))
      (str "widenToSymbol parity: " (getStr kv "id") " got " (widenStr got) " sent " (readOr log))))

fn probes -> (List String)
  (list "read" "push" "agent" "nope" "a" "b" "c" "d" "e" "f" "")

fn effectRow table: (List (Pair String String)) op: String -> String
  (let [r (mt (t/checkEffect table op)
            ((t/effectAllowed) ":allowed true :err \"\" :confirm false")
            ((t/effectUndeclared) ":allowed false :err \"ERR_EFFECT_UNDECLARED\" :confirm false")
            ((t/effectConfirm) ":allowed false :err \"\" :confirm true"))]
    (str "(:e :op \"" (c/escapeAsn op) "\" " r ")"))

fn ! checkEffects kv: (List (Pair String c/KvVal)) base: String -> Bool
  (let [repo (str base "/repo-" (getStr kv "id"))
        dir (str repo "/scripts/agentLoop")
        made (and (ok? (dirCreate dir)) (or (getBool kv "missing") (writeOk (str dir "/effects.asn") (getStr kv "text"))))
        loaded (t/loadEffects! repo)]
    (mt loaded
      ((ok table)
        (let [tab (c/joinAll (map (fn [p] (str "(:t :op \"" (c/escapeAsn (pairFirst p)) "\" :class \"" (pairSecond p) "\")")) table))
              rows (c/joinAll (map (fn [op] (effectRow table op)) (probes)))]
          (check (and made (and (= tab (getStr kv "table")) (= rows (getStr kv "want"))))
            (str "effects parity: " (getStr kv "id") " table " tab))))
      ((err e) (check false (str "loadEffects failed: " e)))))

fn ! checkInside kv: (List (Pair String c/KvVal)) real: String link: String -> Bool
  (let [got (t/insideRoot (place (getStr kv "path") real link) link)]
    (check (= got (getBool kv "want")) (str "insideRoot parity: " (getStr kv "path"))))

fn pad4 k: Int64 -> String
  (let [s (stringFromInt64 k)]
    (str (stringRepeat "0" (max 0 (- 4 (stringLength s)))) s))

fn ! nextId path: String -> String
  (let [k (+ (optionOr (stringToInt64 (readOr path)) 0) 1)]
    (if (writeOk path (stringFromInt64 k)) (str "rid" (pad4 k)) (str "rid-unwritable-" path)))

fn ! checkTxn kv: (List (Pair String c/KvVal)) base: String real: String link: String effects: (List (Pair String String)) -> Bool
  (let [sentLog (str base "/sent.log")
        snapLog (str base "/snap.log")
        idPath (str base "/ids")
        cleared (and (writeOk sentLog "") (and (writeOk snapLog "") (writeOk idPath "0")))
        code (getInt kv "exit")
        out (getStr kv "stdout")
        errText (getStr kv "stderr")
        r (t/execTxn! (place (getStr kv "form") real link) (map (fn [o] (place o real link)) (items (getStr kv "owns"))) link effects
            (fn [] (nextId idPath))
            (fn [p] (writeOk snapLog (str (readOr snapLog) p "\n")))
            (fn [form root] (if (and (writeOk sentLog form) (= root link)) (t/aslRun code out errText) (t/aslRun 1 "" "runner saw a wrong root"))))
        got (unplace (t/serReceipt r) real link)
        snaps (map (fn [s] (str s "\n")) (items (getStr kv "snaps")))
        id (getStr kv "id")]
    (and (check cleared (str "txn logs reset: " id))
      (and (check (= got (getStr kv "want")) (str "execTxn receipt parity: " id " got " got))
        (and (check (= (unplace (readOr sentLog) real link) (getStr kv "sent")) (str "execTxn sent form parity: " id " got " (readOr sentLog)))
          (check (= (unplace (readOr snapLog) real link) (c/joinAll snaps)) (str "execTxn snapshots parity: " id " got " (readOr snapLog)))))))

fn ! checkSnapshotFailure base: String real: String link: String effects: (List (Pair String String)) -> Bool
  (let [sentLog (str base "/sent.log")
        cleared (writeOk sentLog "")
        r (t/execTxn! "(:txn :owns (\"a.txt\") (:write :file \"a.txt\" :content \"x\"))" (list "a.txt") link effects
            (fn [] "ridSnap")
            (fn [p] (and (= p "a.txt") (not (fileExists? (str real "/" p)))))
            (fn [form root] (if (writeOk sentLog form) (t/aslRun 0 "(:txn :status :ok)" "") (t/aslRun 1 "" "sent log unwritable"))))
        want "(receipt (id \"ridSnap\") (op \"txn\") (status \"rejected\") (error \"ERR_SNAPSHOT\") (message \"'a.txt' could not be snapshotted before the write; nothing was sent\"))"]
    (and (check cleared "snapshot case log reset")
      (and (check (= (t/serReceipt r) want) (str "ERR_SNAPSHOT receipt: " (t/serReceipt r)))
        (check (= (readOr sentLog) "") (str "nothing sent after a failed snapshot: " (readOr sentLog))))))

fn ! runCase f: String base: String real: String link: String effects: (List (Pair String String)) -> Int64
  (let [kv (c/parseKv f)
        h (getStr kv "_head")]
    (cond
      ((= h "balance") (if (checkBalance kv) 1 0))
      ((= h "refusal") (if (checkRefusal kv) 1 0))
      ((= h "abort") (if (checkAbort kv real link) 1 0))
      ((= h "intel") (if (checkIntel kv) 1 0))
      ((= h "widen") (if (checkWiden kv base link) 1 0))
      ((= h "effects") (if (checkEffects kv base) 1 0))
      ((= h "inside") (if (checkInside kv real link) 1 0))
      ((= h "txn") (if (checkTxn kv base real link effects) 1 0))
      (else 0)))

fn headIs f: String h: String -> Bool
  (= (getStr (c/parseKv f) "_head") h)

fn ! runTests -> Bool
  (let [forms (c/parseForms (readOr "asl/agentLoop/tests/txnFixtures.asn"))
        header (c/parseKv (optionOr (listHead forms) ""))
        declared (getInt header "cases")
        tmp (resultOr (realPath "/tmp") "/tmp")
        base (str tmp "/aslTxnTest." (stringFromInt64 (procSelf)))
        real (str base "/real")
        link (str base "/link")
        tree (optionOr (listHead (filter (fn [f] (headIs f "tree")) forms)) "")
        built (and (ok? (dirCreate real)) (and (buildTree real (c/parseForms (c/sliceOf tree 1 (stringLength tree)))) (symlink real link)))
        baseEffects (optionOr (listHead (filter (fn [f] (and (headIs f "effects") (= (getStr (c/parseKv f) "id") "base"))) forms)) "")
        effects (t/parseEffects (getStr (c/parseKv baseEffects) "text"))
        passed (fold (fn [acc f] (+ acc (runCase f base real link effects))) 0 forms)
        cases (listLength (filter (fn [f] (not (or (headIs f "tree") (headIs f "txnFixture")))) forms))
        snapFailed (checkSnapshotFailure base real link effects)
        removed (ok? (pathRemove base))]
    (assert (= (getStr header "base") "a33969ab") "fixture recorded at the pinned base a33969ab")
    (assert built (str "fixture tree and symlinked root built under " base))
    (assert (> (listLength effects) 30) "base effects registry parsed")
    (assert (= cases declared) (str "fixture declares " (stringFromInt64 declared) " cases, holds " (stringFromInt64 cases)))
    (assert (= passed cases) (str (stringFromInt64 passed) " of " (stringFromInt64 cases) " cases passed"))
    (assert snapFailed "ERR_SNAPSHOT case passed")
    (assert removed (str "fixture tree removed: " base))
    true)
