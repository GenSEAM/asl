(module asl-forms/gate :x [GateEnv GateOutcome RunOut DelimDiag Repair RepairRun gateOp? readOnlyOp? linesFailed? runGate! checkStep testStep fixStep doctorStep! auditStep languageOf syntaxLang readText foreignSyntax! validateStaged! buildOverlay! runHost aslDelimiterDiag aslDelimiterError aslRepair repairAsn pySplitLines pyExt runArgv! whichTool stagedWritable!] :i [(asl-forms/kernel :a k) (asl-forms/edit :a e)])


(schema GateEnv (:f root String) (:f rootDir String) (:f binDir String) (:f host String) (:f staged (List (Pair String String))))

(schema GateOutcome (:f lines (List String)) (:f errCount Int64) (:f stage (Option (Pair String String))))

(schema RunOut (:f code Int64) (:f out String) (:f errText String) (:f timedOut Bool) (:f failure String))

(schema PumpState (:f outOpen Bool) (:f errOpen Bool) (:f out String) (:f errText String) (:f timedOut Bool) (:f failure String))

(schema DelimDiag (:f kind String) (:f byte Int64) (:f expected String) (:f msg String))

(schema Tok (:f kind String) (:f start Int64) (:f end Int64) (:f byte Int64))

(schema Suffix (:f ok Bool) (:f len Int64) (:f stack (List Int64)))

(schema Cand (:f cost Int64) (:f action String) (:f byte Int64) (:f text String) (:f cutFrom Int64) (:f cutTo Int64) (:f idx Int64))

(schema Repair (:f action String) (:f byte Int64) (:f text String) (:f rank (List String)))

(schema RepairRun (:f status String) (:f text String) (:f repair (Option Repair)) (:f candidates (List Int64)) (:f basis String) (:f rejected (List Repair)))

(schema ScanState (:f stack (List Int64)) (:f len Int64) (:f ok Bool) (:f cands (List Cand)) (:f prevEnd Int64))

(schema HostRun (:f code Int64) (:f out String) (:f errText String) (:f source String))


fn sub s: String a: Int64 b: Int64 -> String
  (let [(n (stringLength s))
        (hi (min n (max 0 b)))
        (lo (min hi (max 0 a)))]
    (optionOr (stringSlice s lo hi) ""))

fn q s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn outcome lines: (List String) errs: Int64 -> GateOutcome
  (GateOutcome :lines lines :errCount errs :stage (none))

fn okLine line: String -> GateOutcome
  (outcome (list line) 0)

fn badLine line: String -> GateOutcome
  (outcome (list line) 1)

fn head id: Int64 op: String -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"" op "\"")

fn rejectLine id: Int64 op: String code: String tail: String -> GateOutcome
  (badLine (str (head id op) " :status \"rejected\" :error-code \"" code "\"" tail ")"))

fn msgTail msg: String -> String
  (str " :message " (q msg))

fn digit? c: Int64 -> Bool
  (and (>= c 48) (<= c 57))

fn wordByte? c: Int64 -> Bool
  (or (digit? c) (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (= c 95) (>= c 128))

fn spaceByte? c: Int64 -> Bool
  (or (= c 32) (and (>= c 9) (<= c 13)))

fn pyTrunc s: String n: Int64 -> String
  (let [(b (stringToBytes s))
        (len (stringLength s))]
    (sub s 0 (cutAt b len 0 n)))

fn cutAt b: Bytes len: Int64 i: Int64 left: Int64 -> Int64
  (cond
    ((>= i len) len)
    ((= (& (bytesGet b i) 192) 128) (cutAt b len (+ i 1) left))
    ((= left 0) i)
    (else (cutAt b len (+ i 1) (- left 1))))

fn codePoints s: String -> Int64
  (let [(b (stringToBytes s))]
    (countLeads b (stringLength s) 0 0))

fn countLeads b: Bytes n: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (countLeads b n (+ i 1) (if (= (& (bytesGet b i) 192) 128) acc (+ acc 1))))

fn pyTail s: String n: Int64 -> String
  (let [(total (codePoints s))]
    (if (<= total n) s (sub s (cutAt (stringToBytes s) (stringLength s) 0 (- total n)) (stringLength s))))

fn lineBreakLen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (bytesGet b i))]
    (cond
      ((or (= c 10) (= c 11) (= c 12) (= c 28) (= c 29) (= c 30)) 1)
      ((= c 13) (if (and (< (+ i 1) n) (= (bytesGet b (+ i 1)) 10)) 2 1))
      ((and (= c 194) (< (+ i 1) n) (= (bytesGet b (+ i 1)) 133)) 2)
      ((and (= c 226) (< (+ i 2) n) (= (bytesGet b (+ i 1)) 128) (or (= (bytesGet b (+ i 2)) 168) (= (bytesGet b (+ i 2)) 169))) 3)
      (else 0)))

fn splitScan s: String b: Bytes n: Int64 i: Int64 start: Int64 keep: Bool acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< start n) (cons (sub s start n) acc) acc))
    (let [(k (lineBreakLen b n i))]
      (if (= k 0)
        (splitScan s b n (+ i 1) start keep acc)
        (splitScan s b n (+ i k) (+ i k) keep (cons (sub s start (if keep (+ i k) i)) acc)))))

fn pySplitLines s: String keep: Bool -> (List String)
  (splitScan s (stringToBytes s) (stringLength s) 0 0 keep (list))

fn strippedLines s: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (pySplitLines s false)))

fn firstWhere xs: (List String) p: (fn [String] -> Bool) -> String
  (optionOr (listHead (filter p xs)) "")

fn lastSlashIn s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (k/charAt s i) "/") i) (else (lastSlashIn s (- i 1))))

fn lastDotIn s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (k/charAt s i) ".") i) (else (lastDotIn s (- i 1))))

fn nonDotBefore? s: String i: Int64 stop: Int64 -> Bool
  (cond ((>= i stop) false) ((!= (k/charAt s i) ".") true) (else (nonDotBefore? s (+ i 1) stop)))

fn pyExt path: String -> String
  (let [(n (stringLength path))
        (slash (lastSlashIn path (- n 1)))
        (dot (lastDotIn path (- n 1)))]
    (if (and (> dot slash) (nonDotBefore? path (+ slash 1) dot)) (sub path dot n) ""))

fn envOr! name: String fallback: String -> String
  (let [(v (optionOr (envGet name) ""))] (if (stringEmpty? v) fallback v))

fn ! executable? p: String -> Bool
  (mt (fileStat p) ((ok st) (and st.isFile (!= (& st.mode 73) 0))) ((err _) false))

fn whichTool! name: String -> String
  (firstWhere (map (fn [(d String)] -> String (k/joinPath d name)) (filter (fn [(d String)] -> Bool (not (stringEmpty? d))) (stringSplit (envOr! "PATH" "") ":")))
              executable?)

fn tmpRoot! -> String
  (let [(t (envOr! "TMPDIR" "/tmp"))] (if (and (stringEndsWith? t "/") (> (stringLength t) 1)) (sub t 0 (- (stringLength t) 1)) t))

fn tempName! prefix: String suffix: String -> String
  (str (tmpRoot!) "/" prefix (stringFromInt64 (procSelf)) "x" (stringFromInt64 (monotonicNs)) suffix)

fn makeTempDir! prefix: String -> (Result String String)
  (let [(d (tempName! prefix ""))]
    (if (fileExists? d)
      (makeTempDir! prefix)
      (mt (dirCreate d) ((ok _) (ok (resultOr (realPath d) d))) ((err e) (err e)))))

fn makeTempFile! prefix: String suffix: String content: String -> (Result String String)
  (let [(p (tempName! prefix suffix))]
    (mt (fileCreateExclusive p content) ((ok _) (ok p)) ((err e) (if (fileExists? p) (makeTempFile! prefix suffix content) (err e)))))

fn envKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (sub row 0 i)) ((none) row))

fn withEnv! name: String value: String -> (List String)
  (listAppend (filter (fn [(r String)] -> Bool (!= (envKey r) name)) (envList)) (list (str name "=" value)))

fn pumpFd! fd: Int64 isOut: Bool st: PumpState -> PumpState
  (mt (fdRead fd 65536)
    ((ok chunk)
      (cond
        ((and (stringEmpty? chunk) isOut) (do (fdClose fd) (with st :outOpen false :timedOut false :failure "")))
        ((stringEmpty? chunk) (do (fdClose fd) (with st :errOpen false :timedOut false :failure "")))
        (isOut (with st :outOpen true :out (str st.out chunk) :timedOut false :failure ""))
        (else (with st :errOpen true :errText (str st.errText chunk) :timedOut false :failure ""))))
    ((err e)
      (cond
        ((= e "wouldBlock") st)
        (isOut (do (fdClose fd) (with st :outOpen false :timedOut false :failure "")))
        (else (do (fdClose fd) (with st :errOpen false :timedOut false :failure ""))))))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn pumpUntil! sp: SpawnedProc st: PumpState deadlineNs: Int64 -> PumpState
  (if (not (or st.outOpen st.errOpen))
    st
    (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
      (if (<= leftMs 0)
        (with st :timedOut true :failure "")
        (mt (fdPoll (listAppend (if st.outOpen (list (pair sp.stdout 1)) (list)) (if st.errOpen (list (pair sp.stderr 1)) (list))) leftMs)
          ((err e) (with st :timedOut false :failure e))
          ((ok ready)
            (let [(s1 (if (and st.outOpen (ready? ready sp.stdout)) (pumpFd! sp.stdout true st) st))
                  (s2 (if (and s1.errOpen (ready? ready sp.stderr)) (pumpFd! sp.stderr false s1) s1))]
              (pumpUntil! sp s2 deadlineNs)))))))

fn closeLeft! sp: SpawnedProc st: PumpState -> Bool
  (do (if st.outOpen (fdClose sp.stdout) (ok ())) (if st.errOpen (fdClose sp.stderr) (ok ())) true)

fn afterTerm! sp: SpawnedProc st: PumpState graceMs: Int64 -> PumpState
  (if (<= graceMs 0)
    (do (procKill (- 0 sp.pid) "SIGKILL") st)
    (do (procKill (- 0 sp.pid) "SIGTERM")
        (let [(s2 (pumpUntil! sp (with st :timedOut false :failure "") (+ (monotonicNs) (* graceMs 1000000))))]
          (do (if s2.timedOut (procKill (- 0 sp.pid) "SIGKILL") (ok ()))
              (PumpState :outOpen s2.outOpen :errOpen s2.errOpen :out s2.out :errText s2.errText :timedOut true :failure s2.failure)))))

fn runArgv! argv: (List String) cwd: (Option String) env: (Option (List String)) timeoutMs: Int64 graceMs: Int64 -> RunOut
  (mt (procSpawnv argv cwd env)
    ((err e) (RunOut :code -1 :out "" :errText "" :timedOut false :failure e))
    ((ok sp)
      (let [(closed (fdClose sp.stdin))
            (st0 (PumpState :outOpen true :errOpen true :out "" :errText "" :timedOut false :failure ""))
            (st1 (pumpUntil! sp st0 (+ (monotonicNs) (* timeoutMs 1000000))))
            (st2 (if st1.timedOut (afterTerm! sp st1 graceMs) st1))
            (done (closeLeft! sp st2))]
        (mt (procWaitPid sp.pid false)
          ((ok code) (RunOut :code (optionOr code -1) :out st2.out :errText st2.errText :timedOut st2.timedOut :failure st2.failure))
          ((err e) (RunOut :code -1 :out st2.out :errText st2.errText :timedOut st2.timedOut :failure e))))))

fn osErrorText kind: String path: String -> String
  (cond
    ((= kind "notFound") (str "[Errno 2] No such file or directory: '" path "'"))
    ((= kind "permission") (str "[Errno 13] Permission denied: '" path "'"))
    (else (str "[Errno ?] " kind ": '" path "'")))

fn pyListRepr xs: (List String) -> String
  (str "[" (stringJoin (map (fn [(x String)] -> String (str "'" x "'")) xs) ", ") "]")

fn timeoutText argv: (List String) secs: Int64 -> String
  (str "Command '" (pyListRepr argv) "' timed out after " (stringFromInt64 secs) " seconds")

fn readText! p: String -> (Result String String)
  (mt (fileReadString p) ((ok t) (ok (k/universalNewlines t))) ((err e) (err e)))

fn stagedContent env: GateEnv p: String -> (Option String)
  (mt (listHead (filter (fn [(sp (Pair String String))] -> Bool (= (pairFirst sp) p)) env.staged))
    ((some sp) (some (pairSecond sp)))
    ((none) (none)))

fn guardParts! cur: String parts: (List String) -> Bool
  (mt (listHead parts)
    ((none) true)
    ((some part)
      (cond
        ((or (stringEmpty? part) (= part ".")) (guardParts! cur (optionOr (listTail parts) (list))))
        ((and (fileExists? (k/joinPath cur part)) (not (k/realChild? cur part))) false)
        (else (guardParts! (k/joinPath cur part) (optionOr (listTail parts) (list)))))))

fn stagedWritable! root: String p: String -> Bool
  (let [(norm (k/normalizePath p))]
    (and (or (= norm root) (stringStartsWith? norm (str root "/")))
         (guardParts! root (stringSplit (k/relPath norm root) "/"))
         (let [(real (resultOr (realPath norm) norm))] (or (= real root) (stringStartsWith? real (str root "/")) (not (fileExists? norm))))))

fn writableStaged! env: GateEnv -> (List (Pair String String))
  (filter (fn [(sp (Pair String String))] -> Bool (stagedWritable! env.root (pairFirst sp))) env.staged)

fn extLang ext: String -> String
  (cond
    ((= ext ".asl") "asl") ((= ext ".asn") "asn")
    ((listContains? (list ".ts" ".tsx" ".mts" ".cts") ext) "typescript")
    ((listContains? (list ".js" ".jsx" ".mjs" ".cjs") ext) "javascript")
    ((= ext ".py") "python") ((= ext ".go") "go") ((= ext ".rs") "rust") ((or (= ext ".c") (= ext ".h")) "c")
    ((= ext ".java") "java") ((or (= ext ".sh") (= ext ".bash")) "shell") ((= ext ".md") "markdown")
    ((= ext ".json") "json") ((or (= ext ".yaml") (= ext ".yml")) "yaml") ((= ext ".toml") "toml")
    (else "text"))

fn shebangLang prog: String -> String
  (cond
    ((= prog "python") "python")
    ((listContains? (list "bash" "sh" "zsh" "dash" "ksh") prog) "shell")
    ((= prog "node") "javascript")
    (else "text"))

fn stripVersion s: String -> String
  (let [(n (stringLength s))]
    (if (and (> n 0) (let [(c (bytesGet (stringToBytes s) (- n 1)))] (or (digit? c) (= c 46)))) (stripVersion (sub s 0 (- n 1))) s))

fn spaceWords s: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
          (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace s "\t" " ") "\n" " ") "\r" " ") "\x0c" " ") " "))

fn shebangWord words: (List String) -> String
  (mt (listHead words)
    ((none) "")
    ((some w)
      (if (or (= (k/baseName w) "env") (stringStartsWith? w "-"))
        (shebangWord (optionOr (listTail words) (list)))
        (stripVersion (k/baseName w)))))

fn shebangProg text: String -> String
  (if (stringStartsWith? text "#!")
    (shebangWord (spaceWords (sub (optionOr (listHead (stringSplit text "\n")) "") 2 (stringLength text))))
    "")

fn headLine! p: String -> String
  (mt (fileReadRange p 0 256)
    ((ok bs) (let [(t (resultOr (fileReadString p) ""))
                   (cut (sub t 0 (min 256 (stringLength t))))]
               (mt (stringIndexOf cut "\n") ((some i) (sub cut 0 (+ i 1))) ((none) cut))))
    ((err _) ""))

fn languageOf! path: String -> String
  (let [(ext (stringLower (pyExt path)))]
    (if (not (stringEmpty? ext))
      (extLang ext)
      (let [(line (headLine! path))]
        (if (stringStartsWith? line "#!")
          (let [(prog (shebangWord (spaceWords (sub line 2 (stringLength line)))))] (if (stringEmpty? prog) "text" (shebangLang prog)))
          "text"))))

fn syntaxLang! path: String content: String -> String
  (let [(lang (languageOf! path))]
    (if (or (!= lang "text") (not (stringEmpty? (pyExt path))))
      lang
      (let [(prog (shebangProg content))] (if (stringEmpty? prog) "text" (shebangLang prog)))))

fn checkerName lang: String -> String
  (cond
    ((= lang "python") "python") ((= lang "json") "json") ((= lang "javascript") "node") ((= lang "shell") "bash")
    ((= lang "typescript") "tsc") ((= lang "yaml") "pyyaml") ((= lang "toml") "tomllib") ((= lang "c") "cc")
    (else ""))

fn checkerField lang: String -> String
  (let [(n (checkerName lang))] (if (stringEmpty? n) "" (str " :checker \"" n "\"")))

fn pyChecker -> String
  "import sys\nlang = sys.argv[1]\nsrc = sys.stdin.buffer.read().decode('utf-8', 'replace')\ndef out(st, msg=''):\n    sys.stdout.write(st + '\\n' + msg)\n    sys.exit(0)\nif lang == 'version':\n    out('ok', 'python' + str(sys.version_info[0]) + '.' + str(sys.version_info[1]))\nif lang == 'python':\n    try:\n        compile(src, sys.argv[2], 'exec', dont_inherit=True)\n    except SyntaxError as e:\n        out('error', str(e.msg) + ' at line ' + str(e.lineno))\n    except Exception as e:\n        out('error', str(e))\n    out('ok')\nif lang == 'json':\n    import json\n    try:\n        json.loads(src)\n    except ValueError as e:\n        out('error', str(e))\n    out('ok')\nif lang == 'yaml':\n    try:\n        import yaml\n    except ImportError as e:\n        out('skipped', 'PyYAML not importable: ' + str(e))\n    try:\n        list(yaml.safe_load_all(src))\n    except yaml.constructor.ConstructorError:\n        out('ok')\n    except yaml.YAMLError as e:\n        out('error', str(e).replace('\\n', ' ')[:300])\n    except (ValueError, RecursionError) as e:\n        out('skipped', 'PyYAML failed internally: ' + str(e))\n    out('ok')\nif lang == 'toml':\n    try:\n        import tomllib\n    except ImportError:\n        out('skipped', 'tomllib needs Python 3.11 or later')\n    try:\n        tomllib.loads(src)\n    except tomllib.TOMLDecodeError as e:\n        out('error', str(e)[:300])\n    out('ok')\nout('skipped', 'no checker for ' + lang)\n"

fn pythonCheck! lang: String path: String content: String -> (Pair String String)
  (let [(py (whichTool! "python3"))]
    (if (stringEmpty? py)
      (pair "skipped" "python3 not found")
      (mt (procSpawnv (list py "-c" (pyChecker) lang path) (none) (none))
        ((err e) (pair "skipped" (str "python3 did not run: " e)))
        ((ok sp)
          (let [(wrote (feedAll! sp.stdin content))
                (closed (fdClose sp.stdin))
                (st (pumpUntil! sp (PumpState :outOpen true :errOpen true :out "" :errText "" :timedOut false :failure "") (+ (monotonicNs) 15000000000)))
                (st2 (if st.timedOut (afterTerm! sp st 0) st))
                (done (closeLeft! sp st2))
                (code (resultOr (procWaitPid sp.pid false) (none)))
                (out st2.out)]
            (cond
              (st2.timedOut (pair "skipped" "python3 timed out after 15s"))
              ((!= (optionOr code -1) 0) (pair "skipped" (str "python3 checker exit " (stringFromInt64 (optionOr code -1)) ": " (pyTrunc (stringTrim st2.errText) 300))))
              (else
                (mt (stringIndexOf out "\n")
                  ((some i) (pair (sub out 0 i) (sub out (+ i 1) (stringLength out))))
                  ((none) (pair "skipped" "python3 checker printed no verdict"))))))))))

fn feedAll! fd: Int64 text: String -> Bool
  (if (stringEmpty? text)
    true
    (mt (fdWrite fd text)
      ((ok n) (feedAll! fd (sub text n (stringLength text))))
      ((err _) false)))

fn relOf env: GateEnv p: String -> String
  (k/relToRoot env.root p)

fn withTemp! content: String suffix: String run: (fn [String] -> (Pair String String)) failWord: String -> (Pair String String)
  (mt (makeTempFile! "aslSyntax" suffix content)
    ((err e) (pair "skipped" (str failWord " did not run: " e)))
    ((ok tmp) (let [(r (run tmp))] (do (pathRemove tmp) r))))

fn nodeCheck! env: GateEnv path: String content: String -> (Pair String String)
  (let [(node (whichTool! "node"))
        (ext (let [(e (pyExt path))] (if (stringEmpty? e) ".js" e)))]
    (if (stringEmpty? node)
      (pair "skipped" "node not found")
      (withTemp! content ext
        (fn [(tmp String)] -> (Pair String String)
          (let [(argv (list node "--check" tmp))
                (r (runArgv! argv (none) (none) 15000 0))]
            (cond
              ((not (stringEmpty? r.failure)) (pair "skipped" (osErrorText r.failure node)))
              (r.timedOut (pair "skipped" (timeoutText argv 15)))
              ((= r.code 0) (pair "ok" ""))
              (else
                (let [(lines (pySplitLines r.errText false))
                      (diag (stringTrim (firstWhere lines (fn [(l String)] -> Bool (stringContains? l "SyntaxError")))))
                      (at (stringTrim (firstWhere lines (fn [(l String)] -> Bool (stringStartsWith? l (str tmp ":"))))))
                      (where (if (stringEmpty? at) "" (stringReplace at tmp (relOf env path))))]
                  (if (stringEmpty? diag)
                    (pair "error" (let [(t (pyTrunc (stringTrim r.errText) 300))] (if (stringEmpty? t) "node --check failed" t)))
                    (pair "error" (pyTrunc (str (if (stringEmpty? where) "" (str where " ")) diag) 300))))))))
        "node")))

fn bashCheck! env: GateEnv path: String content: String -> (Pair String String)
  (let [(prog (shebangProg content))
        (bash (whichTool! "bash"))]
    (cond
      ((or (= prog "zsh") (= prog "ksh")) (pair "skipped" (str "bash -n does not parse " prog)))
      ((stringEmpty? bash) (pair "skipped" "bash not found"))
      (else
        (withTemp! content (let [(e (pyExt path))] (if (stringEmpty? e) ".sh" e))
          (fn [(tmp String)] -> (Pair String String)
            (let [(r (runArgv! (list bash "-n" tmp) (none) (none) 15000 0))]
              (cond
                ((not (stringEmpty? r.failure)) (pair "skipped" (str "bash -n did not run: " (osErrorText r.failure bash))))
                (r.timedOut (pair "skipped" "bash -n timed out after 15s"))
                ((= r.code 0) (pair "ok" ""))
                (else
                  (let [(lines (strippedLines r.errText))]
                    (pair "error" (pyTrunc (mt (listHead lines) ((some l) (stringReplace l tmp (relOf env path))) ((none) (str "bash -n exit " (stringFromInt64 r.code)))) 300)))))))
          "bash -n"))))

fn tsCodeAt l: String i: Int64 first: (fn [Int64] -> Bool) wantBoundary: Bool -> String
  (let [(b (stringToBytes l))
        (n (stringLength l))]
    (if (and (<= (+ i 4) n) (first (bytesGet b i)) (digit? (bytesGet b (+ i 1))) (digit? (bytesGet b (+ i 2))) (digit? (bytesGet b (+ i 3)))
             (or (not wantBoundary) (>= (+ i 4) n) (not (wordByte? (bytesGet b (+ i 4))))))
      (str "TS" (sub l i (+ i 4)))
      ""))

fn tsCodes l: String from: Int64 first: (fn [Int64] -> Bool) wantBoundary: Bool acc: (List String) -> (List String)
  (mt (stringIndexOf (sub l from (stringLength l)) "error TS")
    ((none) (listReverse acc))
    ((some rel)
      (let [(at (+ from rel 8))
            (code (tsCodeAt l at first wantBoundary))]
        (tsCodes l (+ from rel 1) first wantBoundary (if (stringEmpty? code) acc (cons code acc))))))

fn optionDiag? l: String -> Bool
  (not (listEmpty? (tsCodes l 0 (fn [(c Int64)] -> Bool (or (= c 53) (= c 54))) false (list))))

fn tsOptionCode? code: String -> Bool
  (listContains? (list "TS1205" "TS1208" "TS1269" "TS1286" "TS1287" "TS1371" "TS1448" "TS1484" "TS1485") code)

fn syntaxDiag? l: String -> Bool
  (mt (listHead (tsCodes l 0 (fn [(c Int64)] -> Bool (= c 49)) true (list)))
    ((some code) (not (tsOptionCode? code)))
    ((none) false))

fn tsConfig ext: String tname: String -> String
  (str "{\"compilerOptions\": {\"noEmit\": true, \"isolatedModules\": true, \"skipLibCheck\": true, \"noResolve\": true, \"types\": [], \"pretty\": false"
       (if (= ext ".tsx") ", \"jsx\": \"preserve\"" "") "}, \"files\": [\"" tname "\"]}")

fn tscCheck! env: GateEnv path: String content: String -> (Pair String String)
  (let [(tsc (whichTool! "tsc"))
        (ext (let [(e (stringLower (pyExt path)))] (if (stringEmpty? e) ".ts" e)))
        (tname (str "staged" ext))]
    (if (stringEmpty? tsc)
      (pair "skipped" "tsc not found")
      (mt (makeTempDir! "aslSyntax")
        ((err e) (pair "skipped" (str "tsc did not run: " e)))
        ((ok tdir)
          (let [(w1 (fileWrite (k/joinPath tdir tname) content))
                (w2 (fileWrite (k/joinPath tdir "tsconfig.json") (tsConfig ext tname)))
                (r (runArgv! (list tsc "-p" "tsconfig.json") (some tdir) (none) 15000 0))
                (gone (pathRemove tdir))
                (diags (strippedLines (str r.out "\n" r.errText)))
                (opt (filter optionDiag? diags))
                (syn (map (fn [(l String)] -> String (stringReplace l tname (relOf env path))) (filter syntaxDiag? diags)))]
            (cond
              ((not (stringEmpty? r.failure)) (pair "skipped" (str "tsc did not run: " (osErrorText r.failure tsc))))
              (r.timedOut (pair "skipped" "tsc timed out after 15s"))
              ((not (listEmpty? opt)) (pair "skipped" (pyTrunc (str "tsc rejected its options: " (optionOr (listHead opt) "")) 300)))
              ((not (listEmpty? syn)) (pair "error" (pyTrunc (optionOr (listHead syn) "") 300)))
              (else (pair "ok" ""))))))))

fn errorWord? l: String from: Int64 -> Bool
  (mt (stringIndexOf (sub l from (stringLength l)) "error:")
    ((none) false)
    ((some rel)
      (let [(at (+ from rel))]
        (if (or (= at 0) (not (wordByte? (bytesGet (stringToBytes l) (- at 1))))) true (errorWord? l (+ at 1))))))

fn missingInclude? l: String -> Bool
  (or (stringContains? l "file not found") (stringContains? l "No such file or directory"))

fn ccCheck! env: GateEnv path: String content: String -> (Pair String String)
  (let [(cc (whichTool! "cc"))]
    (if (stringEmpty? cc)
      (pair "skipped" "cc not found")
      (withTemp! content ".c"
        (fn [(tmp String)] -> (Pair String String)
          (let [(r (runArgv! (list cc "-fsyntax-only" "-x" "c" "-I" (k/dirName path) tmp) (none) (none) 15000 0))]
            (cond
              ((not (stringEmpty? r.failure)) (pair "skipped" (str "cc did not run: " (osErrorText r.failure cc))))
              (r.timedOut (pair "skipped" "cc timed out after 15s"))
              ((= r.code 0) (pair "ok" ""))
              (else
                (let [(errs (map (fn [(l String)] -> String (stringReplace (stringTrim l) tmp (relOf env path))) (filter (fn [(l String)] -> Bool (errorWord? l 0)) (pySplitLines r.errText false))))
                      (missing (filter missingInclude? errs))
                      (real (filter (fn [(l String)] -> Bool (not (missingInclude? l))) errs))]
                  (cond
                    ((not (listEmpty? real)) (pair "error" (pyTrunc (optionOr (listHead real) "") 300)))
                    ((not (listEmpty? missing)) (pair "skipped" (pyTrunc (str "include not found, not a syntax error: " (optionOr (listHead missing) "")) 300)))
                    (else (pair "skipped" (str "cc exit " (stringFromInt64 r.code) " without an error diagnostic")))))))))
        "cc")))

fn foreignSyntax! env: GateEnv path: String content: String -> (Pair String String)
  (let [(lang (syntaxLang! path content))]
    (cond
      ((listContains? (list "python" "json" "yaml" "toml") lang) (pythonCheck! lang path content))
      ((and (= lang "javascript") (= (stringLower (pyExt path)) ".jsx")) (pair "skipped" "node --check cannot parse JSX"))
      ((= lang "javascript") (nodeCheck! env path content))
      ((= lang "shell") (bashCheck! env path content))
      ((= lang "typescript") (tscCheck! env path content))
      ((= lang "c") (ccCheck! env path content))
      (else (pair "skipped" (str "no local checker for " lang)))))

fn syntaxHost! path: String -> String
  (if (= (languageOf! path) "python")
    (let [(v (pythonCheck! "version" path ""))] (if (= (pairFirst v) "ok") (str " :syntaxHost \"" (pairSecond v) "\"") ""))
    "")

fn closerFor b: Int64 -> Int64
  (cond ((= b 40) 41) ((= b 91) 93) (else 125))

fn openerFor b: Int64 -> Int64
  (cond ((= b 41) 40) ((= b 93) 91) (else 123))

fn delimChar b: Int64 -> String
  (cond ((= b 40) "(") ((= b 41) ")") ((= b 91) "[") ((= b 93) "]") ((= b 123) "{") ((= b 125) "}") ((= b 34) "\"") (else ""))

fn openByte? b: Int64 -> Bool
  (or (= b 40) (= b 91) (= b 123))

fn closeByte? b: Int64 -> Bool
  (or (= b 41) (= b 93) (= b 125))

fn diagScan b: Bytes n: Int64 i: Int64 stack: (List (Pair Int64 Int64)) inStr: Bool strStart: Int64 inComment: Bool -> (Option DelimDiag)
  (if (>= i n)
    (cond
      (inStr (some (DelimDiag :kind "unclosed" :byte n :expected "\"" :msg "unterminated string literal")))
      ((not (listEmpty? stack))
        (let [(top (optionOr (listHead stack) (pair 40 0)))]
          (some (DelimDiag :kind "unclosed" :byte n :expected (stringJoin (map (fn [(p (Pair Int64 Int64))] -> String (delimChar (closerFor (pairFirst p)))) stack) "")
                           :msg (str "unclosed delimiter '" (delimChar (pairFirst top)) "' (" (stringFromInt64 (listLength stack)) " open containers remain)")))))
      (else (none)))
    (let [(c (bytesGet b i))]
      (cond
        (inComment (diagScan b n (+ i 1) stack inStr strStart (!= c 10)))
        (inStr (cond ((= c 92) (diagScan b n (+ i 2) stack true strStart false))
                     ((= c 34) (diagScan b n (+ i 1) stack false strStart false))
                     (else (diagScan b n (+ i 1) stack true strStart false))))
        ((= c 34) (diagScan b n (+ i 1) stack true i false))
        ((= c 59) (diagScan b n (+ i 1) stack false strStart true))
        ((openByte? c) (diagScan b n (+ i 1) (cons (pair c i) stack) false strStart false))
        ((closeByte? c)
          (mt (listHead stack)
            ((none) (some (DelimDiag :kind "unexpected" :byte i :expected "" :msg (str "unexpected closing delimiter '" (delimChar c) "' at byte " (stringFromInt64 i)))))
            ((some top)
              (if (!= (closerFor (pairFirst top)) c)
                (let [(exp (delimChar (closerFor (pairFirst top))))]
                  (some (DelimDiag :kind "mismatch" :byte i :expected exp :msg (str "mismatched delimiter '" (delimChar c) "' (expected '" exp "') at byte " (stringFromInt64 i)))))
                (diagScan b n (+ i 1) (optionOr (listTail stack) (list)) false strStart false)))))
        (else (diagScan b n (+ i 1) stack false strStart false)))))

fn aslDelimiterDiag text: String -> (Option DelimDiag)
  (diagScan (stringToBytes text) (stringLength text) 0 (list) false -1 false)

fn aslDelimiterError text: String -> String
  (mt (aslDelimiterDiag text) ((some d) d.msg) ((none) ""))

fn atomByte? c: Int64 -> Bool
  (not (or (spaceByte? c) (openByte? c) (closeByte? c) (= c 34) (= c 59)))

fn strEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (bytesGet b i) 34) (+ i 1))
    ((= (bytesGet b i) 92) (if (< (+ i 1) n) (strEnd b n (+ i 2)) i))
    (else (strEnd b n (+ i 1))))

fn runEnd b: Bytes n: Int64 i: Int64 p: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (p (bytesGet b i))) (runEnd b n (+ i 1) p) i)

fn tokScan b: Bytes n: Int64 i: Int64 acc: (List Tok) -> (List Tok)
  (if (>= i n)
    (listReverse acc)
    (let [(c (bytesGet b i))]
      (cond
        ((spaceByte? c) (tokScan b n (+ i 1) acc))
        ((openByte? c) (tokScan b n (+ i 1) (cons (Tok :kind "open" :start i :end (+ i 1) :byte c) acc)))
        ((closeByte? c) (tokScan b n (+ i 1) (cons (Tok :kind "close" :start i :end (+ i 1) :byte c) acc)))
        ((= c 59) (tokScan b n (runEnd b n i (fn [(x Int64)] -> Bool (!= x 10))) acc))
        ((= c 34) (let [(e (strEnd b n (+ i 1)))] (tokScan b n e (cons (Tok :kind "atom" :start i :end e :byte 0) acc))))
        (else (let [(e (runEnd b n i atomByte?))] (tokScan b n e (cons (Tok :kind "atom" :start i :end e :byte 0) acc)))))))

fn aslTokens text: String -> (List Tok)
  (tokScan (stringToBytes text) (stringLength text) 0 (list))

fn structureKey text: String -> String
  (stringJoin (map (fn [(t Tok)] -> String (str (stringFromInt64 (- t.end t.start)) ":" (sub text t.start t.end))) (aslTokens text)) "|")

fn lastNewline b: Bytes from: Int64 to: Int64 -> Int64
  (cond ((< to from) -1) ((= (bytesGet b to) 10) to) (else (lastNewline b from (- to 1))))

fn indentScan b: Bytes toks: (List Tok) stack: (List (Pair Int64 Int64)) viol: Int64 lineStart: Int64 prevEnd: Int64 first: Bool lastClosed: Int64 -> Int64
  (mt (listHead toks)
    ((none) viol)
    ((some t)
      (let [(j (lastNewline b prevEnd (- t.start 1)))
            (ls (if (!= j -1) (+ j 1) lineStart))
            (isFirst (or first (!= j -1)))
            (col (- t.start ls))
            (v1 (if isFirst
                  (+ viol
                     (mt (listHead stack) ((some top) (if (<= col (pairFirst top)) 1 0)) ((none) (if (> col 0) 1 0)))
                     (if (and (>= lastClosed 0) (> col lastClosed)) 1 0))
                  viol))
            (lc1 (if isFirst -1 lastClosed))
            (rest (optionOr (listTail toks) (list)))]
        (cond
          ((= t.kind "open") (indentScan b rest (cons (pair col ls) stack) v1 ls t.end false lc1))
          ((and (= t.kind "close") (not (listEmpty? stack)))
            (let [(top (optionOr (listHead stack) (pair 0 0)))]
              (indentScan b rest (optionOr (listTail stack) (list)) v1 ls t.end false (if (!= (pairSecond top) ls) (pairFirst top) lc1))))
          (else (indentScan b rest stack v1 ls t.end false lc1))))))

fn indentationViolations text: String -> Int64
  (indentScan (stringToBytes text) (aslTokens text) (list) 0 0 0 true -1)

fn suffixStep st: Suffix t: Tok -> Suffix
  (cond
    ((not st.ok) st)
    ((= t.kind "close") (Suffix :ok true :len (+ st.len 1) :stack (cons t.byte st.stack)))
    ((= t.kind "open")
      (if (and (> st.len 0) (= (optionOr (listHead st.stack) 0) (closerFor t.byte)))
        (Suffix :ok true :len (- st.len 1) :stack (optionOr (listTail st.stack) (list)))
        (with st :ok false)))
    (else st))

fn suffixes toks: (List Tok) -> (List Suffix)
  (let [(last (Suffix :ok true :len 0 :stack (list)))]
    (pairSecond (fold (fn [(acc (Pair Suffix (List Suffix))) (t Tok)] -> (Pair Suffix (List Suffix))
                        (let [(nx (suffixStep (pairFirst acc) t))] (pair nx (cons nx (pairSecond acc)))))
                      (pair last (list last))
                      (listReverse toks))))

fn matchesTop st: ScanState kExtra: Int64 r: Suffix -> Bool
  (and r.ok (= st.len (+ r.len kExtra)) (= (listDrop st.stack kExtra) r.stack))

fn matchesPushed st: ScanState closer: Int64 r: Suffix -> Bool
  (and r.ok (= (+ st.len 1) r.len) (= (cons closer st.stack) r.stack))

fn closersText cs: (List Int64) -> String
  (stringJoin (map delimChar cs) "")

fn addCand st: ScanState c: Cand -> ScanState
  (with st :cands (cons c st.cands))

fn candAt st: ScanState cost: Int64 action: String byte: Int64 text: String cutFrom: Int64 cutTo: Int64 -> Cand
  (Cand :cost cost :action action :byte byte :text text :cutFrom cutFrom :cutTo cutTo :idx (listLength st.cands))

fn slotCands st: ScanState r: Suffix nextStart: Int64 -> ScanState
  (let [(kk (- st.len r.len))
        (pos st.prevEnd)
        (s1 (if (and (>= kk 1) (matchesTop st kk r))
              (let [(seq (closersText (listTake st.stack kk)))] (addCand st (candAt st kk "insert" pos seq pos pos)))
              st))
        (top (optionOr (listHead r.stack) 0))]
    (if (and (> r.len 0) (matchesPushed s1 top r))
      (let [(o (openerFor top))] (addCand s1 (candAt s1 1 "insert" nextStart (delimChar o) nextStart nextStart)))
      s1))

fn tokCands st: ScanState t: Tok rNext: Suffix -> ScanState
  (cond
    ((= t.kind "close")
      (let [(s1 (if (matchesTop st 0 rNext) (addCand st (candAt st 1 "delete" t.start (delimChar t.byte) t.start t.end)) st))]
        (if (and (> s1.len 0) (!= (optionOr (listHead s1.stack) 0) t.byte))
          (let [(want (optionOr (listHead s1.stack) 0))
                (popped (ScanState :stack (optionOr (listTail s1.stack) (list)) :len (- s1.len 1) :ok true :cands s1.cands :prevEnd s1.prevEnd))]
            (if (matchesTop popped 0 rNext) (addCand s1 (candAt s1 1 "replace" t.start (delimChar want) t.start t.end)) s1))
          s1)))
    ((= t.kind "open")
      (let [(s1 (if (matchesTop st 0 rNext) (addCand st (candAt st 1 "delete" t.start (delimChar t.byte) t.start t.end)) st))]
        (fold (fn [(s ScanState) (alt Int64)] -> ScanState
                (if (and (!= alt t.byte) (matchesPushed s (closerFor alt) rNext)) (addCand s (candAt s 1 "replace" t.start (delimChar alt) t.start t.end)) s))
              s1
              (list 40 91 123))))
    (else st))

fn advance st: ScanState t: Tok -> ScanState
  (cond
    ((= t.kind "open") (with st :stack (cons (closerFor t.byte) st.stack) :len (+ st.len 1) :ok true :prevEnd t.end))
    ((= t.kind "close")
      (if (and (> st.len 0) (= (optionOr (listHead st.stack) 0) t.byte))
        (with st :stack (optionOr (listTail st.stack) (list)) :len (- st.len 1) :ok true :prevEnd t.end)
        (with st :ok false :prevEnd t.end)))
    (else (with st :ok true :prevEnd t.end)))

fn scanSlots toks: (List Tok) rs: (List Suffix) st: ScanState textLen: Int64 -> ScanState
  (if (not st.ok)
    st
    (mt (listHead toks)
      ((none) (slotCands st (optionOr (listHead rs) (Suffix :ok false :len 0 :stack (list))) st.prevEnd))
      ((some t)
        (let [(r (optionOr (listHead rs) (Suffix :ok false :len 0 :stack (list))))
              (rTail (optionOr (listTail rs) (list)))
              (rNext (optionOr (listHead rTail) (Suffix :ok false :len 0 :stack (list))))
              (s1 (slotCands st r t.start))
              (s2 (tokCands s1 t rNext))]
          (scanSlots (optionOr (listTail toks) (list)) rTail (advance s2 t) textLen)))))

fn applyCand text: String c: Cand -> String
  (str (sub text 0 c.cutFrom) (if (= c.action "delete") "" c.text) (sub text c.cutTo (stringLength text)))

fn candRepair c: Cand -> Repair
  (Repair :action c.action :byte c.byte :text c.text :rank (list))

fn verifyCands text: String cands: (List Cand) seen: (List String) good: (List (Pair Repair String)) -> (Pair (List (Pair Repair String)) Bool)
  (mt (listHead cands)
    ((none) (pair (listReverse good) false))
    ((some c)
      (if (>= (listLength good) 64)
        (pair (listReverse good) true)
        (let [(nb (applyCand text c))
              (rest (optionOr (listTail cands) (list)))]
          (if (some? (aslDelimiterDiag nb))
            (verifyCands text rest seen good)
            (let [(key (structureKey nb))]
              (if (listContains? seen key)
                (verifyCands text rest seen good)
                (verifyCands text rest (cons key seen) (cons (pair (candRepair c) nb) good)))))))))

fn touchesOpener? r: Repair -> Bool
  (or (stringContains? r.text "(") (stringContains? r.text "[") (stringContains? r.text "{"))

fn rankKey fault: Int64 item: (Pair Repair String) -> (List Int64)
  (let [(r (pairFirst item))
        (b r.byte)]
    (list (if (touchesOpener? r) 1 0) (indentationViolations (pairSecond item)) (if (<= b fault) 0 1) (if (<= b fault) (- fault b) (- b fault))))

fn keyLess a: (List Int64) b: (List Int64) -> Bool
  (mt (listHead a)
    ((none) false)
    ((some x)
      (let [(y (optionOr (listHead b) 0))]
        (cond ((< x y) true) ((> x y) false) (else (keyLess (optionOr (listTail a) (list)) (optionOr (listTail b) (list))))))))

fn insertBy less: (fn [(Pair (List Int64) (Pair Repair String)) (Pair (List Int64) (Pair Repair String))] -> Bool) x: (Pair (List Int64) (Pair Repair String)) xs: (List (Pair (List Int64) (Pair Repair String))) -> (List (Pair (List Int64) (Pair Repair String)))
  (mt (listHead xs)
    ((none) (list x))
    ((some h) (if (less x h) (cons x xs) (cons h (insertBy less x (optionOr (listTail xs) (list)))))))

fn stableSort items: (List (Pair (List Int64) (Pair Repair String))) -> (List (Pair (List Int64) (Pair Repair String)))
  (fold (fn [(acc (List (Pair (List Int64) (Pair Repair String)))) (x (Pair (List Int64) (Pair Repair String)))] -> (List (Pair (List Int64) (Pair Repair String)))
          (insertBy (fn [(a (Pair (List Int64) (Pair Repair String))) (b (Pair (List Int64) (Pair Repair String)))] -> Bool (keyLess (pairFirst a) (pairFirst b))) x acc))
        (list)
        items)

fn levelDiffers a: (List Int64) b: (List Int64) level: Int64 -> Bool
  (if (= level 2)
    (or (!= (optionOr (listGet a 2) 0) (optionOr (listGet b 2) 0)) (!= (optionOr (listGet a 3) 0) (optionOr (listGet b 3) 0)))
    (!= (optionOr (listGet a level) 0) (optionOr (listGet b level) 0)))

fn firstLevel a: (List Int64) b: (List Int64) level: Int64 -> Int64
  (cond ((> level 2) -1) ((levelDiffers a b level) level) (else (firstLevel a b (+ level 1))))

fn reps items: (List (Pair (List Int64) (Pair Repair String))) -> (List Repair)
  (map (fn [(x (Pair (List Int64) (Pair Repair String)))] -> Repair (pairFirst (pairSecond x))) items)

fn repairRun status: String text: String r: (Option Repair) cands: (List Int64) basis: String rejected: (List Repair) -> RepairRun
  (RepairRun :status status :text text :repair r :candidates cands :basis basis :rejected rejected)

fn sortCands cands: (List Cand) -> (List Cand)
  (let [(n (+ (listLength cands) 1))]
    (listSortBy (fn [(c Cand)] -> Int64 (+ (* c.byte n) c.idx)) cands))

fn aslRepair text: String heuristic: Bool -> RepairRun
  (mt (aslDelimiterDiag text)
    ((none) (repairRun "none" text (none) (list) "" (list)))
    ((some d)
      (let [(toks (aslTokens text))
            (rs (suffixes toks))
            (st (scanSlots toks rs (ScanState :stack (list) :len 0 :ok true :cands (list) :prevEnd 0) (stringLength text)))
            (cands (listReverse st.cands))]
        (if (listEmpty? cands)
          (repairRun "unrepairable" text (none) (list) "" (list))
          (let [(best (optionOr (listMin (map (fn [(c Cand)] -> Int64 c.cost) cands)) 0))
                (v (verifyCands text (sortCands (filter (fn [(c Cand)] -> Bool (= c.cost best)) cands)) (list) (list)))
                (good (pairFirst v))
                (truncated (pairSecond v))
                (n (listLength good))]
            (cond
              ((= n 0) (repairRun "unrepairable" text (none) (list) "" (list)))
              ((and (= n 1) (not truncated))
                (let [(g (optionOr (listHead good) (pair (Repair :action "" :byte 0 :text "" :rank (list)) text)))]
                  (repairRun "unique" (pairSecond g) (some (pairFirst g)) (list (pairFirst g).byte) "structural" (list))))
              (else
                (let [(scored (stableSort (map (fn [(g (Pair Repair String))] -> (Pair (List Int64) (Pair Repair String)) (pair (list (indentationViolations (pairSecond g))) g)) good)))
                      (s0 (optionOr (listGet scored 0) (pair (list 0) (pair (Repair :action "" :byte 0 :text "" :rank (list)) text))))
                      (s1 (optionOr (listGet scored 1) s0))]
                  (if (and (not truncated) (> (listLength scored) 1) (< (optionOr (listHead (pairFirst s0)) 0) (optionOr (listHead (pairFirst s1)) 0)))
                    (repairRun "unique" (pairSecond (pairSecond s0)) (some (pairFirst (pairSecond s0))) (map (fn [(r Repair)] -> Int64 r.byte) (reps scored)) "indentation" (listDrop (reps scored) 1))
                    (let [(ranked (stableSort (map (fn [(g (Pair Repair String))] -> (Pair (List Int64) (Pair Repair String)) (pair (rankKey d.byte g) g)) good)))
                          (r0 (optionOr (listGet ranked 0) s0))
                          (r1 (optionOr (listGet ranked 1) s0))
                          (level (firstLevel (pairFirst r0) (pairFirst r1) 0))]
                      (if (and heuristic (not truncated) (>= level 0))
                        (let [(bestRep (pairFirst (pairSecond r0)))
                              (rules (listTake (list "closerOnly" "indentation" "nearestFault") (+ level 1)))]
                          (repairRun "unique" (pairSecond (pairSecond r0)) (some (Repair :action bestRep.action :byte bestRep.byte :text bestRep.text :rank rules))
                                     (map (fn [(r Repair)] -> Int64 r.byte) (reps ranked)) "heuristic" (listDrop (reps ranked) 1)))
                        (repairRun "ambiguous" text (none) (map (fn [(g (Pair Repair String))] -> Int64 (pairFirst g).byte) good) "" (list)))))))))))))

fn repairAsn r: (Option Repair) -> String
  (mt r
    ((none) "(:none)")
    ((some x) (str "(:action :" x.action " :byte " (stringFromInt64 x.byte) " :text \"" (k/escapeAsnVal x.text) "\")")))

fn rankAsn r: (Option Repair) -> String
  (mt r
    ((some x) (if (listEmpty? x.rank) "" (str " :rank (" (stringJoin x.rank " ") ")")))
    ((none) ""))

fn overlayWalk! env: GateEnv srcDir: String dstDir: String relDir: String stagedRel: (List String) realDirs: (List String) -> Bool
  (mt (dirList srcDir)
    ((err _) true)
    ((ok names)
      (listAll? (fn [(name String)] -> Bool
                  (let [(r (if (stringEmpty? relDir) name (str relDir "/" name)))
                        (sp (k/joinPath srcDir name))
                        (dp (k/joinPath dstDir name))]
                    (cond
                      ((listContains? stagedRel r) true)
                      ((not (k/realChild? srcDir name)) true)
                      ((and (k/isDir! sp) (or (listContains? realDirs r) (and (not (stringStartsWith? name ".")) (!= name "node_modules"))))
                        (do (dirCreate dp) (overlayWalk! env sp dp r stagedRel realDirs)))
                      ((and (k/isFile! sp) (or (stringEndsWith? name ".asl") (= name "manifest.asn") (= name ".asl.config.asn")))
                        (mt (fileReadBytes sp) ((ok bs) (do (fileWrite dp bs) true)) ((err _) true)))
                      (else true))))
                (listSort names))))

fn parents rel: String acc: (List String) -> (List String)
  (let [(p (k/dirName rel))]
    (if (or (stringEmpty? p) (= p ".") (= p rel)) acc (parents p (cons p acc))))

fn buildOverlay! env: GateEnv staged: (List (Pair String String)) -> (Result String String)
  (mt (makeTempDir! "aslOverlay")
    ((err e) (err e))
    ((ok tmp)
      (let [(rels (map (fn [(sp (Pair String String))] -> String (k/relPath (pairFirst sp) env.root)) staged))
            (realDirs (fold (fn [(acc (List String)) (r String)] -> (List String) (parents r acc)) (list) rels))
            (walked (overlayWalk! env env.root tmp "" rels realDirs))
            (written (listAll? (fn [(sp (Pair String String))] -> Bool
                                 (let [(out (k/joinPath tmp (k/relPath (pairFirst sp) env.root)))]
                                   (do (dirCreate (k/dirName out)) (resultOr (resultMap (fileWrite out (pairSecond sp)) (fn [(u Unit)] -> Bool true)) false))))
                               staged))]
        (if written (ok tmp) (do (pathRemove tmp) (err (str "overlay write failed under " tmp)))))))

fn unroot text: String roots: (List String) -> String
  (fold (fn [(t String) (r String)] -> String (if (stringEmpty? r) t (stringReplace t (str r "/") ""))) text roots)

fn runHost! env: GateEnv verb: String path: String timeoutS: Int64 -> (Result HostRun String)
  (if (not (executable? env.host))
    (err "absent")
    (let [(staged (writableStaged! env))
          (ov (if (listEmpty? staged) (ok "") (buildOverlay! env staged)))]
      (mt ov
        ((err e) (err (str "exec:" e)))
        ((ok overlay)
          (let [(argv (list env.host verb (relOf env path)))
                (r (runArgv! argv (some (if (stringEmpty? overlay) env.root overlay)) (none) (* timeoutS 1000) 0))
                (gone (if (stringEmpty? overlay) (ok ()) (pathRemove overlay)))
                (roots (list overlay (if (stringEmpty? overlay) "" (resultOr (realPath overlay) overlay)) env.root))]
            (cond
              ((not (stringEmpty? r.failure)) (err (str "exec:" (osErrorText r.failure env.host))))
              (r.timedOut (err (str "exec:" (timeoutText argv timeoutS))))
              (else (ok (HostRun :code r.code :out (stringTrim (unroot r.out roots)) :errText (stringTrim (unroot r.errText roots)) :source (if (stringEmpty? overlay) ":disk" ":staged"))))))))))

fn hostAbsent -> String
  "the stage-0 host is absent at asl/host/out/asl-host; build it with sh asl/host/build.sh or set ASL_HOST"

fn hostCheckOnce! env: GateEnv overlay: String target: String path: String text: String -> (Pair String String)
  (do (fileWrite target text)
      (let [(r (runArgv! (list env.host "check" (relOf env path)) (some overlay) (none) 15000 0))]
        (cond
          ((not (stringEmpty? r.failure)) (pair "skipped" (str "asl-host check did not run: " (osErrorText r.failure env.host))))
          (r.timedOut (pair "skipped" "asl-host check timed out after 15s"))
          ((= r.code 0) (pair "ok" ""))
          (else
            (let [(out (stringJoin (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (list r.errText r.out)) "\n"))
                  (lines (strippedLines (unroot out (list overlay (resultOr (realPath overlay) overlay)))))]
              (pair "error" (pyTrunc (optionOr (listHead lines) (str "asl-host check exit " (stringFromInt64 r.code))) 300)))))))

fn aslHostCheck! env: GateEnv path: String after: String before: (Option String) -> (List String)
  (if (not (executable? env.host))
    (list "skipped" (str "stage-0 host absent at " env.host) "")
    (let [(others (filter (fn [(sp (Pair String String))] -> Bool (!= (pairFirst sp) path)) (writableStaged! env)))
          (self (listAppend others (mt (stagedContent env path) ((some c) (list (pair path c))) ((none) (list)))))]
      (mt (buildOverlay! env self)
        ((err e) (list "skipped" (str "asl-host check did not run: " e) ""))
        ((ok overlay)
          (let [(target (k/joinPath overlay (k/relPath path env.root)))
                (mk (dirCreate (k/dirName target)))
                (r1 (hostCheckOnce! env overlay target path after))
                (pre (if (and (= (pairFirst r1) "error") (some? before)) (pairFirst (hostCheckOnce! env overlay target path (optionOr before ""))) ""))
                (gone (pathRemove overlay))]
            (list (pairFirst r1) (pairSecond r1) pre))))))

fn validateStaged! env: GateEnv path: String before: (Option String) after: String force: Bool -> (List String)
  (let [(lang (syntaxLang! path after))]
    (if (or (= lang "asl") (= lang "asn"))
      (mt (aslDelimiterDiag after)
        ((none)
          (if (= lang "asn")
            (list "" "" " :balanced true")
            (let [(hc (aslHostCheck! env path after before))
                  (st (optionOr (listGet hc 0) ""))
                  (diag (optionOr (listGet hc 1) ""))
                  (pre (= (optionOr (listGet hc 2) "") "error"))
                  (chk " :checker \"asl-host\"")]
              (cond
                ((!= st "error") (list "" "" (str " :balanced true :syntax :" st chk (if (stringEmpty? diag) "" (str " :syntaxMessage " (q diag))))))
                ((or pre force) (list "" "" (str " :balanced true :syntax :error" chk (if pre " :preexisting true" " :forced true") " :syntaxMessage " (q diag))))
                (else (list ":ERR_CHECK_FAILED" diag (str " :balanced true :syntax :error" chk)))))))
        ((some d)
          (let [(pre (mt before ((some bt) (some? (aslDelimiterDiag bt))) ((none) false)))
                (detail (str " :byte " (stringFromInt64 d.byte) (if (stringEmpty? d.expected) "" (str " :expected " (q d.expected)))))]
            (if (or pre force)
              (list "" "" (str " :balanced false" detail (if pre " :preexisting true" " :forced true")))
              (list ":ERR_UNBALANCED" d.msg detail)))))
      (let [(fs (foreignSyntax! env path after))
            (st (pairFirst fs))
            (msg (pairSecond fs))
            (hostF (str (syntaxHost! path) (checkerField lang)))]
        (if (!= st "error")
          (list "" "" (str " :syntax :" st hostF (if (and (= st "skipped") (not (stringEmpty? msg)) (not (stringEmpty? (checkerName lang)))) (str " :syntaxMessage " (q msg)) "")))
          (let [(pre (mt before ((some bt) (= (pairFirst (foreignSyntax! env path bt)) "error")) ((none) false)))]
            (if (or pre force)
              (list "" "" (str " :syntax :error" hostF (if pre " :preexisting true" " :forced true") " :syntaxMessage " (q msg)))
              (list ":ERR_SYNTAX" msg (str " :syntax :error" hostF))))))))

fn fileArg kw: (Map String String) args: (List String) -> String
  (k/kwOr kw "file" (k/kwOr kw "path" (optionOr (listHead args) "")))

fn checkFile! env: GateEnv id: Int64 op: String raw: String resolved: String -> GateOutcome
  (let [(staged (stagedContent env resolved))
        (read (mt staged ((some c) (ok c)) ((none) (readText! resolved))))]
    (mt read
      ((err e) (rejectLine id op ":ERR_READ_FAILED" (msgTail e)))
      ((ok c)
        (let [(src (if (some? staged) ":staged" ":disk"))
              (lang (languageOf! resolved))
              (rel (k/escapeAsnVal (relOf env resolved)))
              (common (str " :file \"" rel "\" :language \"" lang "\" :source " src))]
          (if (not (or (= lang "asl") (= lang "asn")))
            (let [(fs (foreignSyntax! env resolved c))
                  (syn (pairFirst fs))]
              (if (= syn "error")
                (rejectLine id op ":ERR_SYNTAX" (str common " :syntax :error" (syntaxHost! resolved) (msgTail (pairSecond fs))))
                (okLine (str (head id op) " :status \"ok\"" common " :syntax :" syn " :checked " (if (= syn "ok") "true" "false")
                             " :skipped [:dyck1Purity :syntaxIntegrity] :message \"no ASL checks apply to " lang " sources\")"))))
            (let [(derr (aslDelimiterError c))]
              (cond
                ((not (stringEmpty? derr)) (rejectLine id op ":ERR_UNBALANCED_DELIMITERS" (str common (msgTail derr))))
                ((= lang "asn") (okLine (str (head id op) " :status \"ok\"" common " :valid true :balanced true)")))
                (else
                  (mt (runHost! env "check" resolved 300)
                    ((err e)
                      (if (= e "absent")
                        (rejectLine id op ":ERR_HOST_ABSENT" (str " :file \"" rel "\"" (msgTail (hostAbsent))))
                        (rejectLine id op ":ERR_READ_FAILED" (msgTail (sub e 5 (stringLength e))))))
                    ((ok h)
                      (let [(hc (str " :file \"" rel "\" :language \"" lang "\" :source " h.source))]
                        (if (= h.code 0)
                          (okLine (str (head id op) " :status \"ok\"" hc " :valid true :balanced true :checker \"asl-host\" :checkerExit 0" (msgTail h.out) ")"))
                          (let [(diag (stringJoin (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (list h.errText h.out)) "\n"))]
                            (rejectLine id op ":ERR_CHECK_FAILED" (str hc " :balanced true :checker \"asl-host\" :checkerExit " (stringFromInt64 h.code)
                                                                      (msgTail (if (stringEmpty? diag) "asl-host check failed" diag)))))))))))))))))

fn stagedFailure! env: GateEnv sp: (Pair String String) -> String
  (let [(p (pairFirst sp))
        (c (pairSecond sp))
        (e (if (or (= (languageOf! p) "asl") (= (languageOf! p) "asn"))
             (aslDelimiterError c)
             (let [(fs (foreignSyntax! env p c))] (if (= (pairFirst fs) "error") (pairSecond fs) ""))))]
    (if (stringEmpty? e) "" (str "(:file " (q (relOf env p)) " :message " (q e) ")")))

fn workspaceCheck! env: GateEnv cwd: String aslRoot: (Option String) -> (Pair Int64 String)
  (let [(bin (k/joinPath env.binDir "asl"))
        (r (runArgv! (list bin "check") (some cwd) (optionMap (fn [(v String)] -> (List String) (withEnv! "ASL_ROOT" v)) aslRoot) 300000 0))]
    (cond
      ((not (stringEmpty? r.failure)) (pair -1 (osErrorText r.failure bin)))
      (r.timedOut (pair -1 (timeoutText (list bin "check") 300)))
      (else (pair r.code (let [(e (stringTrim r.errText)) (o (stringTrim r.out))] (pyTrunc (cond ((not (stringEmpty? e)) e) ((not (stringEmpty? o)) o) (else "workspace check failed")) 400))))))

fn checkWorkspace! env: GateEnv id: Int64 op: String -> GateOutcome
  (let [(staged (writableStaged! env))]
    (if (listEmpty? staged)
      (let [(r (workspaceCheck! env env.root (none)))]
        (cond
          ((and (= (pairFirst r) -1) (stringStartsWith? (pairSecond r) "[Errno")) (rejectLine id op ":ERR_EXEC_FAILED" (msgTail (pairSecond r))))
          ((= (pairFirst r) 0) (okLine (str (head id op) " :status \"ok\" :scope \"workspace\" :valid true :checkerExit 0)")))
          (else (rejectLine id op ":ERR_WORKSPACE_CHECK_FAILED" (str " :checkerExit " (stringFromInt64 (pairFirst r)) (msgTail (pairSecond r)))))))
      (let [(bad (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map (fn [(sp (Pair String String))] -> String (stagedFailure! env sp)) staged)))
            (r (mt (buildOverlay! env staged)
                 ((err e) (pair -1 e))
                 ((ok ov) (let [(res (workspaceCheck! env ov (some ov)))] (do (pathRemove ov) res)))))
            (n (stringFromInt64 (listLength staged)))]
        (cond
          ((!= (pairFirst r) 0) (rejectLine id op ":ERR_WORKSPACE_CHECK_FAILED" (str " :source :staged :checkerExit " (stringFromInt64 (pairFirst r)) " :stagedFailures [" (stringJoin bad " ") "]" (msgTail (pairSecond r)))))
          ((not (listEmpty? bad)) (rejectLine id op ":ERR_STAGED_CHECK_FAILED" (str " :source :staged :checkerExit 0 :checkedFiles " n " :failures [" (stringJoin bad " ") "]")))
          (else (okLine (str (head id op) " :status \"ok\" :scope \"workspace\" :source :staged :valid true :checkerExit 0 :checkedFiles " n ")")))))))

fn checkStep! env: GateEnv id: Int64 op: String kw: (Map String String) args: (List String) -> GateOutcome
  (let [(raw (fileArg kw args))]
    (if (stringEmpty? raw)
      (checkWorkspace! env id op)
      (let [(res (k/resolveEditTarget! env.root raw))
            (resolved (pairFirst res))]
        (cond
          ((not (stringEmpty? (pairSecond res))) (rejectLine id op ":ERR_BOUNDARY_VIOLATION" (msgTail (pairSecond res))))
          ((or (k/isFile! resolved) (some? (stagedContent env resolved))) (checkFile! env id op raw resolved))
          (else (rejectLine id op ":ERR_FILE_NOT_FOUND" (msgTail (str "Cannot verify a target that does not exist: " raw))))))))

fn digitsBack b: Bytes i: Int64 -> Int64
  (if (and (>= i 0) (digit? (bytesGet b i))) (digitsBack b (- i 1)) (+ i 1))

fn spaceBack b: Bytes i: Int64 -> Int64
  (if (and (>= i 0) (spaceByte? (bytesGet b i))) (spaceBack b (- i 1)) i)

fn countBefore text: String word: String from: Int64 -> (Option Int64)
  (mt (stringIndexOf (sub text from (stringLength text)) word)
    ((none) (none))
    ((some rel)
      (let [(at (+ from rel))
            (b (stringToBytes text))
            (ws (spaceBack b (- at 1)))
            (ds (digitsBack b ws))]
        (if (and (< ws (- at 1)) (<= ds ws) (>= ws 0))
          (stringToInt64 (sub text ds (+ ws 1)))
          (countBefore text word (+ at 1))))))

fn digitsFwd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (digit? (bytesGet b i))) (digitsFwd b n (+ i 1)) i)

fn afterAsserts text: String from: Int64 -> String
  (mt (stringIndexOf (sub text from (stringLength text)) "after ")
    ((none) "")
    ((some rel)
      (let [(at (+ from rel 6))
            (e (digitsFwd (stringToBytes text) (stringLength text) at))]
        (if (and (> e at) (stringStartsWith? (sub text e (stringLength text)) " assert"))
          (sub text at e)
          (afterAsserts text (+ from rel 1))))))

fn testStep! env: GateEnv id: Int64 kw: (Map String String) args: (List String) -> GateOutcome
  (let [(raw (fileArg kw args))]
    (if (stringEmpty? raw)
      (rejectLine id "test" ":ERR_MISSING_ARG" " :message \"Missing file argument\"")
      (let [(res (k/resolveEditTarget! env.root raw))
            (resolved (pairFirst res))]
        (cond
          ((not (stringEmpty? (pairSecond res))) (rejectLine id "test" ":ERR_EXEC_FAILED" (msgTail (pairSecond res))))
          ((and (not (k/isFile! resolved)) (none? (stagedContent env resolved))) (rejectLine id "test" ":ERR_EXEC_FAILED" (msgTail (str "test file not found: " raw))))
          (else
            (mt (runHost! env "test" resolved 120)
              ((err e)
                (if (= e "absent")
                  (rejectLine id "test" ":ERR_HOST_ABSENT" (msgTail (hostAbsent)))
                  (rejectLine id "test" ":ERR_EXEC_FAILED" (msgTail (sub e 5 (stringLength e))))))
              ((ok h)
                (let [(asserts (countBefore h.out "assertion(s)" 0))
                      (refutes (countBefore h.out "refutation(s)" 0))
                      (after (afterAsserts (str h.out "\n" h.errText) 0))
                      (file (k/escapeAsnVal raw))]
                  (cond
                    ((!= h.code 0)
                      (let [(diag (stringJoin (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (list h.errText h.out)) "\n"))]
                        (rejectLine id "test" ":ERR_TEST_FAILED" (str " :file \"" file "\" :source " h.source " :runner \"asl-host\" :exit " (stringFromInt64 h.code)
                                                                    (if (stringEmpty? after) "" (str " :assertCount " after)) (msgTail (if (stringEmpty? diag) "Test failed" diag))))))
                    ((none? asserts) (rejectLine id "test" ":ERR_UNPARSEABLE_ASSERT_COUNT" " :runner \"asl-host\" :message \"Runner exited 0 but emitted no executed-assertion count; non-vacuity unverifiable\""))
                    ((<= (+ (optionOr asserts 0) (optionOr refutes 0)) 0) (rejectLine id "test" ":ERR_VACUOUS_PASS" " :runner \"asl-host\" :message \"Test exited 0 with zero executed assertions; vacuous pass rejected\""))
                    (else
                      (let [(a (stringFromInt64 (optionOr asserts 0)))
                            (r (stringFromInt64 (optionOr refutes 0)))]
                        (okLine (str (head id "test") " :status \"ok\" :file \"" file "\" :source " h.source " :runner \"asl-host\" :passed true :assertCount " a " :refuteCount " r
                                     " :receipt (:testReceipt :file \"" file "\" :status :passed :assertCount " a " :refuteCount " r "))")))))))))))))

fn kwLower kw: (Map String String) key: String -> String
  (k/lstripColons (stringLower (optionOr (mapGet kw key) "")))

fn truthy? v: String -> Bool
  (listContains? (list "true" ":true" "1") (stringLower v))

fn heuristicTier? kw: (Map String String) key: String -> Bool
  (or (= (kwLower kw key) "heuristic") (truthy? (optionOr (mapGet kw "heuristic") "")))

fn heuristicAllowed? kw: (Map String String) key: String -> Bool
  (or (listContains? (list "indentation" "heuristic") (kwLower kw key)) (truthy? (optionOr (mapGet kw "indentation") "")) (heuristicTier? kw key))

fn fixStep! env: GateEnv id: Int64 kw: (Map String String) args: (List String) -> GateOutcome
  (let [(raw (fileArg kw args))
        (res (if (stringEmpty? raw) (pair "" "Missing file argument") (k/resolveEditTarget! env.root raw)))
        (path (pairFirst res))
        (apply (listContains? (list "true" "1" "indentation" "heuristic") (kwLower kw "apply")))]
    (cond
      ((not (stringEmpty? (pairSecond res))) (rejectLine id "fix" (if (stringEmpty? raw) ":ERR_MISSING_ARG" ":ERR_BOUNDARY_VIOLATION") (msgTail (pairSecond res))))
      ((not (or (= (languageOf! path) "asl") (= (languageOf! path) "asn")))
        (rejectLine id "fix" ":ERR_UNSUPPORTED_LANGUAGE" (str " :file " (q (relOf env path)) " :language \"" (languageOf! path) "\" :message \"delimiter repair applies to ASL and ASN only\"")))
      ((and (not (k/isFile! path)) (none? (stagedContent env path))) (rejectLine id "fix" ":ERR_FILE_NOT_FOUND" (msgTail (str "File not found: " raw))))
      (else
        (let [(staged (stagedContent env path))
              (read (mt staged ((some c) (ok c)) ((none) (readText! path))))]
          (mt read
            ((err e) (rejectLine id "fix" ":ERR_READ_FAILED" (msgTail e)))
            ((ok text)
              (let [(src (if (some? staged) ":staged" ":disk"))
                    (rel (relOf env path))
                    (fileF (str " :file " (q rel) " :source " src))
                    (fault (k/escapeAsnVal (aslDelimiterError text)))
                    (run (aslRepair text (heuristicTier? kw "apply")))
                    (status run.status)
                    (basis run.basis)]
                (cond
                  ((= status "none") (okLine (str (head id "fix") " :status \"ok\"" fileF " :balanced true :repair (:none) :staged false)")))
                  ((= status "unique")
                    (let [(patch (stringJoin (e/unifiedDiff! (pySplitLines text true) (pySplitLines run.text true) (str "current/" rel) (str "repaired/" rel) 1) ""))
                          (stage (and apply (or (= basis "structural") (heuristicAllowed? kw "apply"))))
                          (rej (stringJoin (map (fn [(r Repair)] -> String (repairAsn (some r))) run.rejected) " "))
                          (basisF (str " :basis :" basis (rankAsn run.repair) (if (or (= basis "indentation") (= basis "heuristic")) (str " :rejected [" rej "]") "")))
                          (note (if (and apply (not stage)) " :message \"indentation-based repair; pass :apply :indentation to stage it\"" ""))]
                      (GateOutcome :lines (list (str (head id "fix") " :status \"ok\"" fileF " :fault \"" fault "\" :repair " (repairAsn run.repair) basisF " :staged " (if stage "true" "false") note " :patch " (q patch) ")"))
                                   :errCount 0
                                   :stage (if stage (some (pair path run.text)) (none)))))
                  ((= status "ambiguous")
                    (rejectLine id "fix" ":ERR_AMBIGUOUS_REPAIR" (str fileF " :fault \"" fault "\" :candidates [" (stringJoin (map stringFromInt64 run.candidates) " ")
                                                                    "] :message \"more than one structurally distinct minimal edit balances the file and indentation does not single one out; edit it at one of the candidate byte offsets\"")))
                  (else (rejectLine id "fix" ":ERR_UNREPAIRABLE" (str fileF " :fault \"" fault "\" :message \"no single minimal delimiter edit balances the file\"")))))))))))

(schema CapRow (:f id String) (:f status String) (:f probe (Option String)) (:f expect String) (:f end Int64))

fn wordEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (let [(c (bytesGet b i))] (or (digit? c) (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (= c 95)))) (wordEnd b n (+ i 1)) i)

fn asnStrEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) -1) ((= (bytesGet b i) 34) i) ((= (bytesGet b i) 92) (if (< (+ i 1) n) (asnStrEnd b n (+ i 2)) -1)) (else (asnStrEnd b n (+ i 1))))

fn lit? text: String i: Int64 s: String -> Bool
  (= (sub text i (+ i (stringLength s))) s)

fn probePart text: String b: Bytes n: Int64 i: Int64 -> (Option (List Int64))
  (if (lit? text i " :probe \"")
    (let [(ps (+ i 9)) (pe (asnStrEnd b n ps))]
      (if (and (>= pe 0) (lit? text pe "\" :expect \""))
        (let [(es (+ pe 12)) (ee (asnStrEnd b n es))]
          (if (>= ee 0) (some (list ps pe es ee)) (none)))
        (none)))
    (none))

fn capAt text: String b: Bytes n: Int64 i: Int64 -> (Option CapRow)
  (let [(ids (+ i 9)) (ide (wordEnd b n ids))]
    (if (and (> ide ids) (lit? text ide " :use \""))
      (let [(ue (asnStrEnd b n (+ ide 7)))]
        (if (and (>= ue 0) (lit? text ue "\" :status :"))
          (let [(ss (+ ue 11)) (se (wordEnd b n ss))]
            (if (> se ss)
              (mt (probePart text b n se)
                ((some p) (some (CapRow :id (sub text ids ide) :status (sub text ss se) :probe (some (k/asnUnescape (sub text (optionOr (listGet p 0) 0) (optionOr (listGet p 1) 0))))
                                         :expect (k/asnUnescape (sub text (optionOr (listGet p 2) 0) (optionOr (listGet p 3) 0))) :end (+ (optionOr (listGet p 3) 0) 1))))
                ((none) (some (CapRow :id (sub text ids ide) :status (sub text ss se) :probe (none) :expect "" :end se))))
              (none)))
          (none)))
      (none)))

fn capRows text: String b: Bytes n: Int64 from: Int64 acc: (List CapRow) -> (List CapRow)
  (mt (stringIndexOf (sub text from n) ":cap :id ")
    ((none) (listReverse acc))
    ((some rel)
      (let [(i (+ from rel))]
        (mt (capAt text b n i)
          ((some row) (capRows text b n row.end (cons row acc)))
          ((none) (capRows text b n (+ i 1) acc))))))

fn readOnlyOp? op: String kw: (Map String String) -> Bool
  (cond
    ((= op "note") (listContains? (list "list" "query") (k/lstripColons (k/kwOr kw "action" "list"))))
    ((= op "fix") (not (listContains? (list "true" "1" "indentation" "heuristic") (kwLower kw "apply"))))
    ((= op "doctor") (not (listContains? (list "true" "1") (k/lstripColons (optionOr (mapGet kw "write") "")))))
    (else (listContains? (list "echo" "read" "query" "q" "tree" "observe" "diff" "check" "chk" "gate" "test" "tools" "help" "intel" "doctor" "ping" "where" "search" "research" "crawl" "lens" "preflush") op)))

fn gateOp? op: String -> Bool
  (listContains? (list "check" "chk" "gate" "test" "fix" "doctor" "audit") op)

fn quotedEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) -1) ((= (bytesGet b i) 34) (+ i 1)) ((= (bytesGet b i) 92) (quotedEnd b n (+ i 2))) (else (quotedEnd b n (+ i 1))))

fn fieldsThenStatus text: String b: Bytes n: Int64 i: Int64 -> Bool
  (cond
    ((lit? text i " :status \"rejected\"") true)
    ((and (lit? text i " :") (not (lit? text i " :status")))
      (let [(ke (runEnd b n (+ i 2) (fn [(c Int64)] -> Bool (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (= c 45)))))]
        (if (and (> ke (+ i 2)) (lit? text ke " \""))
          (let [(e (quotedEnd b n (+ ke 2)))] (and (>= e 0) (fieldsThenStatus text b n e)))
          false)))
    (else false))

fn stepRejected? line: String -> Bool
  (let [(b (stringToBytes line))
        (n (stringLength line))
        (s (runEnd b n 0 spaceByte?))
        (p (str "(:step :id "))]
    (and (lit? line s p)
         (let [(de (digitsFwd b n (+ s 11)))]
           (and (> de (+ s 11)) (lit? line de " :op \"")
                (let [(oe (quotedEnd b n (+ de 6)))] (and (>= oe 0) (fieldsThenStatus line b n oe)))))))

fn linesFailed? lines: (List String) errs: Int64 -> Bool
  (or (> errs 0) (listAny? stepRejected? lines))

fn binaryProbe! env: GateEnv name: String path: String -> (Pair Bool String)
  (let [(cp (if (stringStartsWith? path "/") path (k/joinPath env.binDir path)))
        (present (executable? cp))]
    (pair present (str "(:capability :id \"" name "\" :binary " (q path) " :status " (if present ":present" ":absent") ")")))

fn entryProbe! env: GateEnv name: String rel: String -> (Pair Bool String)
  (let [(present (mt (fileStat (k/aslPath! env.rootDir (if (stringStartsWith? rel "asl/") (optionOr (stringSlice rel 4 (stringLength rel)) rel) rel))) ((ok st) st.isFile) ((err _) false)))]
    (pair present (str "(:capability :id \"" name "\" :binary " (q rel) " :status " (if present ":present" ":absent") ")")))

fn remoteCount! env: GateEnv -> (Result Int64 String)
  (let [(git (whichTool! "git"))]
    (if (stringEmpty? git)
      (err "git not found on PATH")
      (let [(r (runArgv! (list git "remote") (some env.rootDir) (none) 60000 0))]
        (cond
          ((not (stringEmpty? r.failure)) (err (osErrorText r.failure git)))
          (r.timedOut (err "git remote timed out after 60s"))
          (else (ok (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (pySplitLines r.out false)))))))))

fn probeRow run: (fn [Int64 String] -> (Pair (List String) Int64)) row: CapRow -> (List String)
  (mt row.probe
    ((none) (list row.id row.status "false" ""))
    ((some form)
      (let [(parsed (k/parseStep form))]
        (if (not (readOnlyOp? parsed.op parsed.kwargs))
          (list row.id "absent" "true"
                (str "(:capability :id \"" row.id "\" :declared :" row.status " :measured :absent :reason \"" (k/escapeAsnVal parsed.op) " is not a read-only op\"" (if (= "absent" row.status) "" " :mismatch true") ")"))
          (let [(out (run 0 form))
                (okProbe (and (= (pairSecond out) 0) (not (linesFailed? (pairFirst out) (pairSecond out))) (stringContains? (stringJoin (pairFirst out) "\n") row.expect)))
                (measured (if okProbe "works" "absent"))]
            (list row.id measured "true"
                  (str "(:capability :id \"" row.id "\" :declared :" row.status " :measured :" measured (if (= measured row.status) "" " :mismatch true") ")")))))))

fn lockCounts rows: (List (List String)) -> String
  (let [(sts (listSort (map (fn [(r (List String))] -> String (optionOr (listGet r 1) "")) rows)))
        (uniq (fold (fn [(acc (List String)) (s String)] -> (List String) (if (listContains? acc s) acc (listAppend acc (list s)))) (list) sts))]
    (stringJoin (map (fn [(s String)] -> String (str " :" s " " (stringFromInt64 (listLength (filter (fn [(x String)] -> Bool (= x s)) sts))))) uniq) ""))

fn writeLock! env: GateEnv rows: (List (List String)) -> (Result String String)
  (let [(body (stringJoin (map (fn [(r (List String))] -> String (str "    (:cap :id \"" (optionOr (listGet r 0) "") "\" :status :" (optionOr (listGet r 1) "") " :probed " (optionOr (listGet r 2) "") ")\n")) rows) ""))
        (text (str "(:capabilitiesLock\n  :version \"1.1.0\"\n  :source \"asl/grammar/capabilities.asn\"\n  :measuredBy \"(:doctor :write true)\"\n  :measuredAt " (stringFromInt64 (/ (nowNs) 1000000))
                   "\n  :summary (:total " (stringFromInt64 (listLength rows)) (lockCounts rows) ")\n  :capabilities (\n" body "  ))\n"))
        (lockPath (k/aslPath! env.rootDir "grammar/capabilities.lock"))]
    (mt (fileWrite (str lockPath ".tmp") text)
      ((err e) (err e))
      ((ok _) (mt (pathRename (str lockPath ".tmp") lockPath) ((ok _) (ok lockPath)) ((err e) (err e))))))

fn doctorStep! env: GateEnv run: (fn [Int64 String] -> (Pair (List String) Int64)) id: Int64 kw: (Map String String) args: (List String) -> GateOutcome
  (let [(bins (list (binaryProbe! env "host" env.host) (binaryProbe! env "intel" "asl") (entryProbe! env "engine" "asl/packages/asl-engine/src/cli.asl") (binaryProbe! env "lens" "lens")))
        (remotes (remoteCount! env))
        (remoteProbe (mt remotes
                       ((ok n) (str "(:capability :id \"zeroRemote\" :remotesCount " (stringFromInt64 n) " :status " (if (= n 0) ":pass" ":fail") ")"))
                       ((err e) (str "(:capability :id \"zeroRemote\" :status :absent :error ERR_TOOL_ABSENT :message " (q e) ")"))))
        (vfsProbe (str "(:capability :id \"ramVfs\" :stagedFiles " (stringFromInt64 (listLength env.staged)) " :status :measured)"))
        (capText (fileReadString (k/aslPath! env.rootDir "grammar/capabilities.asn")))
        (text (resultOr capText ""))
        (rows (capRows text (stringToBytes text) (stringLength text) 0 (list)))
        (measured (map (fn [(r CapRow)] -> (List String) (probeRow run r)) rows))
        (unprobed (listLength (filter (fn [(r CapRow)] -> Bool (none? r.probe)) rows)))
        (mismatch (listAny? (fn [(p (Pair CapRow (List String)))] -> Bool (and (some? (pairFirst p).probe) (!= (optionOr (listGet (pairSecond p) 1) "") (pairFirst p).status))) (zip rows measured)))
        (wantLock (and (listContains? (list "true" "1") (k/lstripColons (optionOr (mapGet kw "write") ""))) (not (listEmpty? measured))))
        (lock (if wantLock (writeLock! env measured) (ok "")))
        (lockOk (mt lock ((ok _) true) ((err _) false)))
        (healthy (and (listAll? pairFirst bins) (= (resultOr remotes 1) 0) (resultOr (resultMap capText (fn [(t String)] -> Bool true)) false) (not mismatch)
                      lockOk))
        (probes (listAppend (listAppend (map pairSecond bins) (list remoteProbe vfsProbe))
                            (listAppend (listAppend (if (resultOr (resultMap capText (fn [(t String)] -> Bool true)) false) (list) (list "(:capability :id \"registry\" :status :absent :file \"asl/grammar/capabilities.asn\")"))
                                                    (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map (fn [(m (List String))] -> String (optionOr (listGet m 3) "")) measured)))
                                        (listAppend (list (str "(:capability :id \"unprobed\" :count " (stringFromInt64 unprobed) " :status :declaredOnly)"))
                                                    (mt lock
                                                      ((ok _) (if wantLock (list (str "(:capability :id \"lock\" :written \"asl/grammar/capabilities.lock\" :entries " (stringFromInt64 (listLength measured)) ")")) (list)))
                                                      ((err e) (list (str "(:capability :id \"lock\" :status :failed :error ERR_WRITE_FAILED :message " (q e) ")"))))))))]
    (GateOutcome :lines (list (str (head id "doctor") " :status \"" (if healthy "ok" "rejected") "\" :health " (if healthy ":nominal" ":degraded") " :probes [" (stringJoin probes " ") "])"))
                 :errCount (if healthy 0 1)
                 :stage (none)))

fn pyIntOr raw: String fallback: Int64 -> Int64
  (let [(t (stringTrim raw))
        (sign (if (or (stringStartsWith? t "-") (stringStartsWith? t "+")) (sub t 0 1) ""))
        (body (sub t (stringLength sign) (stringLength t)))
        (parts (stringSplit body "_"))]
    (if (and (not (stringEmpty? body)) (listAll? (fn [(p String)] -> Bool (and (not (stringEmpty? p)) (listAll? (fn [(c String)] -> Bool (digit? (charCode c))) (stringChars p)))) parts))
      (optionOr (stringToInt64 (str (if (= sign "-") "-" "") (stringReplace body "_" ""))) fallback)
      fallback))

fn auditLines out: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:audit ")) (pySplitLines out false))

fn auditStep! env: GateEnv id: Int64 kw: (Map String String) args: (List String) -> GateOutcome
  (let [(sub0 (k/kwOr kw "subcmd" (k/kwOr kw "action" (optionOr (listHead args) "consistency"))))
        (subcmd (k/lstripColons sub0))
        (sc (k/escapeAsnVal subcmd))
        (bin (k/joinPath env.binDir "asl"))
        (timeoutS (max 1 (pyIntOr (envOr! "ASL_AUDIT_TIMEOUT_S" "300") 300)))
        (full (listContains? (list "true" "True" "1") (k/lstripColons (optionOr (mapGet kw "full") ""))))
        (asn (listContains? (list "vitality" "full" "all" "system" "stubs" "graph" "complexity" "coupling" "vacuity" "deadcode") subcmd))
        (intelSub (listContains? (list "coupling" "deadcode" "vacuity" "sweep" "graph" "complexity" "stubs" "trace") subcmd))
        (workspaceSub (listContains? (list "consistency" "gates" "closure" "foreign" "steps" "vitality" "full" "all" "system") subcmd))
        (argv (if intelSub
                (listAppend (list bin "intel" subcmd) (if (or asn (= subcmd "trace")) (list "--asn") (list)))
                (listAppend (list bin "audit" subcmd) (listAppend (if full (list "--full") (list)) (if asn (list "--asn") (list))))))
        (r (if (or intelSub workspaceSub) (runArgv! argv (some env.rootDir) (none) (* timeoutS 1000) 15000) (RunOut :code 1 :out "" :errText "" :timedOut false :failure "")))]
    (cond
      ((and workspaceSub (not (fileExists? (k/joinPath env.rootDir "scripts/audit/audit.py"))))
        (rejectLine id "audit" ":ERR_WORKSPACE_ONLY" (str " :subcmd \"" sc "\" :message \"" sc " runs the workspace's scripts/audit/audit.py, which this checkout does not have; asl-intel audits here: coupling deadcode vacuity sweep graph complexity stubs trace\"")))
      ((and (not intelSub) (not workspaceSub)) (rejectLine id "audit" ":ERR_UNKNOWN_SUBCMD" (str " :subcmd \"" sc "\" :message \"known: coupling deadcode vacuity sweep graph complexity stubs trace (asl-intel); consistency gates closure foreign steps vitality full all system (the workspace audit)\"")))
      ((not (stringEmpty? r.failure)) (rejectLine id "audit" ":ERR_EXEC_FAILED" (msgTail (osErrorText r.failure bin))))
      (r.timedOut (rejectLine id "audit" ":ERR_TIMEOUT" (str " :subcmd \"" sc "\" :receipt (:audit :sub " sc " :status :failed :err ERR_TIMEOUT :timeoutS " (stringFromInt64 timeoutS) ")")))
      (else
        (let [(receipt (optionOr (listLast (auditLines r.out)) ""))]
          (cond
            ((= r.code 0)
              (cond
                ((not (stringEmpty? receipt)) (okLine (str (head id "audit") " :status \"ok\" :subcmd \"" sc "\" :receipt " receipt ")")))
                ((not (stringEmpty? (stringTrim r.out))) (okLine (str (head id "audit") " :status \"ok\" :subcmd \"" sc "\" :receipt\n" (stringTrim r.out) ")")))
                (else (okLine (str (head id "audit") " :status \"ok\" :receipt (:auditReceipt :subcmd \"" sc "\" :status :passed :exitCode 0))")))))
            ((stringContains? receipt ":status :pending")
              (badLine (str (head id "audit") " :status \"pending\" :error-code \":ERR_PENDING\" :subcmd \"" sc "\" :receipt " receipt ")")))
            (else
              (let [(e (stringTrim r.errText))
                    (o (stringTrim r.out))
                    (body (if (stringEmpty? receipt)
                            (str "(:auditReceipt :subcmd \"" sc "\" :status :failed :exitCode " (stringFromInt64 r.code) " :message " (q (pyTail (cond ((not (stringEmpty? e)) e) ((not (stringEmpty? o)) o) (else "audit failed")) 400)) ")")
                            receipt))]
                (rejectLine id "audit" ":ERR_AUDIT_FAILED" (str " :subcmd \"" sc "\" :exitCode " (stringFromInt64 r.code) " :receipt " body)))))))))

fn runGate! env: GateEnv run: (fn [Int64 String] -> (Pair (List String) Int64)) id: Int64 op: String kw: (Map String String) args: (List String) -> GateOutcome
  (cond
    ((or (= op "check") (= op "chk") (= op "gate")) (checkStep! env id op kw args))
    ((= op "test") (testStep! env id kw args))
    ((= op "fix") (fixStep! env id kw args))
    ((= op "doctor") (doctorStep! env run id kw args))
    ((= op "audit") (auditStep! env id kw args))
    (else (rejectLine id op ":ERR_NOT_PORTED" " :message \"Operation not implemented\"")))
