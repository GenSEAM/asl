(module asl-tools/coord/commitGuard
  :x [Cfg Hit Receipt defaultCfg flagVal hasFlag parseNameStatus addedLines messageHits conflictHits secretLine? secretHits ignoredHits foreignHit! gather! receipt report! run! guard! commit! main]
  :i [(asl-gates/auditForeign :a af) (asl-gates/dyck :a dyck) (asl-regex/regex :a rx) (asl-tools/fleet/run :a fr)])

; (:m :ref COMMIT-GUARD :do "the earliest consistency check, run by the own commit entry (commit!, asl run commitGuard.asl commit --msg M -- PATH...) and by in-process callers (guard!); no git hook: staged (or --range A..B) ASL and ASN balance, asl check per .asl file, foreign growth against the foreignBaseline audit foreign reads, one ASN message line, conflict markers, ignored paths and secret-looking values; one ASN receipt, exit 1 blocks, --warn never blocks")

(schema Cfg
  (:f repo String)
  (:f aslRoot String)
  (:f range String)
  (:f msg String)
  (:f hasMsg Bool)
  (:f paths (List String))
  (:f warn Bool)
  (:f perFileS Int64)
  (:f totalS Int64)
  (:f gitS Int64))

(schema Hit
  (:f rule String)
  (:f path String)
  (:f why String)
  (:f block Bool))

(schema Change
  (:f status String)
  (:f path String))

fn defaultCfg repo: String -> Cfg
  (Cfg :repo repo :aslRoot repo :range "" :msg "" :hasMsg false :paths (list) :warn false :perFileS 20 :totalS 45 :gitS 20)

fn hit rule: String path: String why: String -> Hit
  (Hit :rule rule :path path :why why :block true)

fn soft rule: String path: String why: String -> Hit
  (Hit :rule rule :path path :why why :block false)

; (:m :do "the value after a flag in an argument list, empty when the flag or its value is absent")
fn flagVal args: (List String) name: String -> String
  (match (listHead args)
    ((none) "")
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))]
        (if (= a name) (optionOr (listHead rest) "") (flagVal rest name)))))

fn hasFlag args: (List String) name: String -> Bool
  (listContains? args name)

; (:m :do "git diff --name-status lines (status TAB path) as changes; deletions are dropped, a status letter keeps its first character")
fn parseNameStatus text: String -> (List Change)
  (filter (fn [(c Change)] -> Bool (and (not (stringEmpty? c.path)) (!= c.status "D")))
    (map (fn [(l String)] -> Change
           (let [(parts (stringSplit l "\t"))]
             (Change :status (optionOr (stringSlice (optionOr (listHead parts) "") 0 1) "")
                     :path (optionOr (listGet parts 1) ""))))
         (stringLines text)))

; (:m :do "added lines of a zero-context unified diff as (path, text) pairs; the path comes from the +++ b/ header, binary and header lines are skipped")
fn addedStep acc: (Pair String (List (Pair String String))) line: String -> (Pair String (List (Pair String String)))
  (cond
    ((stringStartsWith? line "+++ b/") (pair (optionOr (stringSlice line 6 (stringLength line)) "") (pairSecond acc)))
    ((stringStartsWith? line "+++ ") (pair "" (pairSecond acc)))
    ((stringStartsWith? line "+")
     (if (stringEmpty? (pairFirst acc)) acc
       (pair (pairFirst acc) (cons (pair (pairFirst acc) (optionOr (stringSlice line 1 (stringLength line)) "")) (pairSecond acc)))))
    (else acc))

fn addedLines diff: String -> (List (Pair String String))
  (listReverse (pairSecond (fold addedStep (pair "" (list)) (stringLines diff))))

fn marker c: String -> String
  (str c c c c c c c)

; (:m :do "conflict markers: an added line that starts with seven of < or > and a space, or is exactly seven =")
fn conflictHits added: (List (Pair String String)) -> (List Hit)
  (map (fn [(a (Pair String String))] -> Hit (hit "conflictMarker" (pairFirst a) (str "added line " (esc1 (pairSecond a)))))
       (filter (fn [(a (Pair String String))] -> Bool
                 (let [(l (pairSecond a))]
                   (or (stringStartsWith? l (str (marker "<") " "))
                       (or (stringStartsWith? l (str (marker ">") " "))
                           (= l (marker "="))))))
               added))

fn esc1 s: String -> String
  (let [(c (if (> (stringLength s) 160) (str (optionOr (stringSlice s 0 160) "") "...") s))]
    (stringReplace c "\"" "'"))

fn secretPatterns -> (List (Pair (List String) String))
  (list (pair (list "sk-") "sk-[A-Za-z0-9_-]{20,}")
        (pair (list "ghp_" "gho_" "ghu_" "ghs_" "ghr_") "gh[pousr]_[A-Za-z0-9]{30,}")
        (pair (list "AKIA") "AKIA[0-9A-Z]{16}")
        (pair (list "xox") "xox[abprs]-[A-Za-z0-9-]{10,}")
        (pair (list "PRIVATE KEY") "-----BEGIN [A-Z ]*PRIVATE KEY-----")
        (pair (list "API_KEY" "SECRET" "TOKEN" "PASSWORD") "[A-Z][A-Z0-9_]*(API_KEY|SECRET|TOKEN|PASSWORD)[A-Z0-9_]*=[\"']?[A-Za-z0-9+/_.-]{20,}"))

; (:m :do "one added line looks like a secret value: a provider key shape, a private key header, or NAME_SECRET=longvalue; a cheap needle test runs first so the regex only sees rare lines; lines over 4000 characters are data, not assignments")
fn secretLine? line: String -> Bool
  (and (< (stringLength line) 4000)
    (listAny? (fn [(p (Pair (List String) String))] -> Bool
                (and (listAny? (fn [(n String)] -> Bool (stringContains? line n)) (pairFirst p))
                     (match (rx/regex-compile! (pairSecond p))
                       ((ok re) (some? (rx/regex-search! re line)))
                       ((err _) false))))
              (secretPatterns)))

fn secretHits added: (List (Pair String String)) -> (List Hit)
  (map (fn [(a (Pair String String))] -> Hit (hit "secret" (pairFirst a) "an added line looks like a credential value"))
       (filter (fn [(a (Pair String String))] -> Bool (secretLine? (pairSecond a))) (listTake added 20000)))

; (:m :do "the commit message: exactly one non-comment line, an ASN form (:c :a AREA :do WHAT ...) with balanced delimiters, no co-author or sign-off text; git-made Merge and Revert lines pass")
fn messageHits text: String -> (List Hit)
  (let [(lines (filter (fn [(l String)] -> Bool (and (not (stringEmpty? l)) (not (stringStartsWith? l "#")))) (map stringTrim (stringLines text))))
        (low (stringLower text))]
    (cond
      ((listEmpty? lines) (list (hit "message" "" "empty message")))
      ((and (= (listLength lines) 1) (or (stringStartsWith? (optionOr (listHead lines) "") "Merge ") (stringStartsWith? (optionOr (listHead lines) "") "Revert \""))) (list))
      (else
        (let [(one (optionOr (listHead lines) ""))
              (multi (if (> (listLength lines) 1) (list (hit "message" "" (str "message has " (stringFromInt64 (listLength lines)) " lines; exactly one ASN line (:c :a AREA :do WHAT) is allowed, no body and no trailers"))) (list)))
              (trailer (if (or (stringContains? low "co-authored-by") (stringContains? low "signed-off-by")) (list (hit "message" "" "co-author or sign-off trailer")) (list)))
              (shape (if (and (stringStartsWith? one "(:c ") (and (stringEndsWith? one ")") (and (stringContains? one " :a ") (stringContains? one " :do "))))
                       (list)
                       (list (hit "message" "" "the line is not (:c :a AREA :do WHAT ...)"))))
              (bal (if (and (stringStartsWith? one "(:c ") (some? (dyck/check (stringToBytes one) true))) (list (hit "message" "" "unbalanced delimiters in the ASN line")) (list)))]
          (listAppend multi (listAppend trailer (listAppend shape bal)))))))

; (:m :do "balanced delimiters of one .asl or .asn file from the bytes under src (the staged export, or the working tree in range mode); a file that cannot be read is skipped, git owns that")
fn ! balanceHit! repo: String path: String -> (Option Hit)
  (match (fileReadBytes (str repo "/" path))
    ((err _) (none))
    ((ok bs) (match (dyck/check bs (not (stringEndsWith? path ".asl")))
               ((none) (none))
               ((some r) (some (hit "balance" path (str "byte " (stringFromInt64 (pairFirst r)) " " (pairSecond r))))))))


fn ! foreignHit! repo: String base: String bt: String path: String status: String -> (Option Hit)
  (match (af/foreignLangOf! (str repo "/" path) path)
    ((err _) (none))
    ((ok lang)
      (if (stringEmpty? lang) (none)
        (match (mapGet (af/parseBaseline bt).rows path)
          ((none) (if (= status "A")
                    (some (hit "foreign" path (str "new foreign file :" lang "; the tree is ported to ASL and foreignBaseline pins every allowed file")))
                    (some (soft "foreign" path (str "foreign file :" lang " is not in the foreign baseline")))))
          ((some row)
            (match (af/measureForeign! (str repo "/" path) lang)
              ((err _) (none))
              ((ok m)
                (cond
                  ((!= lang row.lang) (some (hit "foreign" path (str "is :" lang ", the baseline pins :" row.lang))))
                  ((> (pairFirst m) row.lines) (some (hit "foreign" path (str "foreign growth :lines " (stringFromInt64 (pairFirst m)) " > baseline " (stringFromInt64 row.lines)))))
                  ((> (pairSecond m) row.py) (some (hit "foreign" path (str "embedded python " (stringFromInt64 (pairSecond m)) " > baseline " (stringFromInt64 row.py)))))
                  (else (none))))))))))


fn ignoredHits paths: (List String) ignored: String -> (List Hit)
  (map (fn [(p String)] -> Hit (hit "ignoredPath" p "a new file under an ignored path"))
       (filter (fn [(p String)] -> Bool (listContains? paths p)) (map stringTrim (stringLines ignored))))


fn nowMs! -> Int64
  (/ (nowNs) 1000000)

fn ! git! cfg: Cfg args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" cfg.repo "-c" "core.quotepath=off" "-c" "core.fsmonitor=") args) "." (fr/childEnv (list))) (fr/limits cfg.gitS 16))

; (:m :do "asl check on one .asl file with the workspace of aslRoot, bounded by secs; exit 0 is clean, a timeout or spawn failure is a warning, anything else blocks with the first error line")
fn ! checkOne! cfg: Cfg src: String path: String secs: Int64 -> (Option Hit)
  (let [(d (fr/runOneLimited (fr/job (list (str cfg.aslRoot "/bin/asl") "check" (str src "/" path)) cfg.aslRoot (fr/childEnv (list (str "ASL_ROOT=" cfg.aslRoot)))) (fr/limits secs 200)))
        (errLine (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) (stringLines d.out)))
                           (optionOr (listHead (stringLines d.out)) "")))]
    (cond
      ((= d.exit 0) (none))
      ((= d.verdict "timeout") (some (soft "check" path (str "asl check exceeded " (stringFromInt64 secs) " s"))))
      ((= d.verdict "spawnFailed") (some (soft "check" path "asl check did not start")))
      (else (some (hit "check" path (esc1 (stringReplace errLine (str src "/") "")))))))

fn ! checkLoop! cfg: Cfg src: String paths: (List String) deadline: Int64 acc: (List Hit) -> (List Hit)
  (match (listHead paths)
    ((none) (listReverse acc))
    ((some p)
      (let [(left (- deadline (nowMs!)))
            (rest (optionOr (listTail paths) (list)))]
        (if (<= left 1000)
          (listReverse (cons (soft "check" p "total check budget spent; this file and the rest were not checked") acc))
          (let [(r (checkOne! cfg src p (min cfg.perFileS (/ left 1000))))]
            (checkLoop! cfg src rest deadline (match r ((some h) (cons h acc)) ((none) acc))))))))

fn aslPath? p: String -> Bool
  (stringEndsWith? p ".asl")

fn asnPath? p: String -> Bool
  (stringEndsWith? p ".asn")

fn ! readText! path: String -> String
  (resultOr (fileReadString path) "")

fn ! somes! xs: (List String) f: (fn [(String)] -> (Option Hit)) -> (List Hit)
  (fold (fn [(acc (List Hit)) (x String)] -> (List Hit) (match (f x) ((some h) (listAppend acc (list h))) ((none) acc))) (list) xs)

fn scopeArgs cfg: Cfg -> (List String)
  (if (listEmpty? cfg.paths) (list) (cons "--" cfg.paths))

fn diffBase cfg: Cfg -> (List String)
  (if (stringEmpty? cfg.range) (list "--cached") (list cfg.range))

; (:m :do "export the index content of the changed paths into a private temp dir (git checkout-index --prefix), so every check judges the blob that will land and a partly staged file is judged by its staged half; the dir is empty when the export failed")
fn ! exportStaged! cfg: Cfg paths: (List String) -> String
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/commitGuard-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (mk (fr/runOneLimited (fr/job (list "mkdir" "-p" dir) "." (fr/childEnv (list))) (fr/limits 20 16)))]
    (if (or (!= mk.exit 0) (listEmpty? paths)) dir
      (do (git! cfg (listAppend (list "checkout-index" "-f" (str "--prefix=" dir "/") "--") paths))
          dir)))

fn ! dropExport! dir: String -> Bool
  (if (stringContains? dir "/commitGuard-")
    (= (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 20 16)).exit 0)
    false)

; (:m :do "every check over the staged change restricted to cfg.paths when given, judged on the staged blobs (or the A..B range read from the working tree at B): the hits, in rule order")
fn ! gather! cfg: Cfg -> (Pair Int64 (List Hit))
  (let [(t0 (nowMs!))
        (ns (git! cfg (listAppend (list "diff" "--name-status" "--no-renames") (listAppend (diffBase cfg) (scopeArgs cfg)))))
        (changes (if (= ns.exit 0) (parseNameStatus ns.out) (list)))
        (paths (map (fn [(c Change)] -> String c.path) changes))
        (src (if (stringEmpty? cfg.range) (exportStaged! cfg paths) cfg.repo))
        (srcPaths (filter (fn [(p String)] -> Bool (or (aslPath? p) (asnPath? p))) paths))
        (bal (somes! srcPaths (fn [(p String)] -> (Option Hit) (balanceHit! src p))))
        (balBad (map (fn [(h Hit)] -> String h.path) bal))
        (aslGood (filter (fn [(p String)] -> Bool (and (aslPath? p) (not (listContains? balBad p)))) paths))
        (chk (checkLoop! cfg src aslGood (+ t0 (* cfg.totalS 1000)) (list)))
        (bt (readText! (str cfg.repo "/scripts/audit/foreignBaseline.asn")))
        (fgn (if (stringEmpty? bt) (list)
               (fold (fn [(acc (List Hit)) (c Change)] -> (List Hit)
                       (match (foreignHit! src "" bt c.path c.status) ((some h) (listAppend acc (list h))) ((none) acc)))
                     (list) changes)))
        (df (git! cfg (listAppend (list "diff" "-U0" "--no-color" "--no-ext-diff" "--diff-filter=ACMR") (listAppend (diffBase cfg) (scopeArgs cfg)))))
        (added (if (= df.exit 0) (addedLines df.out) (list)))
        (newPaths (map (fn [(c Change)] -> String c.path) (filter (fn [(c Change)] -> Bool (= c.status "A")) changes)))
        (ig (if (listEmpty? newPaths) (list)
              (ignoredHits newPaths (git! cfg (listAppend (list "check-ignore" "--no-index" "--") (listTake newPaths 500))).out)))
        (msg (if cfg.hasMsg (messageHits cfg.msg) (list)))
        (gitBad (if (or (= ns.exit 0) (not cfg.hasMsg)) (list) (list (hit "git" "" "git diff failed; nothing was judged"))))
        (_ (if (stringEmpty? cfg.range) (dropExport! src) true))]
    (pair (listLength paths)
          (listAppend gitBad (listAppend msg (listAppend bal (listAppend chk (listAppend fgn (listAppend (conflictHits added) (listAppend ig (secretHits added))))))))))

fn rowText h: Hit -> String
  (str "(:row :rule :" h.rule " :sev " (if h.block ":block" ":warn") " :path \"" (esc2 h.path) "\" :why \"" (esc2 h.why) "\")")

fn esc2 s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "")

(schema Receipt
  (:f code Int64)
  (:f status String)
  (:f rows (List Hit))
  (:f text String))

fn receiptText cfg: Cfg files: Int64 ms: Int64 hits: (List Hit) extra: String -> String
  (let [(blocking (listAny? (fn [(h Hit)] -> Bool h.block) hits))
        (status (cond ((not blocking) (if (listEmpty? hits) ":ok" ":okWarn")) (cfg.warn ":wouldBlock") (else ":block")))]
    (str "(:commitGuard :v 1 :mode " (if (stringEmpty? cfg.range) ":staged" ":range") " :status " status " :files " (stringFromInt64 files) " :ms " (stringFromInt64 ms) extra
         " :rows (" (stringJoin (map rowText hits) " ") "))"))

fn receipt cfg: Cfg files: Int64 ms: Int64 hits: (List Hit) -> String
  (receiptText cfg files ms hits "")

; (:m :do "the pure-call API for in-process callers (conductor, Leon, flush, train): judge the staged change of repo restricted to paths, with msg checked as the commit message; code is 1 only when a block row exists and warn is off; the receipt text is the one-line ASN form; git and asl check run as bounded fleet children")
fn ! guard! repo: String aslRoot: String paths: (List String) msg: String warn: Bool -> Receipt
  (let [(base (defaultCfg repo))
        (cfg (Cfg :repo repo :aslRoot aslRoot :range "" :msg msg :hasMsg true :paths paths :warn warn :perFileS base.perFileS :totalS base.totalS :gitS base.gitS))]
    (judge! cfg))

fn ! judge! cfg: Cfg -> Receipt
  (let [(t0 (nowMs!))
        (g (gather! cfg))
        (hits (pairSecond g))
        (blocking (listAny? (fn [(h Hit)] -> Bool h.block) hits))
        (code (if (and blocking (not cfg.warn)) 1 0))]
    (Receipt :code code :status (if blocking (if cfg.warn "wouldBlock" "block") (if (listEmpty? hits) "ok" "okWarn")) :rows hits
             :text (receiptText cfg (pairFirst g) (- (nowMs!) t0) hits "")))

fn ! report! cfg: Cfg -> (Pair Int64 String)
  (let [(r (judge! cfg))]
    (pair r.code r.text))

fn ! run! cfg: Cfg -> Int64
  (let [(r (report! cfg))
        (_ (println (pairSecond r)))]
    (pairFirst r))

fn ! sha! cfg: Cfg -> String
  (stringTrim (git! cfg (list "rev-parse" "--short" "HEAD")).out)

; (:m :do "the warn-mode record: a receipt with rows is appended to repo/.asl/log/commitGuard.asn (ignored by git); a write failure is reported in the receipt, never swallowed")
fn ! record! cfg: Cfg text: String -> String
  (let [(dir (str cfg.repo "/.asl/log"))
        (mk (fr/runOneLimited (fr/job (list "mkdir" "-p" dir) "." (fr/childEnv (list))) (fr/limits 20 16)))]
    (if (!= mk.exit 0) " :recorded :no"
      (match (fileAppend (str dir "/commitGuard.asn") (stringToBytes (str text "\n")))
        ((ok _) " :recorded :yes")
        ((err e) (str " :recorded :no :recordErr \"" (esc2 e) "\"")))))

; (:m :do "stage exactly paths: present ones with add -A, vanished ones (a deletion, possibly already staged) with rm --cached; the first failing step is returned")
fn ! stage! cfg: Cfg paths: (List String) -> fr/Done
  (let [(present (filter (fn [(p String)] -> Bool (fileExists? (str cfg.repo "/" p))) paths))
        (gone (filter (fn [(p String)] -> Bool (not (fileExists? (str cfg.repo "/" p)))) paths))
        (none0 (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict ""))
        (a (if (listEmpty? present) none0 (git! cfg (listAppend (list "add" "-A" "--") present))))
        (g (if (listEmpty? gone) none0 (git! cfg (listAppend (list "rm" "-q" "-r" "--cached" "--ignore-unmatch" "--") gone))))]
    (if (!= a.exit 0) a g))

; (:m :do "the own commit entry: stage exactly paths, judge them and the message on their staged blobs, then commit only those paths; a block commits nothing and leaves HEAD as it was (the paths stay staged); --warn commits anyway and records the rows; the receipt carries :commit :done :sha S, :refused, or :failed")
fn ! commit! repo: String aslRoot: String paths: (List String) msg: String warn: Bool -> Receipt
  (let [(base (defaultCfg repo))
        (cfg (Cfg :repo repo :aslRoot aslRoot :range "" :msg msg :hasMsg true :paths paths :warn warn :perFileS base.perFileS :totalS base.totalS :gitS base.gitS))]
    (if (listEmpty? paths)
      (Receipt :code 1 :status "block" :rows (list (hit "commit" "" "no paths named; commit takes exactly the paths after --"))
               :text (receiptText cfg 0 0 (list (hit "commit" "" "no paths named; commit takes exactly the paths after --")) " :commit :refused"))
      (let [(add (stage! cfg paths))]
        (if (!= add.exit 0)
          (let [(rows (list (hit "commit" "" (esc1 (str "git add failed: " add.out)))))]
            (Receipt :code 1 :status "block" :rows rows :text (receiptText cfg 0 0 rows " :commit :refused")))
          (let [(j (judge! cfg))]
            (if (= j.code 1)
              (Receipt :code 1 :status j.status :rows j.rows :text (stringReplace j.text " :rows (" " :commit :refused :rows ("))
              (let [(c (git! cfg (listAppend (list "commit" "-q" "-m" msg "--") paths)))]
                (if (!= c.exit 0)
                  (let [(rows (listAppend j.rows (list (hit "commit" "" (esc1 (str "git commit failed: " c.out))))))]
                    (Receipt :code 1 :status "block" :rows rows :text (receiptText cfg 0 0 rows " :commit :failed")))
                  (let [(sha (sha! cfg))
                        (txt (stringReplace j.text " :rows (" (str " :commit :done :sha " sha " :rows (")))
                        (rec (if (listEmpty? j.rows) "" (record! cfg txt)))]
                    (Receipt :code 0 :status j.status :rows j.rows :text (if (stringEmpty? rec) txt (stringReplace txt " :rows (" (str rec " :rows (")))))))))))))

; (:m :do "args: commit --msg M [--warn] [--repo DIR] [--asl-root DIR] -- PATH... | --staged (default) | --range A..B, --msg-file F, --warn, --repo DIR, --asl-root DIR, --per-file-s N, --total-s N")
fn pathsAfter args: (List String) -> (List String)
  (match (listIndexOf args "--")
    ((none) (list))
    ((some i) (listDrop args (+ i 1))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(repo (let [(r (flagVal args "--repo"))] (if (stringEmpty? r) (resultOr (realPath ".") ".") r)))
        (base (defaultCfg repo))
        (root (let [(r (flagVal args "--asl-root"))] (if (stringEmpty? r) repo r)))
        (mf (flagVal args "--msg-file"))
        (mtext (if (stringEmpty? mf) (flagVal args "--msg") (resultOr (fileReadString mf) "")))
        (cfg (Cfg :repo repo :aslRoot root :range (flagVal args "--range") :msg mtext :hasMsg (or (not (stringEmpty? mf)) (hasFlag args "--msg"))
                  :paths (pathsAfter args)
                  :warn (hasFlag args "--warn")
                  :perFileS (optionOr (stringToInt64 (flagVal args "--per-file-s")) base.perFileS)
                  :totalS (optionOr (stringToInt64 (flagVal args "--total-s")) base.totalS)
                  :gitS base.gitS))]
    (if (= (optionOr (listHead args) "") "commit")
      (let [(r (commit! repo root cfg.paths mtext cfg.warn))
            (_ (println r.text))]
        (ok r.code))
      (ok (run! cfg))))
