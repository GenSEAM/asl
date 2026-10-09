(module asl/agentLoop/journal
  :x [Snapshot Written AsnNode Layer
      harnessLayers buildSystemPrompt retainJournal journalWrite snapshotBeforeWrite patchLines filePatch!
      applyResumePatch handBack writtenField handBackFields
      newWritten idleWritten git! asnRead asnReadOne pathNorm pathRel pathJoin pathDirname splitExt loadEffects]
  :i [(asl/agentLoop/core :a c) (asl/agentLoop/diff :a d) (asl-proc/coreProcess :a cp)])

(schema Snapshot
  (:f bytes (Option String))
  (:f mode (Option Int64))
  (:f dirs (List String)))

(schema Written
  (:f root String)
  (:f files (Option (List (Pair String Snapshot))))
  (:f startHead (Option String)))

(schema Grammar
  (:f harness String)
  (:f clients String)
  (:f tools String)
  (:f host String))

enum AsnNode
  (asnKw name: String)
  (asnSym text: String)
  (asnStr text: String)
  (asnNum text: String)
  (asnForm items: (List AsnNode))

enum Layer
  (layerOf id: String conds: (Option (List String)) text: (Option String) src: (Option String))

(schema Harness
  (:f layers (List Layer))
  (:f intro String)
  (:f items (List (Pair String (Pair (Option AsnNode) (Option AsnNode)))))
  (:f modes (List (Pair String (List String)))))

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
  (mt patch
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
  (mt (statOf p) ((some st) st.isFile) ((none) false))

fn ! isDir? p: String -> Bool
  (mt (statOf p) ((some st) st.isDir) ((none) false))

fn ! exists? p: String -> Bool
  (some? (statOf p))

fn errKind msg: String -> String
  (mt (stringIndexOf msg ":") ((some i) (sl msg 0 i)) ((none) msg))

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
  (mt (fileReadString p)
    ((ok t) (ok t))
    ((err e) (err (osError (errKind e) p))))

fn ! writeText! p: String t: String -> (Result Int64 String)
  (mt (fileWrite p t)
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
          (mt (dirCreate p)
            ((ok _) (ok 0))
            ((err e) (err (osError (errKind e) first))))))))

fn procError tool: String e: cp/ProcessError -> String
  (mt e
    ((cp/notFound _) (str "FileNotFoundError: [Errno 2] No such file or directory: " (pyQuote tool)))
    ((cp/permissionDenied _) (str "PermissionError: [Errno 13] Permission denied: " (pyQuote tool)))
    ((cp/timeout ms) (str "TimeoutExpired: " tool " timed out after " (stringFromInt64 ms) " ms"))
    ((cp/executionFailed code msg) (str "OSError: " tool ": " msg)))

fn ! run! tool: String args: (List String) cwd: String -> (Result cp/ProcessOutput String)
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd tool args) cwd) 120000))
    ((ok o) (ok o))
    ((err e) (err (procError tool e))))

fn ! git! cwd: String args: (List String) -> (Result cp/ProcessOutput String)
  (run! "git" args cwd)

fn octal m: Int64 acc: String -> String
  (if (= m 0) (if (stringEmpty? acc) "0" acc) (octal (/ m 8) (str (stringFromInt64 (mod m 8)) acc)))

fn ! chmod! p: String mode: Int64 -> (Result Int64 String)
  (mt (statOf p)
    ((some st)
      (if (= (& st.mode 4095) mode)
        (ok 0)
        (mt (run! "chmod" (list (octal mode "") p) "/")
          ((ok o) (if (= o.exitCode 0) (ok 0) (err (str "PermissionError: chmod " (pyQuote p) ": " o.stderr))))
          ((err e) (err e)))))
    ((none) (err (osError "notFound" p))))

fn ! journalWrite path: String text: String -> (Result Int64 String)
  (if (stringEmpty? path)
    (ok 0)
    (let [dir (pathDirname path)]
      (mt (if (stringEmpty? dir) (ok 0) (makeDirs! dir))
        ((err e) (err e))
        ((ok _)
          (mt (if (isFile? path) (readText! path) (ok ""))
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
    (mt (readText! full)
      ((err e) (err e))
      ((ok b) (ok (Snapshot :bytes (some b) :mode (some (mt (statOf full) ((some st) (& st.mode 4095)) ((none) 0))) :dirs (list)))))
    (ok (Snapshot :bytes none :mode none :dirs (missingDirs (pathDirname full) root (list)))))

fn ! snapshotBeforeWrite w: Written filePath: String -> (Result Written String)
  (mt w.files
    ((none) (ok w))
    ((some files)
      (if (stringEmpty? filePath)
        (ok w)
        (let [root w.root
              full (pathNorm (pathJoin root filePath))
              rel (pathRel full root)]
          (if (or (snapHas files rel) (or (= rel "..") (stringStartsWith? rel "../")))
            (ok w)
            (mt (takeSnapshot full root)
              ((err e) (err e))
              ((ok s) (ok (with w :root root :files (some (listAppend files (list (pair rel s)))))))))))))

fn patchLines data: (Option String) -> (List String)
  (mt data
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
        codes2 (mt (listLast codes1)
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
  (mt c0 ((cur xs pos) (if (or (>= pos target) (listEmpty? xs)) c0 (advance (cur (c/restOf xs) (+ pos 1)) target))))

fn emitRun c0: Cur stop: Int64 prefix: String out: (List String) -> (Pair Cur (List String))
  (mt c0 ((cur xs pos)
    (if (or (>= pos stop) (listEmpty? xs))
      (pair c0 out)
      (emitRun (cur (c/restOf xs) (+ pos 1)) stop prefix (cons (str prefix (c/firstOf xs)) out)))))

enum Emit
  (emitState ca: Cur cb: Cur out: (List String))

fn opEmit st: Emit op: d/DiffOpcode -> Emit
  (mt st ((emitState ca cb out)
    (let [tag (opTag op)]
      (cond
        ((= tag "equal") (mt (emitRun (advance ca op.i1) op.i2 " " out) ((pair ca2 o2) (emitState ca2 cb o2))))
        (else
          (let [m (if (or (= tag "replace") (= tag "delete")) (emitRun (advance ca op.i1) op.i2 "-" out) (pair ca out))
                pl (if (or (= tag "replace") (= tag "insert")) (emitRun (advance cb op.j1) op.j2 "+" (pairSecond m)) (pair cb (pairSecond m)))]
            (emitState (pairFirst m) (pairFirst pl) (pairSecond pl))))))))

fn groupEmit st: Emit g: (List d/DiffOpcode) -> Emit
  (let [first (c/firstOf g)
        last (optionOr (listLast g) first)
        head (str "@@ -" (rangeText first.i1 last.i2) " +" (rangeText first.j1 last.j2) " @@\n")]
    (mt st ((emitState ca cb out) (fold opEmit (emitState ca cb (cons head out)) g))))

fn unifiedLines! a: (List String) b: (List String) fromName: String toName: String -> (List String)
  (let [groups (groupedOpcodes! a b 3)]
    (if (listEmpty? groups)
      (list)
      (mt (fold groupEmit (emitState (cur a 0) (cur b 0) (list (str "+++ " toName "\n") (str "--- " fromName "\n"))) groups)
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
  (fold (fn [acc o] (mt o ((some v) (listAppend acc (list v))) ((none) acc))) (list) xs)

fn ! snapshotAll w: Written rels: (List String) -> (Result Written String)
  (if (listEmpty? rels)
    (ok w)
    (mt (snapshotBeforeWrite w (c/firstOf rels))
      ((err e) (err e))
      ((ok w2) (snapshotAll w2 (c/restOf rels)))))

fn cut300 s: String -> String
  (if (> (stringLength s) 300) (sl s 0 300) s)

fn ! journalSaysOk journalPath: String -> Bool
  (if (isFile? journalPath)
    (mt (listLast (someOf (map resultStatus (stringLines (resultOr (fileReadString journalPath) ""))))) ((some m) (= m "ok")) ((none) false))
    false)

fn ! applyResumePatch w: Written rootDir: String journalPath: String sessionId: String -> (Result (Pair Written (Pair (Option String) (Option String))) String)
  (let [patch (str (splitExt journalPath) ".patch")]
    (cond
      ((not (isFile? patch)) (ok (pair w (pair none none))))
      ((journalSaysOk journalPath) (ok (pair w (pair none none))))
      (else
        (mt (readText! patch)
          ((err e) (err e))
          ((ok text)
            (mt (snapshotAll w (someOf (map patchPath (stringLines text))))
              ((err e) (err e))
              ((ok w2)
                (mt (git! rootDir (list "apply" "--whitespace=nowarn" (pathAbs! patch)))
                  ((err e) (err e))
                  ((ok o)
                    (if (not (= o.exitCode 0))
                      (let [msg (cut300 (pyStrip (if (stringEmpty? o.stderr) o.stdout o.stderr)))]
                        (ok (pair w2 (pair none (some (str "git apply " (pathBasename patch) ": " msg))))))
                      (let [applied (pathRel patch rootDir)]
                        (mt (pathRemove patch)
                          ((ok _) (ok (pair w2 (pair (some applied) none))))
                          ((err e) (err (osError (errKind e) patch)))))))))))))))

fn ! currentBytes full: String -> (Option String)
  (if (isFile? full) (resultToOption (fileReadString full)) none)

fn sameBytes a: (Option String) b: (Option String) -> Bool
  (mt a
    ((none) (none? b))
    ((some x) (mt b ((some y) (= x y)) ((none) false))))

fn ! headBytes! rootDir: String rel: String -> (Result (Option String) String)
  (mt (git! rootDir (list "show" (str "HEAD:" rel)))
    ((err e) (err e))
    ((ok o)
      (if (not (= o.exitCode 0))
        (ok none)
        (mt (git! rootDir (list "cat-file" "-s" (str "HEAD:" rel)))
          ((err e) (err e))
          ((ok s)
            (let [size (optionOr (stringToInt64 (pyStrip s.stdout)) -1)
                  out o.stdout]
              (ok (some (if (= size (+ (stringLength out) 1)) (str out "\n") out)))))))))

fn ! removeEmptyDirs dirs: (List String) -> Bool
  (fold (fn [acc dir] (if (and (isDir? dir) (listEmpty? (resultOr (dirList dir) (list "x")))) (and (ok? (pathRemove dir)) acc) acc)) true dirs)

fn ! dropFile! rootDir: String rel: String full: String dirs: (List String) -> (Result Int64 String)
  (mt (if (isFile? full) (pathRemove full) (ok ()))
    ((err e) (err (osError (errKind e) full)))
    ((ok _)
      (do
        (removeEmptyDirs dirs)
        (mt (git! rootDir (list "rm" "--cached" "--quiet" "--ignore-unmatch" "--" rel))
          ((ok _) (ok 0))
          ((err e) (err e))))))

fn ! putFile! rootDir: String rel: String full: String bytes: String mode: (Option Int64) -> (Result Int64 String)
  (let [dir (pathDirname full)]
    (mt (makeDirs! (if (stringEmpty? dir) "." dir))
      ((err e) (err e))
      ((ok _)
        (mt (writeText! full bytes)
          ((err e) (err e))
          ((ok _)
            (mt (mt mode ((some m) (chmod! full m)) ((none) (ok 0)))
              ((err e) (err e))
              ((ok _)
                (mt (git! rootDir (list "reset" "-q" "--" rel))
                  ((ok _) (ok 0))
                  ((err e) (err e))))))))))

fn ! restoreSnap! rootDir: String rel: String full: String snap: Snapshot -> (Result Bool String)
  (mt (mt snap.bytes
        ((none) (dropFile! rootDir rel full snap.dirs))
        ((some bytes) (putFile! rootDir rel full bytes (some (optionOr snap.mode 420)))))
    ((err e) (err e))
    ((ok _) (ok false)))

fn ! restoreOne! rootDir: String rel: String snap: Snapshot headMoved: Bool -> (Result Bool String)
  (let [full (pathJoin rootDir rel)]
    (if (not headMoved)
      (restoreSnap! rootDir rel full snap)
      (mt (headBytes! rootDir rel)
        ((err e) (err e))
        ((ok hb)
          (if (sameBytes hb snap.bytes)
            (restoreSnap! rootDir rel full snap)
            (mt (mt hb
                  ((none) (dropFile! rootDir rel full snap.dirs))
                  ((some bytes) (putFile! rootDir rel full bytes snap.mode)))
              ((err e) (err e))
              ((ok _) (ok true))))))))

fn ! restoreAll! rootDir: String changed: (List (Pair String Snapshot)) headMoved: Bool acc: (List String) -> (Result (List String) String)
  (if (listEmpty? changed)
    (ok (listReverse acc))
    (let [pr (c/firstOf changed)]
      (mt (restoreOne! rootDir (pairFirst pr) (pairSecond pr) headMoved)
        ((err e) (err e))
        ((ok toHead) (restoreAll! rootDir (c/restOf changed) headMoved (if toHead (cons (pairFirst pr) acc) acc))))))

fn ! modeOf full: String -> Int64
  (mt (statOf full) ((some st) st.mode) ((none) 0))

fn ! chunkOf rootDir: String pr: (Pair String Snapshot) -> String
  (let [full (pathJoin rootDir (pairFirst pr))
        now (currentBytes full)]
    (filePatch! (pairFirst pr) (pairSecond pr).bytes now (if (none? now) 0 (modeOf full))))

fn ! restoreAndReport! rootDir: String journalPath: String start: (Option String) changed: (List (Pair String Snapshot)) -> (Result Int64 String)
  (mt (git! rootDir (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok o)
      (let [cur (if (= o.exitCode 0) (pyStrip o.stdout) "")
            moved (mt start ((some s) (and (not (stringEmpty? s)) (and (not (stringEmpty? cur)) (not (= cur s))))) ((none) false))]
        (mt (restoreAll! rootDir changed moved (list))
          ((err e) (err e))
          ((ok toHead)
            (if (listEmpty? toHead) (ok 0) (journalWrite journalPath (str "(:restoreToHead (" (quoteList toHead) "))\n"))))))))

fn ! handBack w: Written rootDir: String journalPath: String sessionId: String restore: Bool startHead: (Option String) -> (Result (Pair Written (Pair (Option String) (List String))) String)
  (let [start (mt startHead ((some h) (some h)) ((none) w.startHead))
        files (listSortBy pairFirst (optionOr w.files (list)))
        w2 (with w :files none)
        changed (filter (fn [pr] (not (sameBytes (currentBytes (pathJoin rootDir (pairFirst pr))) (pairSecond pr).bytes))) files)]
    (if (listEmpty? changed)
      (ok (pair w2 (pair none (list))))
      (let [chunks (map (fn [pr] (chunkOf rootDir pr)) changed)
            base (if (stringEmpty? journalPath) (pathJoin rootDir (str ".asl/run/agentLoop/" sessionId)) (splitExt journalPath))
            patchFile (str base ".patch")]
        (mt (makeDirs! (pathDirname patchFile))
          ((err e) (err e))
          ((ok _)
            (mt (writeText! patchFile (c/joinAll chunks))
              ((err e) (err e))
              ((ok _)
                (if (not restore)
                  (ok (pair w2 (pair (some (pathRel patchFile rootDir)) (list))))
                  (mt (restoreAndReport! rootDir journalPath start changed)
                    ((err e) (err e))
                    ((ok _) (ok (pair w2 (pair (some (pathRel patchFile rootDir)) (map pairFirst changed))))))))))))))

fn ! copyInto! src: String dest: String -> (Result Int64 String)
  (if (isFile? src)
    (mt (readText! src)
      ((err e) (err e))
      ((ok t) (writeText! (pathJoin dest (pathBasename src)) t)))
    (ok 0))

fn errText e: String -> String
  (mt (stringIndexOf e ": ") ((some i) (sl e (+ i 2) (stringLength e))) ((none) e))

fn ! retainTo! journalPath: String dest: String patch: String -> (Result Int64 String)
  (mt (makeDirs! dest)
    ((err e) (err e))
    ((ok _)
      (mt (copyInto! journalPath dest)
        ((err e) (err e))
        ((ok _) (copyInto! patch dest)))))

fn ! retainJournal journalPath: String rootDir: String sessionId: String -> (Result Int64 String)
  (let [rd (if (stringEmpty? rootDir) "." rootDir)
        root (resultOr (realPath rd) (pathAbs! rd))]
    (if (or (stringEmpty? journalPath)
            (or (not (isFile? journalPath))
                (not (stringStartsWith? (resultOr (realPath journalPath) journalPath) (str root "/")))))
      (ok 0)
      (mt (git! rd (list "rev-parse" "--path-format=absolute" "--git-dir" "--git-common-dir"))
        ((err e) (err e))
        ((ok o)
          (let [dirs (nonEmpty (stringSplit (stringReplace (stringReplace o.stdout "\n" " ") "\t" " ") " "))]
            (if (or (not (= o.exitCode 0)) (or (not (= (listLength dirs) 2)) (= (c/firstOf dirs) (c/firstOf (c/restOf dirs)))))
              (ok 0)
              (let [dest (pathJoin (pathDirname (c/firstOf (c/restOf dirs))) ".asl/run/agentLoop")
                    patch (pathJoin (pathDirname journalPath) (str sessionId ".patch"))]
                (mt (retainTo! journalPath dest patch)
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
          (mt (readString s n i (+ i 1) (list))
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
  (mt v ((asnForm _) true) ((asnKw _) false) ((asnSym _) false) ((asnStr _) false) ((asnNum _) false))

fn asnReadOne text: String -> (Result AsnNode String)
  (mt (asnRead text)
    ((err e) (err e))
    ((ok vs)
      (if (and (= (listLength vs) 1) (isForm (c/firstOf vs)))
        (ok (c/firstOf vs))
        (err (str "expected one form, found " (stringFromInt64 (listLength vs)) " values")))))

fn formItems v: AsnNode -> (List AsnNode)
  (mt v ((asnForm xs) xs) ((asnKw _) (list)) ((asnSym _) (list)) ((asnStr _) (list)) ((asnNum _) (list)))

fn strLike v: AsnNode -> (Option String)
  (mt v ((asnKw k) (some k)) ((asnSym t) (some t)) ((asnStr t) (some t)) ((asnNum _) none) ((asnForm _) none))

fn strIs v: AsnNode s: String -> Bool
  (mt (strLike v) ((some t) (= t s)) ((none) false))

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

fn pyReprList xs: (List String) -> String
  (str "[" (c/joinSep (map pyReprStr xs) ", ") "]")

fn nodeRepr v: AsnNode -> String
  (mt v
    ((asnKw k) (str ":" k))
    ((asnSym t) t)
    ((asnStr t) (pyReprStr t))
    ((asnNum t) t)
    ((asnForm xs) (str "[" (c/joinSep (map nodeRepr xs) ", ") "]")))

fn nodeStr v: AsnNode -> String
  (mt v
    ((asnKw k) k)
    ((asnSym t) t)
    ((asnStr t) t)
    ((asnNum t) t)
    ((asnForm _) (nodeRepr v)))

fn optStr o: (Option AsnNode) -> String
  (mt o ((some v) (nodeStr v)) ((none) "None"))

fn isKw v: AsnNode key: String -> Bool
  (mt v ((asnKw k) (= k key)) ((asnSym _) false) ((asnStr _) false) ((asnNum _) false) ((asnForm _) false))

fn getLoop xs: (List AsnNode) key: String found: (Option AsnNode) -> (Option AsnNode)
  (if (or (listEmpty? xs) (listEmpty? (c/restOf xs)))
    found
    (getLoop (c/restOf xs) key (if (isKw (c/firstOf xs) key) (some (c/firstOf (c/restOf xs))) found)))

fn formGet v: AsnNode key: String -> (Option AsnNode)
  (getLoop (formItems v) key none)

fn truthy v: AsnNode -> Bool
  (mt v
    ((asnForm xs) (not (listEmpty? xs)))
    ((asnStr t) (not (stringEmpty? t)))
    ((asnKw k) (not (stringEmpty? k)))
    ((asnSym t) (not (stringEmpty? t)))
    ((asnNum t) (not (or (= t "0") (or (= t "0.0") (= t "-0.0"))))))

fn pyType v: AsnNode -> String
  (mt v ((asnForm _) "Form") ((asnNum t) (if (isIntTok t) "int" "float")) ((asnKw _) "Keyword") ((asnSym _) "Symbol") ((asnStr _) "str"))

fn headIs v: AsnNode head: String -> Bool
  (mt (listHead (formItems v)) ((some h) (strIs h head)) ((none) false))

fn formsOf o: (Option AsnNode) head: String -> (Result (List AsnNode) String)
  (mt o
    ((none) (ok (list)))
    ((some v)
      (cond
        ((not (truthy v)) (ok (list)))
        ((isForm v) (ok (filter (fn [x] (and (isForm x) (headIs x head))) (formItems v))))
        (else (err (str "AttributeError: '" (pyType v) "' object has no attribute 'forms'"))))))

fn grammarOf repoRoot: String -> Grammar
  (Grammar :harness (pathJoin repoRoot "asl/grammar/harness.asn") :clients (pathJoin repoRoot "asl/grammar/clients.asn")
           :tools (pathJoin repoRoot "asl/grammar/tools.asn") :host (pathJoin repoRoot "asl/host/out/asl-host"))

fn systemExit msg: String -> String
  (str "SystemExit: " msg)

fn ! readTree! path: String -> (Result AsnNode String)
  (mt (readText! path)
    ((err e) (err e))
    ((ok text)
      (mt (asnReadOne text)
        ((err e) (err (systemExit (str "launch: " path ": " e))))
        ((ok t) (ok t)))))

fn dictPut kv: (List (Pair String T)) k: String v: T -> (List (Pair String T))
  (if (listAny? (fn [pr] (= (pairFirst pr) k)) kv)
    (map (fn [pr] (if (= (pairFirst pr) k) (pair k v) pr)) kv)
    (listAppend kv (list (pair k v))))

fn dictAt kv: (List (Pair String T)) k: String -> (Option T)
  (mt (listHead (filter (fn [pr] (= (pairFirst pr) k)) kv)) ((some pr) (some (pairSecond pr))) ((none) none))

fn clientFields items: (List AsnNode) i: Int64 acc: (List (Pair String AsnNode)) -> (List (Pair String AsnNode))
  (if (>= i (- (listLength items) 1))
    acc
    (let [k (optionOr (listGet items i) (asnSym ""))
          v (optionOr (listGet items (+ i 1)) (asnSym ""))]
      (clientFields items (+ i 2) (mt k ((asnKw name) (dictPut acc name v)) ((asnSym _) acc) ((asnStr _) acc) ((asnNum _) acc) ((asnForm _) acc)))))

fn addClient acc: (Result (List (Pair String (List (Pair String AsnNode)))) String) f: AsnNode -> (Result (List (Pair String (List (Pair String AsnNode)))) String)
  (mt acc
    ((err e) (err e))
    ((ok cs)
      (let [fields (clientFields (formItems f) 1 (list))]
        (mt (dictAt fields "id")
          ((none) (err "KeyError: 'id'"))
          ((some idv) (ok (dictPut cs (nodeStr idv) (filter (fn [pr] (not (= (pairFirst pr) "id"))) fields))))))))

fn ! loadClients! g: Grammar -> (Result (List (Pair String (List (Pair String AsnNode)))) String)
  (mt (readTree! g.clients)
    ((err e) (err e))
    ((ok tree)
      (mt (formsOf (formGet tree "clients") "client")
        ((err e) (err e))
        ((ok forms) (fold addClient (ok (list)) forms)))))

fn ! clientField! g: Grammar client: String field: String -> (Result (Option String) String)
  (mt (loadClients! g)
    ((err e) (err e))
    ((ok cs)
      (ok (mt (dictAt cs client)
            ((none) none)
            ((some fields) (mt (dictAt fields field) ((some v) (strLike v)) ((none) none)))))))

fn nodeIter o: (Option AsnNode) -> (Result (List String) String)
  (mt o
    ((none) (ok (list)))
    ((some v)
      (cond
        ((not (truthy v)) (ok (list)))
        ((isForm v) (ok (map nodeStr (formItems v))))
        ((some? (strLike v)) (ok (stringChars (optionOr (strLike v) ""))))
        (else (err (str "TypeError: '" (pyType v) "' object is not iterable"))))))

fn notForm o: (Option AsnNode) -> Bool
  (mt o ((some v) (not (isForm v))) ((none) false))

fn layerCheck f: AsnNode -> (Result Layer String)
  (let [lid (optStr (formGet f "id"))
        text (formGet f "text")
        src (formGet f "from")
        whenV (formGet f "when")
        unlessV (formGet f "unless")
        badText (mt text ((some t) (none? (strLike t))) ((none) false))]
    (cond
      ((or (= (none? text) (none? src)) badText)
        (err (systemExit (str "launch: layer " lid " needs exactly one of :text \"...\" or :from"))))
      ((notForm whenV) (err (systemExit (str "launch: layer " lid " :when must be a list of facts"))))
      ((notForm unlessV) (err (systemExit (str "launch: layer " lid " :unless must be a list of facts"))))
      (else
        (let [cnd (listAppend (resultOr (nodeIter whenV) (list)) (map (fn [u] (str "!" u)) (resultOr (nodeIter unlessV) (list))))]
          (ok (layerOf lid (if (listEmpty? cnd) none (some cnd))
                       (mt text ((some t) (strLike t)) ((none) none))
                       (mt src ((some s) (some (nodeStr s))) ((none) none))))))))

fn attGet att: (Option AsnNode) key: String -> (Result (Option AsnNode) String)
  (mt att
    ((none) (ok none))
    ((some v)
      (cond
        ((not (truthy v)) (ok none))
        ((isForm v) (ok (formGet v key)))
        (else (err (str "AttributeError: '" (pyType v) "' object has no attribute 'get'"))))))

fn missingOf items: (List (Pair String (Pair (Option AsnNode) (Option AsnNode)))) ids: (List String) -> (List String)
  (filter (fn [i] (none? (dictAt items i))) ids)

fn modesMissing g: Grammar items: (List (Pair String (Pair (Option AsnNode) (Option AsnNode)))) modes: (List (Pair String (List String))) -> (Option String)
  (mt (listHead (filter (fn [m] (not (listEmpty? (missingOf items (pairSecond m))))) modes))
    ((none) none)
    ((some m)
      (some (systemExit (str "launch: mode " (pairFirst m) " names unknown attractors "
                             (pyReprList (missingOf items (pairSecond m))) " in " g.harness)))))

fn collect rs: (List (Result T String)) -> (Result (List T) String)
  (fold (fn [acc r] (mt acc ((err e) (err e)) ((ok xs) (mt r ((err e) (err e)) ((ok x) (ok (listAppend xs (list x)))))))) (ok (list)) rs)

fn modeOfForm m: AsnNode -> (Result (Pair String (List String)) String)
  (mt (nodeIter (formGet m "attractors"))
    ((err e) (err e))
    ((ok ids) (ok (pair (optStr (formGet m "id")) ids))))

fn ! attractorsOf! g: Grammar tree: AsnNode layers: (List Layer) -> (Result Harness String)
  (let [att (formGet tree "attractors")
        parts (collect (list (attGet att "items") (attGet att "modes") (attGet att "intro")))]
    (mt parts
      ((err e) (err e))
      ((ok nodes)
        (let [itemsNode (optionOr (listGet nodes 0) none)
              modesNode (optionOr (listGet nodes 1) none)
              introNode (optionOr (listGet nodes 2) none)]
          (mt (formsOf itemsNode "attractor")
            ((err e) (err e))
            ((ok aforms)
              (mt (formsOf modesNode "mode")
                ((err e) (err e))
                ((ok mforms)
                  (mt (collect (map modeOfForm mforms))
                    ((err e) (err e))
                    ((ok modeList)
                      (let [items (fold (fn [acc a] (dictPut acc (optStr (formGet a "id")) (pair (formGet a "goal") (formGet a "shadow")))) (list) aforms)
                            modes (fold (fn [acc m] (dictPut acc (pairFirst m) (pairSecond m))) (list) modeList)]
                        (mt (modesMissing g items modes)
                          ((some e) (err e))
                          ((none)
                            (ok (Harness :layers layers
                                         :intro (mt introNode ((some v) (if (truthy v) (nodeStr v) "")) ((none) ""))
                                         :items items :modes modes)))))))))))))))

fn ! loadHarness! g: Grammar -> (Result Harness String)
  (mt (readTree! g.harness)
    ((err e) (err e))
    ((ok tree)
      (if (not (headIs tree "harness"))
        (err (systemExit (str "launch: " g.harness " is not a (:harness ...) form")))
        (mt (formsOf (formGet tree "layers") "layer")
          ((err e) (err e))
          ((ok lforms)
            (mt (collect (map layerCheck lforms))
              ((err e) (err e))
              ((ok layers)
                (if (listEmpty? layers)
                  (err (systemExit (str "launch: " g.harness " has no :layers")))
                  (mt (attractorsOf! g tree layers)
                    ((err e) (err e))
                    ((ok h)
                      (mt (loadClients! g)
                        ((err e) (err e))
                        ((ok _) (ok h)))))))))))))

fn ! whichAsl -> (Option String)
  (listHead (filter (fn [p] (mt (statOf p) ((some st) (and st.isFile (not (= (& st.mode 73) 0)))) ((none) false)))
                    (map (fn [dir] (pathJoin (if (stringEmpty? dir) "." dir) "asl")) (stringSplit (optionOr (envGet "PATH") "") ":"))))

fn migrateTrue text: String i: Int64 -> Bool
  (mt (stringIndexOf (sl text i (stringLength text)) ":migrate")
    ((none) false)
    ((some k)
      (let [n (stringLength text)
            p (+ (+ i k) 8)
            q (leftEnd text p n)]
        (if (and (> q p) (and (= (sl text q (+ q 4)) "true") (not (isWord (ch text (+ q 4))))))
          true
          (migrateTrue text p)))))

fn ! facts! g: Grammar client: String cwd: String mode: String -> (Result (List (Pair String Bool)) String)
  (mt (git! cwd (list "rev-parse" "--show-toplevel"))
    ((err e) (err e))
    ((ok top)
      (let [root (if (= top.exitCode 0) (pyStrip top.stdout) "")
            hasRoot (not (stringEmpty? root))
            asex (and hasRoot (isFile? (pathJoin root "asl/grammar/rules.asn")))
            aslSrc (if hasRoot
                     (mt (git! root (list "ls-files" "--" "*.asl")) ((ok o) (not (stringEmpty? (pyStrip o.stdout)))) ((err _) false))
                     false)
            cfg (if hasRoot (pathJoin root ".asl.config.asn") "")
            migrate (and hasRoot (and (isFile? cfg) (migrateTrue (resultOr (fileReadString cfg) "") 0)))]
        (mt (loadClients! g)
          ((err e) (err e))
          ((ok cs)
            (mt (clientField! g client "shell")
              ((err e) (err e))
              ((ok shell)
                (mt (clientField! g client "subagent")
                  ((err e) (err e))
                  ((ok sub)
                    (ok (list (pair "git" hasRoot) (pair "asex" asex) (pair "foreign" (and hasRoot (not asex)))
                              (pair "aslProject" (or asex (or aslSrc migrate)))
                              (pair "shell" (some? shell)) (pair "asl" (some? (whichAsl)))
                              (pair "session" (not (stringEmpty? (optionOr (envGet "ASL_SESSION") ""))))
                              (pair "implement" (or (= mode "implement") (= mode "grade")))
                              (pair "distill" (= mode "distill")) (pair "agy" (= client "agy")) (pair "codex" (= client "codex"))
                              (pair "once" false) (pair "chat" (none? (dictAt cs client))) (pair "tools" (some? (dictAt cs client)))
                              (pair "subagent" (some? sub)))))))))))))

fn ! gitState! cwd: String -> (Result String String)
  (mt (git! cwd (list "rev-parse" "--show-toplevel"))
    ((err e) (err e))
    ((ok top)
      (if (not (= top.exitCode 0))
        (ok "none")
        (mt (git! cwd (list "branch" "--show-current"))
          ((err e) (err e))
          ((ok b)
            (let [branch (pyStrip b.stdout)]
              (ok (str (pyStrip top.stdout) " on " (if (stringEmpty? branch) "detached HEAD" branch)))))))))

fn briefOf op: AsnNode -> (Option String)
  (mt (formGet op "brief") ((some v) (strLike v)) ((none) none))

fn ! toolBriefs! g: Grammar -> (Result String String)
  (mt (readTree! g.tools)
    ((err e) (err e))
    ((ok tree)
      (mt (formsOf (formGet tree "entries") "op")
        ((err e) (err e))
        ((ok ops) (ok (c/joinSep (someOf (map briefOf ops)) "; "))))))

fn topicField t: AsnNode field: String -> (Option String)
  (if (= (optStr (formGet t "name")) "language")
    (mt (formGet t field) ((some v) (strLike v)) ((none) none))
    none)

fn ! languageText! g: Grammar field: String -> (Result String String)
  (mt (readTree! g.tools)
    ((err e) (err e))
    ((ok tree)
      (mt (formsOf (formGet tree "topics") "topic")
        ((err e) (err e))
        ((ok topics)
          (mt (listHead (someOf (map (fn [t] (topicField t field)) topics)))
            ((some text) (ok text))
            ((none) (err (systemExit (str "launch: " g.tools " has no (:topic :name :language :" field " ...)")))))))))

fn attractorLine h: Harness i: String -> String
  (let [gs (optionOr (dictAt h.items i) (pair none none))]
    (str i ": " (optStr (pairFirst gs)) ", overdone: " (optStr (pairSecond gs))))

fn ! attractorsText! g: Grammar mode: String -> (Result String String)
  (mt (loadHarness! g)
    ((err e) (err e))
    ((ok h)
      (let [ids (optionOr (dictAt h.modes mode) (list))]
        (if (listEmpty? ids)
          (err (systemExit (str "launch: no attractors for mode " mode " in " g.harness)))
          (ok (str h.intro " " (c/joinSep (map (fn [i] (attractorLine h i)) ids) "; ")))))))

fn ! stdoutOf! tool: String args: (List String) -> String
  (mt (run! tool args "/") ((ok o) (pyStrip o.stdout)) ((err e) e))

fn ! fillValue! key: String cwd: String gitState: String briefs: String shell: (Option String) sub: (Option String) -> (Option String)
  (cond
    ((= key "cwd") (some cwd))
    ((= key "git") (some gitState))
    ((= key "platform") (some (str (stdoutOf! "uname" (list "-s")) " " (stdoutOf! "uname" (list "-r")) " " (stdoutOf! "uname" (list "-m")))))
    ((= key "date") (some (stdoutOf! "date" (list "+%Y-%m-%d"))))
    ((= key "shell") (some (optionOr shell "shell")))
    ((= key "asl") (some (optionOr (whichAsl) "asl")))
    ((= key "promptDir") (some "the prompt dir"))
    ((= key "note") (some "note.md"))
    ((= key "aslMore") (some briefs))
    ((= key "subagent") (some (optionOr sub "a subagent tool")))
    (else none))

fn braceNext s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (= (ch s i) "{"))) (braceNext s (+ i 1) n) i)

fn ! fillLoop! text: String n: Int64 i: Int64 lookup: (fn [String] -> (Option String)) acc: (List String) -> String
  (cond
    ((>= i n) (c/joinAll (listReverse acc)))
    ((= (ch text i) "{")
      (let [j (wordRun text (+ i 1) n)]
        (if (and (> j (+ i 1)) (= (ch text j) "}"))
          (fillLoop! text n (+ j 1) lookup (cons (optionOr (lookup (sl text (+ i 1) j)) (sl text i (+ j 1))) acc))
          (fillLoop! text n (+ i 1) lookup (cons "{" acc)))))
    (else
      (let [k (braceNext text (+ i 1) n)]
        (fillLoop! text n k lookup (cons (sl text i k) acc)))))

fn hostEnds s: String i: Int64 len: Int64 n: Int64 -> Bool
  (and (= (sl s (+ i (- len 8)) (+ i len)) "asl-host")
       (or (>= (+ i len) n) (not (or (isWord (ch s (+ i len))) (= (ch s (+ i len)) "-")))))

fn hostTokenAt s: String i: Int64 n: Int64 -> Int64
  (let [before (if (= i 0) "" (ch s (- i 1)))
        okBefore (or (= i 0) (not (or (isWord before) (or (= before "/") (or (= before ".") (= before "-"))))))]
    (cond
      ((not okBefore) 0)
      ((and (= (sl s i (+ i 13)) "asl/host/out/") (hostEnds s i 21 n)) 21)
      ((hostEnds s i 8 n) 8)
      (else 0)))

fn hostLoop s: String n: Int64 i: Int64 start: Int64 host: String acc: (List String) -> String
  (if (>= i n)
    (c/joinAll (listReverse (cons (sl s start n) acc)))
    (let [k (hostTokenAt s i n)]
      (if (> k 0)
        (hostLoop s n (+ i k) (+ i k) host (cons host (cons (sl s start i) acc)))
        (hostLoop s n (+ i 1) start host acc))))

fn hostPaths text: String host: String -> String
  (hostLoop text (stringLength text) 0 0 host (list))

fn factOf have: (List (Pair String Bool)) w: String -> Bool
  (optionOr (dictAt have w) false)

fn ! layerPart! g: Grammar mode: String lid: String text: (Option String) src: (Option String) lookup: (fn [String] -> (Option String)) -> (Result String String)
  (mt src
    ((some s)
      (cond
        ((= s "attractors") (attractorsText! g mode))
        ((= s "language") (languageText! g "text"))
        ((= s "languageTools") (languageText! g "tools"))
        (else (err (systemExit (str "launch: layer " lid " :from " s " is not a known source"))))))
    ((none) (let [t (optionOr text "")] (ok (fillLoop! t (stringLength t) 0 lookup (list))))))

fn ! renderLayers! g: Grammar have: (List (Pair String Bool)) mode: String only: (List String) lookup: (fn [String] -> (Option String)) layers: (List Layer) acc: (List String) -> (Result (List String) String)
  (if (listEmpty? layers)
    (ok (listReverse acc))
    (mt (c/firstOf layers)
      ((layerOf lid cnd text src)
        (let [rest (c/restOf layers)
              conds (optionOr cnd (list))
              pos (filter (fn [w] (not (stringStartsWith? w "!"))) conds)
              neg (map (fn [w] (sl w 1 (stringLength w))) (filter (fn [w] (stringStartsWith? w "!")) conds))
              unknown (filter (fn [w] (none? (dictAt have w))) (listAppend pos neg))]
          (cond
            ((and (not (listEmpty? only)) (not (listContains? only lid))) (renderLayers! g have mode only lookup rest acc))
            ((not (listEmpty? unknown))
              (err (systemExit (str "launch: layer " lid " names unknown facts " (pyReprList unknown) " in " g.harness))))
            ((and (not (listEmpty? pos)) (not (listAll? (fn [w] (factOf have w)) pos))) (renderLayers! g have mode only lookup rest acc))
            ((listAny? (fn [w] (factOf have w)) neg) (renderLayers! g have mode only lookup rest acc))
            (else
              (mt (layerPart! g mode lid text src lookup)
                ((err e) (err e))
                ((ok p) (renderLayers! g have mode only lookup rest (cons p acc))))))))))

fn layerId l: Layer -> String
  (mt l ((layerOf lid _ _ _) lid))

fn ! render! g: Grammar cwd: String client: String mode: String only: (List String) -> (Result String String)
  (mt (loadHarness! g)
    ((err e) (err e))
    ((ok h)
      (mt (facts! g client cwd mode)
        ((err e) (err e))
        ((ok have)
          (mt (gitState! cwd)
            ((err e) (err e))
            ((ok gs)
              (mt (clientField! g client "shell")
                ((err e) (err e))
                ((ok shell)
                  (mt (toolBriefs! g)
                    ((err e) (err e))
                    ((ok briefs)
                      (mt (clientField! g client "subagent")
                        ((err e) (err e))
                        ((ok sub)
                          (let [ids (map layerId h.layers)
                                unknownOnly (filter (fn [o] (not (listContains? ids o))) only)
                                lookup (fn [key] (fillValue! key cwd gs briefs shell sub))]
                            (if (not (listEmpty? unknownOnly))
                              (err (systemExit (str "launch: cannot render unknown layers " (pyReprList unknownOnly))))
                              (mt (renderLayers! g have mode only lookup h.layers (list))
                                ((err e) (err e))
                                ((ok parts) (ok (str (c/joinSep (map (fn [p] (hostPaths p g.host)) parts) "\n") "\n"))))))))))))))))))

fn harnessError e: String -> String
  (if (stringStartsWith? e "SystemExit: ")
    (str "RuntimeError: ERR_HARNESS: " (sl e 12 (stringLength e)))
    e)

fn ! harnessLayers repoRoot: String rootDir: String mode: String -> (Result String String)
  (let [g (grammarOf repoRoot)]
    (mt (clientField! g "leon" "layers")
      ((err e) (err (harnessError e)))
      ((ok names)
        (if (stringEmpty? (optionOr names ""))
          (err "RuntimeError: ERR_HARNESS: asl/grammar/clients.asn has no (:client :id leon :layers ...)")
          (mt (render! g rootDir "leon" mode (nonEmpty (map pyStrip (stringSplit (optionOr names "") ","))))
            ((err e) (err (harnessError e)))
            ((ok text) (ok (pyStrip text))))))))

fn classEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (= (ch s i) "\""))) (classEnd s (+ i 1) n) i)

fn afterSpace s: String i: Int64 n: Int64 -> (Option Int64)
  (let [a (leftEnd s i n)]
    (if (= a i) none (some a)))

fn effectAt s: String n: Int64 i: Int64 -> (Option (Pair (Pair String String) Int64))
  (if (not (= (sl s i (+ i 3)) ":op"))
    none
    (mt (afterSpace s (+ i 3) n)
      ((none) none)
      ((some a)
        (let [b (classEnd s (+ a 1) n)]
          (if (or (not (= (ch s a) "\"")) (or (>= b n) (= b (+ a 1))))
            none
            (mt (afterSpace s (+ b 1) n)
              ((none) none)
              ((some c1)
                (if (not (= (sl s c1 (+ c1 6)) ":class"))
                  none
                  (mt (afterSpace s (+ c1 6) n)
                    ((none) none)
                    ((some c2)
                      (let [e (wordRun s (+ c2 1) n)]
                        (if (or (not (= (ch s c2) ":")) (= e (+ c2 1)))
                          none
                          (some (pair (pair (sl s (+ a 1) b) (sl s (+ c2 1) e)) e))))))))))))))

fn effectsLoop s: String n: Int64 i: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (if (>= i n)
    acc
    (mt (effectAt s n i)
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

fn writeFact -> String
  "a write or edit step is applied to the file at once inside :owns; a later edit is the only undo; a run that does not end with green gates is handed back as a patch and the files are restored"

fn oldFact -> String
  "quote an :old only from text a receipt still shows whole; before a cut can take them, copy the lines you will edit into (:note ...); after a cut re-read only the lines one edit needs, once"

fn deliverFact -> String
  (str "first state what the task asks you to deliver as (:intent :deliver findings|patch|plan|verdict :why s); "
       "findings that need web or document research add :kind research, and a turn after a search or research step is served by a research model; "
       "a later (:intent ...) restates it; findings are done with (:findings ...) claims that receipts back; "
       "findings accumulate across turns, a claim with the same :file and :anchor replaces the earlier one, "
       "and (:retract :file f :anchor a) inside (:findings ...) drops one; "
       "a patch is done once a write is applied and the declared gates pass; a plan is done with (:note ...) and (:done); "
       "a verdict is done with (:findings ...) citing gate receipts")

fn autoFact -> String
  (str "the task decides the phases, and you choose them in any order, each as often as needed: "
       "scout reads and searches and reports (:findings ...); plan sets the plan as the session (:note ...); "
       "implement writes inside :owns, or anywhere inside the workspace root when no :owns is given; "
       "grade runs the declared gates with (:step :op \"gate\") and cites their receipts; "
       "the run ends with (:done), (:findings ...) or (:escalate :reason s); "
       "(:done :commit s) commits the written paths when the task asks for a commit; "
       "code it writes catches the specific error and handles or reports it; "
       "it never writes a bare except or except Exception followed by pass")

fn noteFact -> String
  (str "a window cut drops older receipts; a (:note ...) survives it, sent whole in every message: "
       "keep in it the decisions, the target file and span, and the next write")

fn lookupFact -> String
  (str "an outline step lists a file's defs and classes with their line spans, cheaper than reading it; "
       "every call site of a function, through aliases and modules: the observe step with :dim callers :symbol s")

fn batchFact -> String
  (str "batching: a turn costs a whole model call and a wrong guess costs one receipt, "
       "so each reply carries every independent read, query, edit and gate step you can foresee; "
       "only a step that needs a receipt not yet seen waits for the next turn, where you recalibrate; "
       "a reply has no limit on steps; three steps in one reply, the edit quoting lines an earlier receipt showed: "
       "(:step :op \"edit\" :file \"src/ring.py\" :old \"return xs[len(xs)]\" :new \"return xs[len(xs) - 1]\") "
       "(:step :op \"read\" :file \"tests/ringTest.sh\" :start 1 :end 60) (:step :op \"gate\" :n 1)"
       "; once the lines to change are seen, the next reply carries the edit")

fn planFact -> String
  (str "plan: your first reply carries (:plan (:step :id s1 :do s :check s) ...) beside its first steps; "
       "the plan is sent whole in every message, and (:now) shows :plan (:done (ids) :current id :turnsOnCurrent n); "
       "(:planDone :id s1 :ev id) marks a step done, citing the :id of a receipt that shows its :check; "
       "(:planDrop :id s :why s) drops a step; (:plan :revise ((:step ...) ...) :why s) replaces the steps not done; "
       "the run is done only when every step is done or dropped")

fn indexed xs: (List String) i: Int64 acc: (List String) -> (List String)
  (if (listEmpty? xs)
    (listReverse acc)
    (indexed (c/restOf xs) (+ i 1) (cons (str "  " (stringFromInt64 i) " \"" (escapeAsn (c/firstOf xs)) "\"") acc)))

fn opt c: Bool x: String -> (List String)
  (if c (list x) (list))

fn ! buildSystemPrompt repoRoot: String task: String rootDir: String base: String gates: (List String) contextTokens: (Option Int64) plan: Bool -> (Result String String)
  (let [effects (loadEffects repoRoot)
        confirm (map pairFirst (filter (fn [e] (listContains? (list "outward" "irreversible" "needsConfirm") (pairSecond e))) effects))
        accepted (map pairFirst (filter (fn [e] (and (= (pairSecond e) "local") (not (= (pairFirst e) "step")))) effects))
        shapes (someOf (map (fn [op] (if (listContains? (list "diff" "flush" "discard") op) none (dictAt (opShapes) op))) accepted))
        head (list "answer contract: a program reads the reply as ASN forms; several forms in one reply run in order; an unbalanced form or over 40 words outside the forms is a parse defect; fenced forms are read"
                   "grounding: a claim holds when a receipt or the given context shows it; what the context and receipts do not show is unknown; (:escalate :reason s) or a (:findings ...) claim naming what is needed carries it to the reader"
                   (str "tools: the step forms below are executed in the workspace by the program that reads your reply, and each receipt comes back next turn; " (writeFact) "; " (oldFact))
                   "scope: paths resolve against the workspace root; a read outside the workspace answers ERR_BOUNDARY_VIOLATION"
                   "done by escalating: when a receipt shows the cause in a file outside :owns, (:escalate :reason s) naming that file and the receipt :id is the finished answer"
                   "evidence: (:evidence (:receipt id)) runs nothing; it cites the :id of a receipt already in the context; a command exit counts as evidence only through a run or gate receipt"
                   (autoFact) (deliverFact))
        shapeText (str "accepted op forms:\n" (c/joinSep (map (fn [s] (str "  " s)) shapes) "\n") "\n"
                       "for code with quotes, backslashes or many lines, use :raw and a fenced block on the following lines as the normal way to send code; the escaped-string form stays accepted for short values without escapes.")
        gateText (str "declared gates; (:step :op \"gate\") runs them all now, :n i the i-th, and they run after every turn that acts; a gate counts when it prints (:gate ... :asserts n :failed 0) with n > 0, and :failed above 0 once the change is reverted:\n"
                      (c/joinSep (indexed gates 1 (list)) "\n"))
        parts (listAppend head
                (listAppend (opt plan (planFact))
                  (listAppend (list (batchFact) (lookupFact))
                    (listAppend (opt (not (listEmpty? confirm)) (str "not run, answered with a needsConfirm receipt: " (c/joinSep confirm ", ")))
                      (listAppend (opt (not (listEmpty? shapes)) shapeText)
                        (listAppend (list "each (:step ...) runs in the workspace; the next message carries the task, each earlier turn as (:turn n :sent <your forms> :got <its receipts>), and last (:now ...) with the files written, the newest gate runs and :last, the newest turn"
                                          (noteFact))
                          (opt (not (listEmpty? gates)) gateText)))))))
        layers (mt contextTokens
                 ((some t) (if (>= t 8000) (harnessLayers repoRoot rootDir "implement") (ok "")))
                 ((none) (ok "")))]
    (mt layers
      ((err e) (err e))
      ((ok lay)
        (ok (c/joinSep (listAppend parts (listAppend (opt (not (stringEmpty? lay)) lay)
                                           (listAppend (opt (not (stringEmpty? task)) (str "Task: " task))
                                                       (opt (not (stringEmpty? base)) (str "Base: " base)))))
                       "\n\n")))))
