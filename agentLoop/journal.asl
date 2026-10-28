(module asl/agentLoop/journal
  :x [Snapshot Written AsnNode Layer
      harnessLayers buildSystemPrompt retainJournal journalWrite snapshotBeforeWrite patchLines filePatch!
      applyResumePatch handBack writtenField handBackFields
      newWritten idleWritten git! asnRead asnReadOne pathNorm pathRel pathJoin pathDirname splitExt loadEffects]
  :i [(asl/agentLoop/core :a c) (asl/agentLoop/diff :a d) (asl-proc/coreProcess :a cp) (asl-proc/runnerBin :a rb) (asl-harness/launch :a lh) (asl/agentLoop/grounding :a gr)])

(schema Snapshot
  (:f bytes (Option String))
  (:f mode (Option Int64))
  (:f dirs (List String)))

(schema Written
  (:f root String)
  (:f files (Option (List (Pair String Snapshot))))
  (:f startHead (Option String)))

enum AsnNode
  (asnKw name: String)
  (asnSym text: String)
  (asnStr text: String)
  (asnNum text: String)
  (asnForm items: (List AsnNode))

fn newWritten root: String startHead: (Option String) -> Written
  (Written :root root :files (some (list)) :startHead startHead)

fn idleWritten root: String -> Written
  (Written :root root :files none :startHead none)

fn sl s: String i: Int64 j: Int64 -> String
  (let [n (stringLength s)
        a (max 0 (min i n))
        b (max a (min j n))]
    (optionOr (stringSlice s a b) ""))

fn ch s: String i: Int64 -> String
  (sl s i (+ i 1))

fn isSpaceByte x: String -> Bool
  (or (= x " ") (or (and (>= x "\t") (<= x "\r")) (and (>= x "\u{1c}") (<= x "\u{1f}"))))

fn isWord x: String -> Bool
  (or (and (>= x "0") (<= x "9"))
    (or (and (>= x "a") (<= x "z"))
      (or (and (>= x "A") (<= x "Z"))
        (or (= x "_") (>= x (sl "À" 0 1))))))

fn leftEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isSpaceByte (ch s i))) (leftEnd s (+ i 1) n) i)

fn rightEnd s: String lo: Int64 j: Int64 -> Int64
  (if (and (> j lo) (isSpaceByte (ch s (- j 1)))) (rightEnd s lo (- j 1)) j)

fn pyStrip s: String -> String
  (let [n (stringLength s)
        a (leftEnd s 0 n)]
    (sl s a (rightEnd s a n)))

fn lastIndex s: String t: String i: Int64 -> Int64
  (cond
    ((< i 0) -1)
    ((= (sl s i (+ i (stringLength t))) t) i)
    (else (lastIndex s t (- i 1))))

fn rfind s: String t: String -> Int64
  (lastIndex s t (- (stringLength s) (stringLength t)))

fn escapeAsn s: String -> String
  (c/escapeAsn s)

fn quoteList xs: (List String) -> String
  (c/joinSep (map (fn [p] (str "\"" (escapeAsn p) "\"")) xs) " ")

fn writtenField written: (List String) -> String
  (if (listEmpty? written) "" (str " :written (" (quoteList written) ")"))

fn handBackFields patch: (Option String) restored: (List String) -> String
  (match patch
    ((none) "")
    ((some p)
      (if (stringEmpty? p)
        ""
        (str " :patch \"" (escapeAsn p) "\"" (if (listEmpty? restored) "" (str " :restored (" (quoteList restored) ")"))))))

fn pathJoin a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn allSlashes s: String -> Bool
  (= (stringReplace s "/" "") "")

fn trimSlashes s: String -> String
  (if (stringEndsWith? s "/") (trimSlashes (sl s 0 (- (stringLength s) 1))) s)

fn pathDirname p: String -> String
  (let [head (sl p 0 (+ (rfind p "/") 1))]
    (if (and (not (stringEmpty? head)) (not (allSlashes head))) (trimSlashes head) head))

fn pathBasename p: String -> String
  (sl p (+ (rfind p "/") 1) (stringLength p))

fn leadingSlashes p: String i: Int64 -> Int64
  (if (= (ch p i) "/") (leadingSlashes p (+ i 1)) i)

fn normComps comps: (List String) initial: Int64 acc: (List String) -> (List String)
  (if (listEmpty? comps)
    (listReverse acc)
    (let [comp (c/firstOf comps)
          rest (c/restOf comps)]
      (cond
        ((or (= comp "") (= comp ".")) (normComps rest initial acc))
        ((or (not (= comp ".."))
             (or (and (= initial 0) (listEmpty? acc))
                 (and (not (listEmpty? acc)) (= (c/firstOf acc) ".."))))
          (normComps rest initial (cons comp acc)))
        ((not (listEmpty? acc)) (normComps rest initial (c/restOf acc)))
        (else (normComps rest initial acc)))))

fn pathNorm p: String -> String
  (if (stringEmpty? p)
    "."
    (let [k (leadingSlashes p 0)
          initial (if (= k 2) 2 (if (> k 0) 1 0))
          body (c/joinSep (normComps (stringSplit p "/") initial (list)) "/")
          out (str (stringRepeat "/" initial) body)]
      (if (stringEmpty? out) "." out)))

fn ! cwd! -> String
  (resultOr (realPath ".") ".")

fn ! pathAbs! p: String -> String
  (pathNorm (if (stringStartsWith? p "/") p (pathJoin (cwd!) p)))

fn commonCount a: (List String) b: (List String) k: Int64 -> Int64
  (if (or (listEmpty? a) (or (listEmpty? b) (not (= (c/firstOf a) (c/firstOf b)))))
    k
    (commonCount (c/restOf a) (c/restOf b) (+ k 1)))

fn nonEmpty xs: (List String) -> (List String)
  (filter (fn [x] (not (stringEmpty? x))) xs)

fn ! pathRel path: String start: String -> String
  (let [sl (nonEmpty (stringSplit (pathAbs! start) "/"))
        pl (nonEmpty (stringSplit (pathAbs! path) "/"))
        i (commonCount sl pl 0)
        parts (listAppend (map (fn [_] "..") (listDrop sl i)) (listDrop pl i))]
    (if (listEmpty? parts) "." (c/joinSep parts "/")))

fn extFrom p: String k: Int64 dot: Int64 -> String
  (cond
    ((>= k dot) p)
    ((not (= (ch p k) ".")) (sl p 0 dot))
    (else (extFrom p (+ k 1) dot)))

fn splitExt p: String -> String
  (let [sep (rfind p "/")
        dot (rfind p ".")]
    (if (> dot sep) (extFrom p (+ sep 1) dot) p))

fn ! statOf p: String -> (Option FileStat)
  (resultToOption (fileStat p))

fn ! isFile? p: String -> Bool
  (match (statOf p) ((some st) st.isFile) ((none) false))

fn ! isDir? p: String -> Bool
  (match (statOf p) ((some st) st.isDir) ((none) false))

fn ! exists? p: String -> Bool
  (some? (statOf p))

fn errKind msg: String -> String
  (match (stringIndexOf msg ":") ((some i) (sl msg 0 i)) ((none) msg))

fn pyQuote s: String -> String
  (str "'" (stringReplace (stringReplace s "\\" "\\\\") "'" "\\'") "'")

fn osError kind: String path: String -> String
  (cond
    ((= kind "notFound") (str "FileNotFoundError: [Errno 2] No such file or directory: " (pyQuote path)))
    ((= kind "permission") (str "PermissionError: [Errno 13] Permission denied: " (pyQuote path)))
    ((= kind "io:21") (str "IsADirectoryError: [Errno 21] Is a directory: " (pyQuote path)))
    ((= kind "io:20") (str "NotADirectoryError: [Errno 20] Not a directory: " (pyQuote path)))
    ((= kind "io:17") (str "FileExistsError: [Errno 17] File exists: " (pyQuote path)))
    (else (str "OSError: " kind ": " (pyQuote path))))

fn ! readText! p: String -> (Result String String)
  (match (fileReadString p)
    ((ok t) (ok t))
    ((err e) (err (osError (errKind e) p))))

fn ! writeText! p: String t: String -> (Result Int64 String)
  (match (fileWrite p t)
    ((ok _) (ok 0))
    ((err e) (err (osError (errKind e) p))))

fn ! firstMissing p: String -> String
  (let [up (pathDirname p)]
    (if (or (= up p) (exists? up)) p (firstMissing up)))

fn ! makeDirs! p: String -> (Result Int64 String)
  (cond
    ((isDir? p) (ok 0))
    ((exists? p) (err (osError "io:17" p)))
    (else
      (let [first (firstMissing p)
            parent (pathDirname first)]
        (if (and (not (= parent first)) (not (isDir? parent)))
          (err (osError "io:20" first))
          (match (dirCreate p)
            ((ok _) (ok 0))
            ((err e) (err (osError (errKind e) first))))))))

fn procError tool: String e: cp/ProcessError -> String
  (match e
    ((cp/notFound _) (str "FileNotFoundError: [Errno 2] No such file or directory: " (pyQuote tool)))
    ((cp/permissionDenied _) (str "PermissionError: [Errno 13] Permission denied: " (pyQuote tool)))
    ((cp/timeout ms) (str "TimeoutExpired: " tool " timed out after " (stringFromInt64 ms) " ms"))
    ((cp/executionFailed code msg) (str "OSError: " tool ": " msg)))

fn ! run! tool: String args: (List String) cwd: String -> (Result cp/ProcessOutput String)
  (match (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd tool args) cwd) 120000))
    ((ok o) (ok o))
    ((err e) (err (procError tool e))))

fn ! git! cwd: String args: (List String) -> (Result cp/ProcessOutput String)
  (run! "git" args cwd)

fn octal m: Int64 acc: String -> String
  (if (= m 0) (if (stringEmpty? acc) "0" acc) (octal (/ m 8) (str (stringFromInt64 (mod m 8)) acc)))

fn ! chmod! p: String mode: Int64 -> (Result Int64 String)
  (match (statOf p)
    ((some st)
      (if (= (& st.mode 4095) mode)
        (ok 0)
        (match (run! "chmod" (list (octal mode "") p) "/")
          ((ok o) (if (= o.exitCode 0) (ok 0) (err (str "PermissionError: chmod " (pyQuote p) ": " o.stderr))))
          ((err e) (err e)))))
    ((none) (err (osError "notFound" p))))

fn ! journalWrite path: String text: String -> (Result Int64 String)
  (if (stringEmpty? path)
    (ok 0)
    (let [dir (pathDirname path)]
      (match (if (stringEmpty? dir) (ok 0) (makeDirs! dir))
        ((err e) (err e))
        ((ok _)
          (match (if (isFile? path) (readText! path) (ok ""))
            ((err e) (err e))
            ((ok prev) (writeText! path (str prev text))))))))

fn snapHas files: (List (Pair String Snapshot)) rel: String -> Bool
  (listAny? (fn [pr] (= (pairFirst pr) rel)) files)

fn ! missingDirs d: String root: String acc: (List String) -> (List String)
  (if (and (stringStartsWith? d (str root "/")) (not (exists? d)))
    (missingDirs (pathDirname d) root (cons d acc))
    (listReverse acc))

fn ! takeSnapshot full: String root: String -> (Result Snapshot String)
  (if (isFile? full)
    (match (readText! full)
      ((err e) (err e))
      ((ok b) (ok (Snapshot :bytes (some b) :mode (some (match (statOf full) ((some st) (& st.mode 4095)) ((none) 0))) :dirs (list)))))
    (ok (Snapshot :bytes none :mode none :dirs (missingDirs (pathDirname full) root (list)))))

fn ! snapshotBeforeWrite w: Written filePath: String -> (Result Written String)
  (match w.files
    ((none) (ok w))
    ((some files)
      (if (stringEmpty? filePath)
        (ok w)
        (let [root w.root
              full (pathNorm (pathJoin root filePath))
              rel (pathRel full root)]
          (if (or (snapHas files rel) (or (= rel "..") (stringStartsWith? rel "../")))
            (ok w)
            (match (takeSnapshot full root)
              ((err e) (err e))
              ((ok s) (ok (with w :root root :files (some (listAppend files (list (pair rel s)))))))))))))

fn patchLines data: (Option String) -> (List String)
  (match data
    ((none) (list))
    ((some s) (if (stringEmpty? s) (list) (d/splitLinesKeepEnds s))))

fn opTag op: d/DiffOpcode -> String
  op.tag

fn trimFirst op: d/DiffOpcode n: Int64 -> d/DiffOpcode
  (d/DiffOpcode :tag op.tag :i1 (max op.i1 (- op.i2 n)) :i2 op.i2 :j1 (max op.j1 (- op.j2 n)) :j2 op.j2)

fn trimLast op: d/DiffOpcode n: Int64 -> d/DiffOpcode
  (d/DiffOpcode :tag op.tag :i1 op.i1 :i2 (min op.i2 (+ op.i1 n)) :j1 op.j1 :j2 (min op.j2 (+ op.j1 n)))

fn groupLoop codes: (List d/DiffOpcode) n: Int64 group: (List d/DiffOpcode) acc: (List (List d/DiffOpcode)) -> (List (List d/DiffOpcode))
  (if (listEmpty? codes)
    (let [g (listReverse group)]
      (listReverse (if (and (not (listEmpty? g)) (not (and (= (listLength g) 1) (= (opTag (c/firstOf g)) "equal")))) (cons g acc) acc)))
    (let [op (c/firstOf codes)
          rest (c/restOf codes)]
      (if (and (= (opTag op) "equal") (> (- op.i2 op.i1) (* 2 n)))
        (groupLoop rest n (list (trimFirst op n)) (cons (listReverse (cons (trimLast op n) group)) acc))
        (groupLoop rest n (cons op group) acc))))

fn groupedOpcodes! a: (List String) b: (List String) n: Int64 -> (List (List d/DiffOpcode))
  (let [raw (d/getOpcodes a b)
        codes0 (if (listEmpty? raw) (list (d/DiffOpcode :tag "equal" :i1 0 :i2 1 :j1 0 :j2 1)) raw)
        codes1 (if (= (opTag (c/firstOf codes0)) "equal") (cons (trimFirst (c/firstOf codes0) n) (c/restOf codes0)) codes0)
        codes2 (match (listLast codes1)
                 ((some l) (if (= (opTag l) "equal") (listAppend (listTake codes1 (- (listLength codes1) 1)) (list (trimLast l n))) codes1))
                 ((none) codes1))]
    (groupLoop codes2 n (list) (list)))

fn rangeText start: Int64 stop: Int64 -> String
  (let [len (- stop start)]
    (cond
      ((= len 1) (stringFromInt64 (+ start 1)))
      ((= len 0) (str (stringFromInt64 start) ",0"))
      (else (str (stringFromInt64 (+ start 1)) "," (stringFromInt64 len)))))

fn patchLine line: String -> String
  (if (stringEndsWith? line "\n") line (str line "\n\\ No newline at end of file\n"))

enum Cur
  (cur rest: (List String) pos: Int64)

fn advance c0: Cur target: Int64 -> Cur
  (match c0 ((cur xs pos) (if (or (>= pos target) (listEmpty? xs)) c0 (advance (cur (c/restOf xs) (+ pos 1)) target))))

fn emitRun c0: Cur stop: Int64 prefix: String out: (List String) -> (Pair Cur (List String))
  (match c0 ((cur xs pos)
    (if (or (>= pos stop) (listEmpty? xs))
      (pair c0 out)
      (emitRun (cur (c/restOf xs) (+ pos 1)) stop prefix (cons (str prefix (c/firstOf xs)) out)))))

enum Emit
  (emitState ca: Cur cb: Cur out: (List String))

fn opEmit st: Emit op: d/DiffOpcode -> Emit
  (match st ((emitState ca cb out)
    (let [tag (opTag op)]
      (cond
        ((= tag "equal") (match (emitRun (advance ca op.i1) op.i2 " " out) ((pair ca2 o2) (emitState ca2 cb o2))))
        (else
          (let [m (if (or (= tag "replace") (= tag "delete")) (emitRun (advance ca op.i1) op.i2 "-" out) (pair ca out))
                pl (if (or (= tag "replace") (= tag "insert")) (emitRun (advance cb op.j1) op.j2 "+" (pairSecond m)) (pair cb (pairSecond m)))]
            (emitState (pairFirst m) (pairFirst pl) (pairSecond pl))))))))

fn groupEmit st: Emit g: (List d/DiffOpcode) -> Emit
  (let [first (c/firstOf g)
        last (optionOr (listLast g) first)
        head (str "@@ -" (rangeText first.i1 last.i2) " +" (rangeText first.j1 last.j2) " @@\n")]
    (match st ((emitState ca cb out) (fold opEmit (emitState ca cb (cons head out)) g))))

fn unifiedLines! a: (List String) b: (List String) fromName: String toName: String -> (List String)
  (let [groups (groupedOpcodes! a b 3)]
    (if (listEmpty? groups)
      (list)
      (match (fold groupEmit (emitState (cur a 0) (cur b 0) (list (str "+++ " toName "\n") (str "--- " fromName "\n"))) groups)
        ((emitState _ _ out) (listReverse out)))))

fn filePatch! rel: String old: (Option String) new: (Option String) newMode: Int64 -> String
  (let [head (str "diff --git a/" rel " b/" rel "\n"
               (cond
                 ((none? old) (str "new file mode " (if (= (& newMode 73) 0) "100644" "100755") "\n"))
                 ((none? new) "deleted file mode 100644\n")
                 (else "")))
        fromName (if (none? old) "/dev/null" (str "a/" rel))
        toName (if (none? new) "/dev/null" (str "b/" rel))
        lines (unifiedLines! (patchLines old) (patchLines new) fromName toName)]
    (str head (c/joinAll (map patchLine lines))))

fn wordRun s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isWord (ch s i))) (wordRun s (+ i 1) n) i)

fn nonSpaceRun s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (isSpaceByte (ch s i)))) (nonSpaceRun s (+ i 1) n) i)

fn resultStatus line: String -> (Option String)
  (if (stringStartsWith? line "(:result :status :")
    (let [n (stringLength line)
          k (wordRun line 18 n)]
      (if (> k 18) (some (sl line 18 k)) none))
    none)

fn patchPath line: String -> (Option String)
  (if (stringStartsWith? line "diff --git a/")
    (let [n (stringLength line)
          k (nonSpaceRun line 13 n)]
      (if (and (> k 13) (= (sl line k (+ k 3)) " b/")) (some (sl line 13 k)) none))
    none)

fn someOf xs: (List (Option String)) -> (List String)
  (fold (fn [acc o] (match o ((some v) (listAppend acc (list v))) ((none) acc))) (list) xs)

fn ! snapshotAll w: Written rels: (List String) -> (Result Written String)
  (if (listEmpty? rels)
    (ok w)
    (match (snapshotBeforeWrite w (c/firstOf rels))
      ((err e) (err e))
      ((ok w2) (snapshotAll w2 (c/restOf rels)))))

fn cut300 s: String -> String
  (if (> (stringLength s) 300) (sl s 0 300) s)

fn ! journalSaysOk journalPath: String -> Bool
  (if (isFile? journalPath)
    (match (listLast (someOf (map resultStatus (stringLines (resultOr (fileReadString journalPath) ""))))) ((some m) (= m "ok")) ((none) false))
    false)

fn ! applyResumePatch w: Written rootDir: String journalPath: String sessionId: String -> (Result (Pair Written (Pair (Option String) (Option String))) String)
  (let [patch (str (splitExt journalPath) ".patch")]
    (cond
      ((not (isFile? patch)) (ok (pair w (pair none none))))
      ((journalSaysOk journalPath) (ok (pair w (pair none none))))
      (else
        (match (readText! patch)
          ((err e) (err e))
          ((ok text)
            (match (snapshotAll w (someOf (map patchPath (stringLines text))))
              ((err e) (err e))
              ((ok w2)
                (match (git! rootDir (list "apply" "--whitespace=nowarn" (pathAbs! patch)))
                  ((err e) (err e))
                  ((ok o)
                    (if (not (= o.exitCode 0))
                      (let [msg (cut300 (pyStrip (if (stringEmpty? o.stderr) o.stdout o.stderr)))]
                        (ok (pair w2 (pair none (some (str "git apply " (pathBasename patch) ": " msg))))))
                      (let [applied (pathRel patch rootDir)]
                        (match (pathRemove patch)
                          ((ok _) (ok (pair w2 (pair (some applied) none))))
                          ((err e) (err (osError (errKind e) patch)))))))))))))))

fn ! currentBytes full: String -> (Option String)
  (if (isFile? full) (resultToOption (fileReadString full)) none)

fn sameBytes a: (Option String) b: (Option String) -> Bool
  (match a
    ((none) (none? b))
    ((some x) (match b ((some y) (= x y)) ((none) false))))

fn ! headBytes! rootDir: String rel: String -> (Result (Option String) String)
  (match (git! rootDir (list "show" (str "HEAD:" rel)))
    ((err e) (err e))
    ((ok o)
      (if (not (= o.exitCode 0))
        (ok none)
        (match (git! rootDir (list "cat-file" "-s" (str "HEAD:" rel)))
          ((err e) (err e))
          ((ok s)
            (let [size (optionOr (stringToInt64 (pyStrip s.stdout)) -1)
                  out o.stdout]
              (ok (some (if (= size (+ (stringLength out) 1)) (str out "\n") out)))))))))

fn ! removeEmptyDirs dirs: (List String) -> Bool
  (fold (fn [acc dir] (if (and (isDir? dir) (listEmpty? (resultOr (dirList dir) (list "x")))) (and (ok? (pathRemove dir)) acc) acc)) true dirs)

fn ! dropFile! rootDir: String rel: String full: String dirs: (List String) -> (Result Int64 String)
  (match (if (isFile? full) (pathRemove full) (ok ()))
    ((err e) (err (osError (errKind e) full)))
    ((ok _)
      (do
        (removeEmptyDirs dirs)
        (match (git! rootDir (list "rm" "--cached" "--quiet" "--ignore-unmatch" "--" rel))
          ((ok _) (ok 0))
          ((err e) (err e))))))

fn ! putFile! rootDir: String rel: String full: String bytes: String mode: (Option Int64) -> (Result Int64 String)
  (let [dir (pathDirname full)]
    (match (makeDirs! (if (stringEmpty? dir) "." dir))
      ((err e) (err e))
      ((ok _)
        (match (writeText! full bytes)
          ((err e) (err e))
          ((ok _)
            (match (match mode ((some m) (chmod! full m)) ((none) (ok 0)))
              ((err e) (err e))
              ((ok _)
                (match (git! rootDir (list "reset" "-q" "--" rel))
                  ((ok _) (ok 0))
                  ((err e) (err e))))))))))

fn ! restoreSnap! rootDir: String rel: String full: String snap: Snapshot -> (Result Bool String)
  (match (match snap.bytes
        ((none) (dropFile! rootDir rel full snap.dirs))
        ((some bytes) (putFile! rootDir rel full bytes (some (optionOr snap.mode 420)))))
    ((err e) (err e))
    ((ok _) (ok false)))

fn ! restoreOne! rootDir: String rel: String snap: Snapshot headMoved: Bool -> (Result Bool String)
  (let [full (pathJoin rootDir rel)]
    (if (not headMoved)
      (restoreSnap! rootDir rel full snap)
      (match (headBytes! rootDir rel)
        ((err e) (err e))
        ((ok hb)
          (if (sameBytes hb snap.bytes)
            (restoreSnap! rootDir rel full snap)
            (match (match hb
                  ((none) (dropFile! rootDir rel full snap.dirs))
                  ((some bytes) (putFile! rootDir rel full bytes snap.mode)))
              ((err e) (err e))
              ((ok _) (ok true))))))))

fn ! restoreAll! rootDir: String changed: (List (Pair String Snapshot)) headMoved: Bool acc: (List String) -> (Result (List String) String)
  (if (listEmpty? changed)
    (ok (listReverse acc))
    (let [pr (c/firstOf changed)]
      (match (restoreOne! rootDir (pairFirst pr) (pairSecond pr) headMoved)
        ((err e) (err e))
        ((ok toHead) (restoreAll! rootDir (c/restOf changed) headMoved (if toHead (cons (pairFirst pr) acc) acc))))))

fn ! modeOf full: String -> Int64
  (match (statOf full) ((some st) st.mode) ((none) 0))

fn ! chunkOf rootDir: String pr: (Pair String Snapshot) -> String
  (let [full (pathJoin rootDir (pairFirst pr))
        now (currentBytes full)]
    (filePatch! (pairFirst pr) (pairSecond pr).bytes now (if (none? now) 0 (modeOf full))))

fn ! restoreAndReport! rootDir: String journalPath: String start: (Option String) changed: (List (Pair String Snapshot)) -> (Result Int64 String)
  (match (git! rootDir (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok o)
      (let [cur (if (= o.exitCode 0) (pyStrip o.stdout) "")
            moved (match start ((some s) (and (not (stringEmpty? s)) (and (not (stringEmpty? cur)) (not (= cur s))))) ((none) false))]
        (match (restoreAll! rootDir changed moved (list))
          ((err e) (err e))
          ((ok toHead)
            (if (listEmpty? toHead) (ok 0) (journalWrite journalPath (str "(:restoreToHead (" (quoteList toHead) "))\n"))))))))

fn ! handBack w: Written rootDir: String journalPath: String sessionId: String restore: Bool startHead: (Option String) -> (Result (Pair Written (Pair (Option String) (List String))) String)
  (let [start (match startHead ((some h) (some h)) ((none) w.startHead))
        files (listSortBy pairFirst (optionOr w.files (list)))
        w2 (with w :files none)
        changed (filter (fn [pr] (not (sameBytes (currentBytes (pathJoin rootDir (pairFirst pr))) (pairSecond pr).bytes))) files)]
    (if (listEmpty? changed)
      (ok (pair w2 (pair none (list))))
      (let [chunks (map (fn [pr] (chunkOf rootDir pr)) changed)
            base (if (stringEmpty? journalPath) (pathJoin rootDir (str ".asl/run/agentLoop/" sessionId)) (splitExt journalPath))
            patchFile (str base ".patch")]
        (match (makeDirs! (pathDirname patchFile))
          ((err e) (err e))
          ((ok _)
            (match (writeText! patchFile (c/joinAll chunks))
              ((err e) (err e))
              ((ok _)
                (if (not restore)
                  (ok (pair w2 (pair (some (pathRel patchFile rootDir)) (list))))
                  (match (restoreAndReport! rootDir journalPath start changed)
                    ((err e) (err e))
                    ((ok _) (ok (pair w2 (pair (some (pathRel patchFile rootDir)) (map pairFirst changed))))))))))))))

fn ! copyInto! src: String dest: String -> (Result Int64 String)
  (if (isFile? src)
    (match (readText! src)
      ((err e) (err e))
      ((ok t) (writeText! (pathJoin dest (pathBasename src)) t)))
    (ok 0))

fn errText e: String -> String
  (match (stringIndexOf e ": ") ((some i) (sl e (+ i 2) (stringLength e))) ((none) e))

fn ! retainTo! journalPath: String dest: String patch: String -> (Result Int64 String)
  (match (makeDirs! dest)
    ((err e) (err e))
    ((ok _)
      (match (copyInto! journalPath dest)
        ((err e) (err e))
        ((ok _) (copyInto! patch dest)))))

fn ! retainJournal journalPath: String rootDir: String sessionId: String -> (Result Int64 String)
  (let [rd (if (stringEmpty? rootDir) "." rootDir)
        root (resultOr (realPath rd) (pathAbs! rd))]
    (if (or (stringEmpty? journalPath)
            (or (not (isFile? journalPath))
                (not (stringStartsWith? (resultOr (realPath journalPath) journalPath) (str root "/")))))
      (ok 0)
      (match (git! rd (list "rev-parse" "--path-format=absolute" "--git-dir" "--git-common-dir"))
        ((err e) (err e))
        ((ok o)
          (let [dirs (nonEmpty (stringSplit (stringReplace (stringReplace o.stdout "\n" " ") "\t" " ") " "))]
            (if (or (not (= o.exitCode 0)) (or (not (= (listLength dirs) 2)) (= (c/firstOf dirs) (c/firstOf (c/restOf dirs)))))
              (ok 0)
              (let [dest (pathJoin (pathDirname (c/firstOf (c/restOf dirs))) ".asl/run/agentLoop")
                    patch (pathJoin (pathDirname journalPath) (str sessionId ".patch"))]
                (match (retainTo! journalPath dest patch)
                  ((ok _) (ok 0))
                  ((err e) (journalWrite journalPath (str "(:journalRetain :error \"" (escapeAsn (errText e)) "\" :dest \"" (escapeAsn dest) "\")\n")))))))))))

fn isAtomEnd x: String -> Bool
  (or (isSpaceByte x) (or (= x "(") (or (= x ")") (or (= x ";") (= x "\"")))))

fn atomEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (isAtomEnd (ch s i)))) (atomEnd s (+ i 1) n) i)

fn isDigitCh x: String -> Bool
  (and (>= x "0") (<= x "9"))

fn digitRun s: String i: Int64 n: Int64 -> Int64
  (cond
    ((>= i n) i)
    ((isDigitCh (ch s i)) (digitRun s (+ i 1) n))
    ((and (= (ch s i) "_") (and (> i 0) (and (isDigitCh (ch s (- i 1))) (isDigitCh (ch s (+ i 1)))))) (digitRun s (+ i 1) n))
    (else i))

fn signEnd s: String -> Int64
  (if (or (= (ch s 0) "+") (= (ch s 0) "-")) 1 0)

fn isIntTok s: String -> Bool
  (let [n (stringLength s)
        a (signEnd s)
        b (digitRun s a n)]
    (and (> b a) (= b n)))

fn expEnd s: String c1: Int64 n: Int64 -> Int64
  (if (or (= (ch s c1) "e") (= (ch s c1) "E"))
    (let [sgn (if (or (= (ch s (+ c1 1)) "+") (= (ch s (+ c1 1)) "-")) (+ c1 2) (+ c1 1))
          k (digitRun s sgn n)]
      (if (> k sgn) k -1))
    c1)

fn isFloatTok s: String -> Bool
  (let [n (stringLength s)
        a (signEnd s)
        low (stringLower (sl s a n))
        b (digitRun s a n)
        dot (= (ch s b) ".")
        c1 (if dot (digitRun s (+ b 1) n) b)
        mant (> (- c1 a) (if dot 1 0))]
    (or (or (= low "inf") (or (= low "infinity") (= low "nan")))
        (and mant (= (expEnd s c1 n) n))))

fn canonInt s: String -> String
  (let [neg (= (ch s 0) "-")
        v (optionOr (stringToInt64 (stringReplace (sl s (signEnd s) (stringLength s)) "_" "")) 0)]
    (if (and neg (> v 0)) (str "-" (stringFromInt64 v)) (stringFromInt64 v)))

fn atomOf tok: String -> AsnNode
  (cond
    ((and (stringStartsWith? tok ":") (> (stringLength tok) 1)) (asnKw (sl tok 1 (stringLength tok))))
    ((isIntTok tok) (asnNum (canonInt tok)))
    ((isFloatTok tok) (asnNum tok))
    (else (asnSym tok)))

fn escOf x: String -> String
  (cond ((= x "n") "\n") ((= x "t") "\t") ((= x "r") "\r") (else x))

fn plainRun s: String j: Int64 n: Int64 -> Int64
  (if (and (< j n) (not (or (= (ch s j) "\\") (= (ch s j) "\"")))) (plainRun s (+ j 1) n) j)

fn readString s: String n: Int64 i: Int64 j: Int64 acc: (List String) -> (Result (Pair String Int64) String)
  (cond
    ((>= j n) (err (str "unterminated string at byte " (stringFromInt64 i))))
    ((= (ch s j) "\\")
      (if (>= (+ j 1) n)
        (err (str "dangling escape at byte " (stringFromInt64 j)))
        (readString s n i (+ j 2) (cons (escOf (ch s (+ j 1))) acc))))
    ((= (ch s j) "\"") (ok (pair (c/joinAll (listReverse acc)) (+ j 1))))
    (else
      (let [k (plainRun s (+ j 1) n)]
        (readString s n i k (cons (sl s j k) acc)))))

fn emit v: AsnNode stack: (List (Pair (List AsnNode) Int64)) out: (List AsnNode) -> (Pair (List (Pair (List AsnNode) Int64)) (List AsnNode))
  (if (listEmpty? stack)
    (pair stack (cons v out))
    (let [top (c/firstOf stack)]
      (pair (cons (pair (cons v (pairFirst top)) (pairSecond top)) (c/restOf stack)) out)))

fn lineEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (= (ch s i) "\n"))) (lineEnd s (+ i 1) n) i)

fn readLoop s: String n: Int64 i: Int64 stack: (List (Pair (List AsnNode) Int64)) out: (List AsnNode) -> (Result (List AsnNode) String)
  (if (>= i n)
    (if (listEmpty? stack)
      (ok (listReverse out))
      (err (str "unclosed ( at byte " (stringFromInt64 (pairSecond (c/firstOf stack))))))
    (let [x (ch s i)]
      (cond
        ((isSpaceByte x) (readLoop s n (+ i 1) stack out))
        ((= x ";") (readLoop s n (lineEnd s i n) stack out))
        ((= x "(") (readLoop s n (+ i 1) (cons (pair (list) i) stack) out))
        ((= x ")")
          (if (listEmpty? stack)
            (err (str "unmatched ) at byte " (stringFromInt64 i)))
            (let [top (c/firstOf stack)
                  e (emit (asnForm (listReverse (pairFirst top))) (c/restOf stack) out)]
              (readLoop s n (+ i 1) (pairFirst e) (pairSecond e)))))
        ((= x "\"")
          (match (readString s n i (+ i 1) (list))
            ((err m) (err m))
            ((ok pr)
              (let [e (emit (asnStr (pairFirst pr)) stack out)]
                (readLoop s n (pairSecond pr) (pairFirst e) (pairSecond e))))))
        (else
          (let [j (atomEnd s i n)
                e (emit (atomOf (sl s i j)) stack out)]
            (readLoop s n j (pairFirst e) (pairSecond e)))))))

fn asnRead text: String -> (Result (List AsnNode) String)
  (readLoop text (stringLength text) 0 (list) (list))

fn isForm v: AsnNode -> Bool
  (match v ((asnForm _) true) ((asnKw _) false) ((asnSym _) false) ((asnStr _) false) ((asnNum _) false))

fn asnReadOne text: String -> (Result AsnNode String)
  (match (asnRead text)
    ((err e) (err e))
    ((ok vs)
      (if (and (= (listLength vs) 1) (isForm (c/firstOf vs)))
        (ok (c/firstOf vs))
        (err (str "expected one form, found " (stringFromInt64 (listLength vs)) " values")))))

fn reprChar q: String x: String -> String
  (cond
    ((= x "\\") "\\\\")
    ((= x "\n") "\\n")
    ((= x "\r") "\\r")
    ((= x "\t") "\\t")
    ((= x q) (str "\\" q))
    (else x))

fn pyReprStr s: String -> String
  (let [q (if (and (stringContains? s "'") (not (stringContains? s "\""))) "\"" "'")]
    (str q (c/joinAll (map (fn [x] (reprChar q x)) (stringChars s))) q))

fn nodeRepr v: AsnNode -> String
  (match v
    ((asnKw k) (str ":" k))
    ((asnSym t) t)
    ((asnStr t) (pyReprStr t))
    ((asnNum t) t)
    ((asnForm xs) (str "[" (c/joinSep (map nodeRepr xs) ", ") "]")))

fn isKw v: AsnNode key: String -> Bool
  (match v ((asnKw k) (= k key)) ((asnSym _) false) ((asnStr _) false) ((asnNum _) false) ((asnForm _) false))

fn getLoop xs: (List AsnNode) key: String found: (Option AsnNode) -> (Option AsnNode)
  (if (or (listEmpty? xs) (listEmpty? (c/restOf xs)))
    found
    (getLoop (c/restOf xs) key (if (isKw (c/firstOf xs) key) (some (c/firstOf (c/restOf xs))) found)))

fn dictPut kv: (List (Pair String T)) k: String v: T -> (List (Pair String T))
  (if (listAny? (fn [pr] (= (pairFirst pr) k)) kv)
    (map (fn [pr] (if (= (pairFirst pr) k) (pair k v) pr)) kv)
    (listAppend kv (list (pair k v))))

fn dictAt kv: (List (Pair String T)) k: String -> (Option T)
  (match (listHead (filter (fn [pr] (= (pairFirst pr) k)) kv)) ((some pr) (some (pairSecond pr))) ((none) none))

; (:m :ref LEON-HARNESS5 :do "Leon renders the same harness5.asn rows asl launch renders, through asl-harness/launch renderAsnFor for client leon; mode implement because Leon has no mode path and its task text picks the phases")
fn ! harnessLayers repoRoot: String rootDir: String mode: String -> (Result String String)
  (let [paths (lh/pathsFor repoRoot (lh/runnerDisplay! repoRoot))
        clients (fileReadString paths.clients)
        tools (fileReadString paths.tools)]
    (match clients
      ((err e) (err (str "RuntimeError: ERR_HARNESS: " e)))
      ((ok ctext)
        (match tools
          ((err e) (err (str "RuntimeError: ERR_HARNESS: " e)))
          ((ok ttext)
            (match (lh/probe! rootDir)
              ((err e) (err (str "RuntimeError: ERR_HARNESS: " e)))
              ((ok probe)
                (match (lh/platform!)
                  ((err e) (err (str "RuntimeError: ERR_HARNESS: " e)))
                  ((ok plat)
                    (match (lh/today!)
                      ((err e) (err (str "RuntimeError: ERR_HARNESS: " e)))
                      ((ok day)
                        (let [loaded (lh/loadSources paths "" ctext ttext)
                              opts (lh/RenderOpts :cwd rootDir :client "leon" :mode mode :core false :promptDir none :drop (list) :only (list)
                                                  :fills (list) :once false :platform plat :date day)]
                          (match (lh/renderAsnFor loaded probe opts)
                            ((err e) (err (str "RuntimeError: ERR_HARNESS: " e)))
                            ((ok text) (ok (pyStrip text))))))))))))))))

fn classEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (= (ch s i) "\""))) (classEnd s (+ i 1) n) i)

fn afterSpace s: String i: Int64 n: Int64 -> (Option Int64)
  (let [a (leftEnd s i n)]
    (if (= a i) none (some a)))

fn effectAt s: String n: Int64 i: Int64 -> (Option (Pair (Pair String String) Int64))
  (if (not (= (sl s i (+ i 3)) ":op"))
    none
    (match (afterSpace s (+ i 3) n)
      ((none) none)
      ((some a)
        (let [b (classEnd s (+ a 1) n)]
          (if (or (not (= (ch s a) "\"")) (or (>= b n) (= b (+ a 1))))
            none
            (match (afterSpace s (+ b 1) n)
              ((none) none)
              ((some c1)
                (if (not (= (sl s c1 (+ c1 6)) ":class"))
                  none
                  (match (afterSpace s (+ c1 6) n)
                    ((none) none)
                    ((some c2)
                      (let [e (wordRun s (+ c2 1) n)]
                        (if (or (not (= (ch s c2) ":")) (= e (+ c2 1)))
                          none
                          (some (pair (pair (sl s (+ a 1) b) (sl s (+ c2 1) e)) e))))))))))))))

fn effectsLoop s: String n: Int64 i: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (if (>= i n)
    acc
    (match (effectAt s n i)
      ((some m) (effectsLoop s n (pairSecond m) (dictPut acc (pairFirst (pairFirst m)) (pairSecond (pairFirst m)))))
      ((none) (effectsLoop s n (+ i 1) acc))))

fn ! loadEffects repoRoot: String -> (List (Pair String String))
  (let [current (pathJoin repoRoot "asl/agentLoop/effects.asn")
        legacy (pathJoin repoRoot "scripts/agentLoop/effects.asn")
        path (if (isFile? current) current legacy)]
    (if (not (isFile? path))
      (list)
      (let [text (resultOr (fileReadString path) "")]
        (effectsLoop text (stringLength text) 0 (list)))))

fn opShapes -> (List (Pair String String))
  (list (pair "write" "(:step :op \"write\" :file f :content :raw|s)")
        (pair "edit" "(:step :op \"edit\" :file f :old :raw|s :new :raw|s)")
        (pair "read" "(:step :op \"read\" :file f [:symbol name] [:anchor s] [:start n :end m])")
        (pair "query" "(:step :op \"query\" :query s [:in code|text|all] [:limit n])")
        (pair "outline" "(:step :op \"outline\" :file f)")
        (pair "check" "(:step :op \"check\" :file f)")
        (pair "diff" "(:step :op \"diff\")")
        (pair "flush" "(:step :op \"flush\")")
        (pair "discard" "(:step :op \"discard\")")
        (pair "test" "(:step :op \"test\" :file f)")
        (pair "tree" "(:step :op \"tree\" :path p)")
        (pair "fix" "(:step :op \"fix\" :file f)")
        (pair "txn" "(:txn :owns (f ...) ...)")
        (pair "tools" "(:step :op \"tools\")")
        (pair "help" "(:step :op \"help\" :name op)")
        (pair "findings" "(:findings (:claim s :file f))")
        (pair "evidence" "(:evidence (:receipt id [:exit n]))")
        (pair "escalate" "(:escalate :reason s)")
        (pair "done" "(:done [:commit s])")
        (pair "gitDiff" "(:step :op \"gitDiff\" :path p :base rev [:start n :end m])")
        (pair "gitLog" "(:step :op \"gitLog\" :path p :limit n [:start n :end m])")
        (pair "gitShow" "(:step :op \"gitShow\" :rev rev :path p [:start n :end m])")
        (pair "gate" "(:step :op \"gate\" [:n i])")
        (pair "run" "(:step :op \"run\" :argv \"cmd\")")
        (pair "delete" "(:step :op \"delete\" :file f)")
        (pair "manage" "(:step :op \"manage\" :action spawn|poll|tail|send|kill|list :id name [:cmd c] [:text s])")
        (pair "note" "(:step :op \"note\" :text s)")
        (pair "observe" "(:step :op \"observe\" :dim callers|status|coverage|tokenCost|memory|session [:symbol s] [:path p] [:spec p])")
        (pair "search" "(:step :op \"search\" :query s [:limit n])")
        (pair "research" "(:step :op \"research\" :topic s [:depth flash|deep|exhaustive])")
        (pair "crawl" "(:step :op \"crawl\" :url u [:distill text|asn] [:limit n])"))

fn quoted xs: (List String) -> String
  (c/joinSep (map (fn [x] (str "\"" (escapeAsn x) "\"")) xs) " ")

fn opt c: Bool x: String -> (List String)
  (if c (list x) (list))

fn planRow -> String
  "(:plan :first (:plan (:step :id s1 :do s :check s)) :sentWhole true :now (:plan :done (ids) :current id :turnsOnCurrent n) :marks ((:planDone :id s1 :ev receiptId) (:planDrop :id s :why s) (:plan :revise ((:step ...)) :why s)) :doneWhen (every step (done dropped)) :ev receiptShowingCheck)"

fn batchRow -> String
  "(:batch :example ((:step :op \"edit\" :file \"src/ring.py\" :old \"return xs[len(xs)]\" :new \"return xs[len(xs) - 1]\") (:step :op \"read\" :file \"tests/ringTest.sh\" :start 1 :end 60) (:step :op \"gate\" :n 1)) :waits (:step :needs receiptNotSeen))"

; (:m :ref LEONPOOL3 :do "pool tasks talk through ask and answer forms; outside a pool both are ERR_NOT_IN_POOL")
fn poolRow -> String
  "(:pool :ask (:ask :to i :body (...)) :waits answer :answers (:poolAsks ...) :reply (:answer :to from :body (...)) :outside ERR_NOT_IN_POOL)"

fn gatesRow gates: (List String) -> String
  (str "(:gates :run (:step :op \"gate\") :nth (:step :op \"gate\" :n i) :after everyActingTurn :counts (:gate :asserts n :failed 0) :needs (:gt n 0) :redOnRevert (:gt failed 0) :items (" (quoted gates) "))")

fn ! buildSystemPrompt repoRoot: String task: String rootDir: String base: String gates: (List String) contextTokens: (Option Int64) plan: Bool -> (Result String String)
  (let [effects (loadEffects repoRoot)
        confirm (map pairFirst (filter (fn [e] (listContains? (list "outward" "irreversible" "needsConfirm") (pairSecond e))) effects))
        accepted (map pairFirst (filter (fn [e] (and (= (pairSecond e) "local") (not (= (pairFirst e) "step")))) effects))
        shapes (someOf (map (fn [op] (if (listContains? (list "diff" "flush" "discard") op) none (dictAt (opShapes) op))) accepted))
        rows (listAppend (opt (not (listEmpty? shapes)) (str "(:ops :raw \"code with quotes, backslashes or many lines: :raw and a fenced block on the following lines\" :forms (" (quoted shapes) "))"))
               (listAppend (opt (not (listEmpty? confirm)) (str "(:needsConfirm :answers needsConfirmReceipt :ops (" (quoted confirm) "))"))
                 (listAppend (opt plan (planRow))
                   (listAppend (list (batchRow) (poolRow))
                     (opt (not (listEmpty? gates)) (gatesRow gates))))))
        layers (match contextTokens
                 ((some _) (harnessLayers repoRoot rootDir "implement"))
                 ((none) (ok "")))
        card (if (gr/wantsAslCard task gates) (gr/aslCard! repoRoot) (ok ""))]
    (match layers
      ((err e) (err e))
      ((ok lay)
        (match card
          ((err e) (err (str "RuntimeError: ERR_HARNESS: aslCard: " e)))
          ((ok cardText)
            (ok (c/joinSep (listAppend (opt (not (stringEmpty? lay)) lay)
                             (listAppend rows
                               (listAppend (opt (not (stringEmpty? cardText)) cardText)
                                 (listAppend (opt (not (stringEmpty? task)) (str "(:task " (quoted (list task)) ")"))
                                             (opt (not (stringEmpty? base)) (str "(:base " (quoted (list base)) ")"))))))
                           "\n")))))))
