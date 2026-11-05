(module asl-tools/coord/commitGuard
  :x [recordText! guardIndex! cfgFor! scaledSecs! configNum Cfg Hit Receipt defaultCfg flagVal hasFlag chunkRows statusOf Added exportStaged! exportHits hitBlocks? parseNameStatus addedLines messageHits conflictHits secretLine? secretHits ignoredHits foreignHit! gather! receipt report! run! guard! commit! main]
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
  (:f gitS Int64)
  (:f indexFile String :default ""))

(schema Hit
  (:f rule String)
  (:f path String)
  (:f why String)
  (:f block Bool))

(schema Change
  (:f status String)
  (:f path String))

fn defaultCfg repo: String -> Cfg
  (Cfg :repo repo :aslRoot repo :range "" :msg "" :hasMsg false :paths (list) :warn false :perFileS 30 :totalS 60 :gitS 20)

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

(schema Added
  (:f path String)
  (:f line Int64)
  (:f text String))

(schema AddState
  (:f path String)
  (:f next Int64)
  (:f rows (List Added)))

; (:m :do "the first new-file line number of a hunk header @@ -a,b +c,d @@, 0 when unreadable")
fn hunkStart line: String -> Int64
  (let [(plus (optionOr (listGet (stringSplit line " ") 2) "+0"))
        (num (optionOr (listHead (stringSplit (optionOr (stringSlice plus 1 (stringLength plus)) "0") ",")) "0"))]
    (optionOr (stringToInt64 num) 0))

; (:m :do "added lines of a zero-context unified diff with their file and new line number; the path comes from the +++ b/ header, binary and header lines are skipped")
fn addedStep st: AddState line: String -> AddState
  (cond
    ((stringStartsWith? line "+++ b/") (AddState :path (optionOr (stringSlice line 6 (stringLength line)) "") :next st.next :rows st.rows))
    ((stringStartsWith? line "+++ ") (AddState :path "" :next st.next :rows st.rows))
    ((stringStartsWith? line "@@ ") (AddState :path st.path :next (hunkStart line) :rows st.rows))
    ((stringStartsWith? line "+")
     (AddState :path st.path :next (+ st.next 1)
               :rows (if (stringEmpty? st.path) st.rows (cons (Added :path st.path :line st.next :text (optionOr (stringSlice line 1 (stringLength line)) "")) st.rows))))
    (else st))

fn addedLines diff: String -> (List Added)
  (listReverse (fold addedStep (AddState :path "" :next 0 :rows (list)) (stringLines diff)).rows)

fn marker c: String -> String
  (str c c c c c c c)

; (:m :do "conflict markers: an added line that starts with seven of < or > and a space, or is exactly seven =; the row names the line, never its content")
fn conflictHits added: (List Added) -> (List Hit)
  (map (fn [(a Added)] -> Hit (hit "conflictMarker" a.path (str "conflict marker at line " (stringFromInt64 a.line))))
       (filter (fn [(a Added)] -> Bool
                 (or (stringStartsWith? a.text (str (marker "<") " "))
                     (or (stringStartsWith? a.text (str (marker ">") " "))
                         (= a.text (marker "=")))))
               added))

fn esc1 s: String -> String
  (let [(c (if (> (stringLength s) 160) (str (optionOr (stringSlice s 0 160) "") "...") s))]
    (stringReplace c "\"" "'"))

; (:m :do "provider key shapes; sk- must not follow an alphanumeric, so task-queue... is no key")
fn secretPatterns -> (List (Pair (List String) String))
  (list (pair (list "sk-") "(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}")
        (pair (list "ghp_" "gho_" "ghu_" "ghs_" "ghr_") "gh[pousr]_[A-Za-z0-9]{30,}")
        (pair (list "AKIA") "AKIA[0-9A-Z]{16}")
        (pair (list "xox") "xox[abprs]-[A-Za-z0-9-]{10,}")
        (pair (list "PRIVATE KEY") "-----BEGIN [A-Z ]*PRIVATE KEY-----"))

fn alphaChars -> String
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

; (:m :do "a value is high entropy when it mixes letters and digits and has at least 8 distinct characters; a digit run or a word is not a secret")
fn entropic? v: String -> Bool
  (let [(cs (stringChars v))
        (distinct (fold (fn [(acc (List String)) (c String)] -> (List String) (if (listContains? acc c) acc (cons c acc))) (list) cs))]
    (and (listAny? (fn [(c String)] -> Bool (stringContains? (alphaChars) c)) cs)
         (and (listAny? (fn [(c String)] -> Bool (stringContains? "0123456789" c)) cs)
              (>= (listLength distinct) 8))))

; (:m :do "NAME_(API_KEY|SECRET|TOKEN|PASSWORD)=value where the value has no path characters (/ . ~) and is high entropy; MAX_TOKENS=1000000000000000000000 and ASL_TOKEN_FILE=/Users/x are not credentials")
fn assignSecret? line: String -> Bool
  (and (stringContains? line "=")
    (and (listAny? (fn [(n String)] -> Bool (stringContains? line n)) (list "API_KEY" "SECRET" "TOKEN" "PASSWORD"))
      (match (rx/regex-compile! "[A-Z][A-Z0-9_]*(API_KEY|SECRET|TOKEN|PASSWORD)[A-Z0-9_]*=[\"']?[A-Za-z0-9+_-]{20,}")
        ((err _) false)
        ((ok re) (match (rx/regex-search! re line)
                   ((none) false)
                   ((some m) (let [(parts (stringSplit m.text "="))
                                   (v (stringReplace (stringReplace (optionOr (listGet parts (- (listLength parts) 1)) "") "\"" "") "'" ""))]
                               (entropic? v))))))))

; (:m :do "one added line looks like a secret value; a cheap needle test runs first so the regex only sees rare lines; lines over 4000 characters are data, not assignments")
fn secretLine? line: String -> Bool
  (and (< (stringLength line) 4000)
    (or (assignSecret? line)
        (listAny? (fn [(p (Pair (List String) String))] -> Bool
                    (and (listAny? (fn [(n String)] -> Bool (stringContains? line n)) (pairFirst p))
                         (match (rx/regex-compile! (pairSecond p))
                           ((ok re) (some? (rx/regex-search! re line)))
                           ((err _) false))))
                  (secretPatterns))))

fn secretHits added: (List Added) -> (List Hit)
  (map (fn [(a Added)] -> Hit (hit "secret" a.path (str "credential-looking value at line " (stringFromInt64 a.line))))
       (filter (fn [(a Added)] -> Bool (secretLine? a.text)) (listTake added 20000)))

fn scissors? l: String -> Bool
  (and (stringStartsWith? l "# ") (stringContains? l ">8"))

fn beforeScissors lines: (List String) -> (List String)
  (match (listHead lines)
    ((none) (list))
    ((some l) (if (scissors? l) (list) (cons l (beforeScissors (optionOr (listTail lines) (list)))))))

; (:m :do "the message git generates minus noise: cut at the git commit -v scissors line, drop # comment lines, the (cherry picked from commit X) line and the This reverts commit X. line; the rest, trimmed, without blank lines")
fn cleanLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool
            (and (not (stringEmpty? l))
                 (and (not (stringStartsWith? l "#"))
                      (and (not (stringStartsWith? l "(cherry picked from commit "))
                           (not (stringStartsWith? l "This reverts commit "))))))
          (map stringTrim (beforeScissors (stringLines text))))

; (:m :do "the commit message: exactly one cleaned line, an ASN form (:c :a AREA :do WHAT ...) with balanced delimiters, no co-author or sign-off text; a Merge or Revert first line, as git writes it, is exempt from the one-line and ASN-shape rules only; the trailer and co-author check still runs")
fn messageHits text: String -> (List Hit)
  (let [(lines (cleanLines text))
        (first (optionOr (listHead lines) ""))
        (low (stringLower (stringJoin lines "\n")))]
    (cond
      ((listEmpty? lines) (list (hit "message" "" "empty message")))
      (else
        (let [(exempt (or (stringStartsWith? first "Merge ") (stringStartsWith? first "Revert \"")))
              (multi (if (and (not exempt) (> (listLength lines) 1)) (list (hit "message" "" (str "message has " (stringFromInt64 (listLength lines)) " lines; exactly one ASN line (:c :a AREA :do WHAT) is allowed, no body and no trailers"))) (list)))
              (trailer (if (or (stringContains? low "co-authored-by") (stringContains? low "signed-off-by")) (list (hit "message" "" "co-author or sign-off trailer")) (list)))
              (shape (if (or exempt (and (stringStartsWith? first "(:c ") (and (stringEndsWith? first ")") (and (stringContains? first " :a ") (stringContains? first " :do ")))))
                       (list)
                       (list (hit "message" "" "the line is not (:c :a AREA :do WHAT ...)"))))
              (bal (if (and (stringStartsWith? first "(:c ") (some? (dyck/check (stringToBytes first) true))) (list (hit "message" "" "unbalanced delimiters in the ASN line")) (list)))]
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


fn dirOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

; (:m :do "new files under an ignored path: allowed when a sibling in the same dir was already tracked (a deliberately tracked ledger or golden), else a warning; tracked is git ls-files -ci --exclude-standard, ignoring the files being added")
fn ignoredHits paths: (List String) ignored: String tracked: String -> (List Hit)
  (let [(old (filter (fn [(t String)] -> Bool (not (listContains? paths t))) (map stringTrim (stringLines tracked))))
        (dirs (map dirOf old))]
    (map (fn [(p String)] -> Hit (soft "ignoredPath" p "a new file under an ignored path with no tracked sibling"))
         (filter (fn [(p String)] -> Bool (and (listContains? paths p) (not (listContains? dirs (dirOf p)))))
                 (map stringTrim (stringLines ignored)))))


fn nowMs! -> Int64
  (/ (nowNs) 1000000)

; (:m :ref VCS-LAYER-CORE :do "every git child of the guard runs through env -u GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_NAMESPACE, so a caller's git environment never points it at another repo; the explicit indexFile is then set for that child only")
fn gitEnvArgv cfg: Cfg -> (List String)
  (listAppend (list "env" "-u" "GIT_DIR" "-u" "GIT_WORK_TREE" "-u" "GIT_INDEX_FILE" "-u" "GIT_COMMON_DIR" "-u" "GIT_OBJECT_DIRECTORY" "-u" "GIT_NAMESPACE")
              (if (stringEmpty? cfg.indexFile) (list) (list (str "GIT_INDEX_FILE=" cfg.indexFile))))

fn ! git! cfg: Cfg args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (gitEnvArgv cfg) (listAppend (list "git" "-C" cfg.repo "-c" "core.quotepath=off" "-c" "core.fsmonitor=") args)) "." (fr/childEnv (list))) (fr/limits cfg.gitS 16))

fn unchecked path: String why: String -> Hit
  (soft "unchecked" path why)

fn firstErr lines: (List String) -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) lines)) (optionOr (listHead lines) ""))

; (:m :do "one asl check over a chunk of .asl files under src with the workspace of aslRoot, bounded by secs; returns the rows: a timeout or spawn failure marks every file unchecked, ERR_NATIVE_STALE is one BLOCKING toolchain row (fail closed: a stale native CLI is not a verdict on the file) plus unchecked files, any other failure blocks per file with its first error line")
fn ! checkChunk! cfg: Cfg src: String files: (List String) secs: Int64 -> (List Hit)
  (let [(d (fr/runOneLimited (fr/job (listAppend (list (str cfg.aslRoot "/bin/asl") "check") (map (fn [(p String)] -> String (str src "/" p)) files)) cfg.aslRoot (fr/childEnv (list (str "ASL_ROOT=" cfg.aslRoot)))) (fr/limits secs 200)))]
    (chunkRows src files secs d.exit d.verdict d.out))

; (:m :ref COMMIT-GUARD-VERDICT :do "the rows of one asl check chunk from its exit code, verdict and output: pure; exit 0 counts a file clean only when the output carries its ok line, so a silent or foreign checker leaves it unchecked")
fn chunkRows src: String files: (List String) secs: Int64 exit: Int64 verdict: String out: String -> (List Hit)
  (let [(lines (stringLines out))
        (all (fn [(why String)] -> (List Hit) (map (fn [(p String)] -> Hit (unchecked p why)) files)))
        (strip (fn [(s String)] -> String (esc1 (stringReplace s (str src "/") ""))))]
    (cond
      ((= exit 0) (map (fn [(p String)] -> Hit (unchecked p "asl check gave no ok verdict for this file")) (filter (fn [(p String)] -> Bool (not (listAny? (fn [(l String)] -> Bool (stringStartsWith? l (str "ok " src "/" p ":"))) lines))) files)))
      ((= verdict "timeout") (all (str "asl check exceeded " (stringFromInt64 secs) " s")))
      ((= verdict "spawnFailed") (all "asl check did not start"))
      ((listAny? (fn [(l String)] -> Bool (stringContains? l "ERR_NATIVE_STALE")) lines)
       (cons (hit "toolchain" "" (strip (str "native CLI stale: " (firstErr lines))))
             (all "asl check could not run: native CLI stale")))
      (else
        (let [(rows (filter (fn [(h Hit)] -> Bool (not (stringEmpty? h.why)))
                      (map (fn [(p String)] -> Hit
                             (let [(mine (filter (fn [(l String)] -> Bool (stringStartsWith? l (str src "/" p ":"))) lines))]
                               (if (listEmpty? mine) (hit "check" p "") (hit "check" p (strip (firstErr mine))))))
                           files)))]
          (if (listEmpty? rows) (list (hit "check" "" (strip (firstErr lines)))) rows)))))

fn digitsPrefix s: String -> String
  (match (stringSlice s 0 1)
    ((some c) (if (stringContains? "0123456789" c) (str c (digitsPrefix (optionOr (stringSlice s 1 (stringLength s)) ""))) ""))
    ((none) ""))

; (:m :ref COMMIT-GUARD-CHECK-DEADLINE :do "an integer config value: the digits after KEY in text, none when the key or digits are absent")
fn configNum text: String key: String -> (Option Int64)
  (match (stringIndexOf text (str key " "))
    ((none) none)
    ((some i) (stringToInt64 (digitsPrefix (stringTrim (optionOr (stringSlice text (+ i (stringLength key)) (stringLength text)) ""))))))

; (:m :ref COMMIT-GUARD-CHECK-DEADLINE :do "adopted 400 ms of asl check time per KB of source, added to perFileS; a workspace tunes it with :commitGuardPerKbMs N in aslRoot/.asl.config.asn, never an env var")
fn defaultPerKbMs -> Int64
  400

fn ! perKbMs! cfg: Cfg -> Int64
  (optionOr (configNum (resultOr (fileReadString (str cfg.aslRoot "/.asl.config.asn")) "") ":commitGuardPerKbMs") (defaultPerKbMs))

; (:m :ref COMMIT-GUARD-CHECK-DEADLINE :do "the default config with perFileS and totalS overridden by :commitGuardPerFileS and :commitGuardTotalS rows of aslRoot/.asl.config.asn when present")
fn ! cfgFor! repo: String aslRoot: String -> Cfg
  (let [(d (defaultCfg repo))
        (text (resultOr (fileReadString (str aslRoot "/.asl.config.asn")) ""))]
    (Cfg :repo repo :aslRoot aslRoot :range "" :msg "" :hasMsg false :paths (list) :warn false
         :perFileS (optionOr (configNum text ":commitGuardPerFileS") d.perFileS)
         :totalS (optionOr (configNum text ":commitGuardTotalS") d.totalS)
         :gitS d.gitS))

fn ! kbOf! src: String files: (List String) -> Int64
  (/ (fold (fn [(acc Int64) (p String)] -> Int64 (+ acc (stringLength (resultOr (fileReadString (str src "/" p)) "")))) 0 files) 1024)

; (:m :ref COMMIT-GUARD-CHECK-DEADLINE :do "the check deadline of a set of files in seconds: perFileS plus the per-KB term, so a large change under load is not cut at a flat 30 s")
fn ! scaledSecs! cfg: Cfg src: String files: (List String) -> Int64
  (+ cfg.perFileS (/ (* (kbOf! src files) (perKbMs! cfg)) 1000))

fn chunksOf xs: (List String) n: Int64 -> (List (List String))
  (if (listEmpty? xs) (list) (cons (listTake xs n) (chunksOf (listDrop xs n) n)))

fn ! checkLoop! cfg: Cfg src: String chunks: (List (List String)) deadline: Int64 acc: (List Hit) -> (List Hit)
  (match (listHead chunks)
    ((none) acc)
    ((some files)
      (let [(left (- deadline (nowMs!)))
            (rest (optionOr (listTail chunks) (list)))]
        (if (<= left 1000)
          (listAppend acc (map (fn [(p String)] -> Hit (unchecked p "total check budget spent")) (listFlatMap (fn [(c (List String))] -> (List String) c) chunks)))
          (checkLoop! cfg src rest deadline (listAppend acc (checkChunk! cfg src files (min (scaledSecs! cfg src files) (/ left 1000)))))))))

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
fn ! exportStaged! cfg: Cfg paths: (List String) -> (Pair String String)
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/commitGuard-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (mk (fr/runOneLimited (fr/job (list "mkdir" "-p" dir) "." (fr/childEnv (list))) (fr/limits 20 16)))]
    (cond
      ((!= mk.exit 0) (pair dir (str "cannot create the export dir: " mk.out)))
      ((listEmpty? paths) (pair dir ""))
      (else (let [(x (git! cfg (listAppend (list "checkout-index" "-f" (str "--prefix=" dir "/") "--") paths)))]
              (if (!= x.exit 0) (pair dir (str "git checkout-index failed: " x.out))
                (if (listAny? aslPath? paths) (pair dir (exportContext! cfg dir paths)) (pair dir "")))))))

; (:m :ref COMMIT-GUARD-PKG-RESOLVE :do "the index entries of every other .asl and .asn file (manifests, the root .asl.config.asn, sibling and dependency modules), so asl check of an exported file resolves imports in its own package and workspace exactly as a plain check at that path would; a quoted path (special characters under quotepath off) is skipped, since checkout-index takes the raw name")
fn ! contextPaths! cfg: Cfg paths: (List String) -> (Result (List String) String)
  (let [(ls (git! cfg (list "ls-files" "--cached" "--" "*.asl" "*.asn")))]
    (if (!= ls.exit 0) (err (str "git ls-files failed: " (stringTrim ls.out)))
      (ok (filter (fn [(p String)] -> Bool (and (not (stringEmpty? p)) (and (not (stringStartsWith? p "\"")) (not (listContains? paths p)))))
                  (stringLines ls.out)))))

; (:m :ref COMMIT-GUARD-PKG-RESOLVE :do "export the context paths in chunks of 400 into dir beside the changed files; the first failure is the message, empty on success")
fn ! exportContext! cfg: Cfg dir: String paths: (List String) -> String
  (match (contextPaths! cfg paths)
    ((err e) e)
    ((ok ctx) (fold (fn [(acc String) (chunk (List String))] -> String
                      (if (not (stringEmpty? acc)) acc
                        (let [(x (git! cfg (listAppend (list "checkout-index" "-f" (str "--prefix=" dir "/") "--") chunk)))]
                          (if (= x.exit 0) "" (str "git checkout-index of the package context failed: " x.out)))))
                    "" (chunksOf ctx 400))))

; (:m :do "the block row for a failed export, none when the export succeeded")
fn exportHits msg: String -> (List Hit)
  (if (stringEmpty? msg) (list) (list (hit "git" "" (esc1 msg))))

fn ! dropExport! dir: String -> Bool
  (if (stringContains? dir "/commitGuard-")
    (= (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 20 16)).exit 0)
    false)

fn gitRow what: String d: fr/Done -> (List Hit)
  (if (= d.exit 0) (list) (list (hit "git" "" (esc1 (str what " failed (exit " (stringFromInt64 d.exit) "): " (stringTrim d.out))))))

; (:m :do "every check over the staged change restricted to cfg.paths when given, judged on the staged blobs (or the A..B range read from the working tree at B): the hits, in rule order; any git failure is a block row and nothing after it is judged as clean")
fn ! gather! cfg: Cfg -> (Pair Int64 (List Hit))
  (let [(t0 (nowMs!))
        (ns (git! cfg (listAppend (list "diff" "--name-status" "--no-renames") (listAppend (diffBase cfg) (scopeArgs cfg)))))
        (changes (if (= ns.exit 0) (parseNameStatus ns.out) (list)))
        (paths (map (fn [(c Change)] -> String c.path) changes))
        (ex (if (stringEmpty? cfg.range) (exportStaged! cfg paths) (pair cfg.repo "")))
        (src (pairFirst ex))
        (exRow (exportHits (pairSecond ex)))
        (srcPaths (filter (fn [(p String)] -> Bool (or (aslPath? p) (asnPath? p))) paths))
        (bal (somes! srcPaths (fn [(p String)] -> (Option Hit) (balanceHit! src p))))
        (balBad (map (fn [(h Hit)] -> String h.path) bal))
        (aslGood (filter (fn [(p String)] -> Bool (and (aslPath? p) (not (listContains? balBad p)))) paths))
        (chk (if (not (listEmpty? exRow)) (list) (checkLoop! cfg src (chunksOf aslGood 10) (+ t0 (* (+ cfg.totalS (- (scaledSecs! cfg src aslGood) cfg.perFileS)) 1000)) (list))))
        (bt (readText! (str cfg.repo "/scripts/audit/foreignBaseline.asn")))
        (fgn (if (or (stringEmpty? bt) (not (listEmpty? exRow))) (list)
               (fold (fn [(acc (List Hit)) (c Change)] -> (List Hit)
                       (match (foreignHit! src "" bt c.path c.status) ((some h) (listAppend acc (list h))) ((none) acc)))
                     (list) changes)))
        (df (git! cfg (listAppend (list "diff" "-U0" "--no-color" "--no-ext-diff" "--diff-filter=ACMR") (listAppend (diffBase cfg) (scopeArgs cfg)))))
        (added (if (= df.exit 0) (addedLines df.out) (list)))
        (newPaths (map (fn [(c Change)] -> String c.path) (filter (fn [(c Change)] -> Bool (= c.status "A")) changes)))
        (ci (if (listEmpty? newPaths) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "") (git! cfg (listAppend (list "check-ignore" "--no-index" "--") (listTake newPaths 500)))))
        (ciBad (if (> ci.exit 1) (gitRow "git check-ignore" ci) (list)))
        (tr (if (or (listEmpty? newPaths) (stringEmpty? (stringTrim ci.out))) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "") (git! cfg (list "ls-files" "-ci" "--exclude-standard"))))
        (ig (if (or (not (listEmpty? ciBad)) (listEmpty? newPaths)) (list) (ignoredHits newPaths ci.out tr.out)))
        (msg (if cfg.hasMsg (messageHits cfg.msg) (list)))
        (gitBad (listAppend (gitRow "git diff --name-status" ns) (listAppend exRow (listAppend (gitRow "git diff" df) (listAppend ciBad (gitRow "git ls-files" tr))))))
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

fn uncheckedOf hits: (List Hit) -> (List String)
  (map (fn [(h Hit)] -> String h.path) (filter (fn [(h Hit)] -> Bool (= h.rule "unchecked")) hits))

; (:m :do "block when a block row exists (wouldBlock under warn); partial when only unchecked or toolchain rows keep files from being judged; okWarn for other warnings; ok for none")
fn statusOf hits: (List Hit) warn: Bool -> String
  (cond
    ((listAny? (fn [(h Hit)] -> Bool h.block) hits) (if warn "wouldBlock" "block"))
    ((not (listEmpty? (uncheckedOf hits))) "partial")
    ((listEmpty? hits) "ok")
    (else "okWarn"))

fn receiptText cfg: Cfg files: Int64 ms: Int64 hits: (List Hit) extra: String -> String
  (str "(:commitGuard :v 1 :mode " (if (stringEmpty? cfg.range) ":staged" ":range") " :status :" (statusOf hits cfg.warn) " :files " (stringFromInt64 files) " :ms " (stringFromInt64 ms) extra
       " :unchecked (" (stringJoin (map (fn [(p String)] -> String (str "\"" (esc2 p) "\"")) (uncheckedOf hits)) " ") ")"
       " :rows (" (stringJoin (map rowText hits) " ") "))")

fn receipt cfg: Cfg files: Int64 ms: Int64 hits: (List Hit) -> String
  (receiptText cfg files ms hits "")

; (:m :do "the pure-call API for in-process callers (conductor, Leon, flush, train): judge the staged change of repo restricted to paths, with msg checked as the commit message; code is 1 only when a block row exists and warn is off; the receipt text is the one-line ASN form; git and asl check run as bounded fleet children")
fn ! guard! repo: String aslRoot: String paths: (List String) msg: String warn: Bool -> Receipt
  (guardIndex! repo aslRoot paths msg warn "")

; (:m :ref VCS-LAYER-CORE :do "guard! judging the entries of the given index file instead of the shared index (the git children get GIT_INDEX_FILE), so the vcs layer judges exactly the blobs it then commits")
fn ! guardIndex! repo: String aslRoot: String paths: (List String) msg: String warn: Bool indexFile: String -> Receipt
  (let [(base (cfgFor! repo aslRoot))
        (cfg (Cfg :repo repo :aslRoot aslRoot :range "" :msg msg :hasMsg true :paths paths :warn warn :perFileS base.perFileS :totalS base.totalS :gitS base.gitS :indexFile indexFile))]
    (judge! cfg))

fn ! judge! cfg: Cfg -> Receipt
  (let [(t0 (nowMs!))
        (g (gather! cfg))
        (hits (pairSecond g))
        (blocking (or (listAny? (fn [(h Hit)] -> Bool h.block) hits) (not (listEmpty? (uncheckedOf hits)))))
        (code (if (and blocking (not cfg.warn)) 1 0))]
    (Receipt :code code :status (statusOf hits cfg.warn) :rows hits
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
  (let [(base (cfgFor! repo aslRoot))
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

fn hitBlocks? h: Hit -> Bool
  h.block

; (:m :ref VCS-LAYER-CORE :do "the warn-mode record for in-process callers: append text to repo/.asl/log/commitGuard.asn, answering the :recorded marker of record!")
fn ! recordText! repo: String text: String -> String
  (record! (defaultCfg repo) text)
