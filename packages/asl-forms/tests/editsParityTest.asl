(module asl-forms/tests/editsParityTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/vfs :a v) (asl-forms/edit :a e) (asl-forms/ops :a ops) (asl-json/json :a j) (asl-proc/coreProcess :a proc)])


(schema Replay (:f ws String) (:f steps Int64) (:f failures Int64) (:f loose Int64) (:f diverged Int64))


fn kwOf line: String -> (Map String String)
  (k/parseStep line).kwargs

fn get kw: (Map String String) key: String -> String
  (optionOr (mapGet kw key) "")

fn tmpRoot! -> String
  (let [(t (optionOr (envGet "TMPDIR") "/tmp"))] (resultOr (realPath t) t))

fn firstLine text: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringSplit text "\n")))) "")

fn hostCheck! host: String overlay: String rel: String text: String -> (Pair String String)
  (let [(target (str overlay "/" rel))]
    (do (resultOr (dirCreate (k/dirName target)) ())
        (resultOr (fileWrite target text) ())
        (mt (proc/exec! (proc/withTimeout (proc/withCwd (proc/cmd host (list "check" rel)) overlay) 15000))
          ((err e)
            (mt e
              ((proc/timeout ms) (pair "error" (str "asl-host check timed out after " (stringFromInt64 (/ ms 1000)) "s")))
              (_ (pair "error" "asl-host check did not run"))))
          ((ok o)
            (if (= o.exitCode 0)
              (pair "ok" "")
              (let [(both (stringJoin (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (list o.stderr o.stdout)) "\n"))
                    (cut (stringReplace (stringReplace both (str (resultOr (realPath overlay) overlay) "/") "") (str overlay "/") ""))
                    (line (firstLine cut))]
                (pair "error" (optionOr (stringSlice (if (stringEmpty? line) (str "asl-host check exit " (stringFromInt64 o.exitCode)) line) 0 300) line))))))))

fn aslCheckIn! ws: String host: String p: String after: String before: (Option String) -> e/SyntaxResult
  (let [(overlay (str (tmpRoot!) "/aslOverlay" (stringFromInt64 (nowNs))))
        (rel (k/relPath p ws))
        (r (hostCheck! host overlay rel after))
        (pre (if (= (pairFirst r) "error") (mt before ((some b) (pairFirst (hostCheck! host overlay rel b))) ((none) "")) ""))]
    (do (resultOr (pathRemove overlay) ())
        (e/SyntaxResult :status (pairFirst r) :message (pairSecond r) :before pre :host "")))

fn routed! ws: String host: String -> e/Checkers
  (e/Checkers :aslCheck (fn [(p String) (after String) (before (Option String))] -> e/SyntaxResult (aslCheckIn! ws host p after before))
              :foreignCheck (fn [(p String) (content String)] -> e/SyntaxResult (e/SyntaxResult :status "skipped" :message "foreign syntax check not configured" :before "" :host "")))

fn vfsFor! ws: String session: String -> v/Vfs
  (let [(dir (str ws "/.asl/vfs"))]
    (do (resultOr (dirCreate dir) ()) (v/vfsAt ws dir session)))

fn dispatch! vs: v/Vfs ch: e/Checkers id: Int64 form: String held: (List String) -> ops/StepOutcome
  (let [(p (k/parseStep form))
        (run (fn [(n Int64) (f String) (h (List String))] -> k/EditOutcome
                   (let [(r (dispatch! vs ch n f h))] (k/EditOutcome :lines r.lines :errCount r.errCount))))]
    (mt (e/editOp! vs ch run held id p.op p.kwargs p.args)
      ((some out) (ops/StepOutcome :lines out.lines :errCount out.errCount))
      ((none) (ops/runStep! vs.root id form))))

fn octal n: Int64 -> String
  (if (< n 8) (stringFromInt64 n) (str (octal (/ n 8)) (stringFromInt64 (mod n 8))))

fn treeRows! ws: String rel: String -> (List String)
  (let [(dir (if (stringEmpty? rel) ws (str ws "/" rel)))]
    (mt (dirList dir)
      ((err _) (list))
      ((ok names)
        (fold (fn [(acc (List String)) (name String)] -> (List String)
                (let [(r (if (stringEmpty? rel) name (str rel "/" name)))
                      (full (str ws "/" r))]
                  (cond
                    ((and (stringEmpty? rel) (= name ".asl")) acc)
                    ((v/isLink? full) (cons (str "L " r " " (mt (proc/runSimple! "readlink" (list full)) ((ok t) t) ((err _) "?"))) acc))
                    ((k/isDir! full) (listAppend (cons (str "D " r) acc) (treeRows! ws r)))
                    (else
                      (let [(mode (mt (fileStat full) ((ok st) (& st.mode 4095)) ((err _) 0)))
                            (sha (mt (fileReadBytes full) ((ok b) (bytesSha256 b)) ((err x) x)))]
                        (cons (str "F " r " " (octal mode) " " sha) acc))))))
              (list)
              names))))

fn tree! ws: String -> String
  (stringJoin (listSort (treeRows! ws "")) "\n")

fn jtext obj: j/Json key: String -> String
  (mt (j/jsonGet obj key) ((some x) (mt x ((j/jstr s) s) (_ ""))) ((none) ""))

fn jbool obj: j/Json key: String -> String
  (mt (j/jsonGet obj key) ((some x) (mt x ((j/jbool b) (if b "true" "false")) (_ "none"))) ((none) "none"))

fn metaRow! ws: String sess: String dir: String name: String -> String
  (let [(text (resultOr (fileReadString (str dir "/" name)) ""))
        (meta (resultOr (j/jsonParse text) (j/jnull)))
        (blob (mt (fileReadBytes (str dir "/" (optionOr (stringSlice name 0 (- (stringLength name) 5)) "") ".blob")) ((ok b) (bytesSha256 b)) ((err x) x)))
        (sha (jtext meta "baseSha"))]
    (str sess " " (k/relPath (jtext meta "path") ws) " " blob " " (if (stringEmpty? sha) "-" sha) " " (jbool meta "baseExists") " " (v/shaText (stringReplace text ws "@WS@"))))

fn storeRows! ws: String sess: String dir: String -> (List String)
  (mt (dirList dir)
    ((err _) (list))
    ((ok names)
      (fold (fn [(acc (List String)) (name String)] -> (List String)
              (cond
                ((stringEndsWith? name ".meta") (cons (metaRow! ws sess dir name) acc))
                ((and (= sess ".") (k/isDir! (str dir "/" name))) (listAppend acc (storeRows! ws name (str dir "/" name))))
                (else acc)))
            (list)
            names)))

fn staged! ws: String -> String
  (stringJoin (listSort (storeRows! ws "." (str ws "/.asl/vfs"))) "\n")

fn sh! bin: String args: (List String) -> Bool
  (mt (proc/runSimple! bin args)
    ((ok _) true)
    ((err _) (do (println (str "(:harnessError :bin " bin " :args \"" (k/escapeAsnVal (stringJoin args " ")) "\")")) false)))

fn setupFile! r: Replay kw: (Map String String) -> Replay
  (let [(path (str r.ws "/" (get kw "path")))]
    (do (resultOr (dirCreate (k/dirName path)) ())
        (resultOr (fileWrite path (get kw "content")) ())
        (sh! "chmod" (list (octal (optionOr (stringToInt64 (get kw "mode")) 420)) path))
        r))

fn addLink! r: Replay rel: String target: String -> Replay
  (do (resultOr (dirCreate (k/dirName (str r.ws "/" rel))) ())
      (sh! "ln" (list "-s" target (str r.ws "/" rel)))
      r)

fn harness! r: Replay form: String -> Replay
  (let [(kw (kwOf form))
        (rel (get kw "path"))
        (path (str r.ws "/" rel))]
    (cond
      ((mapHas? kw "disk") (do (resultOr (dirCreate (k/dirName path)) ()) (resultOr (fileWrite path (get kw "content")) ()) r))
      ((mapHas? kw "rm") (do (resultOr (pathRemove path) ()) r))
      ((mapHas? kw "symlink") (addLink! r rel (get kw "target")))
      (else r)))

fn firstDiff a: String b: String i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (!= (stringSlice a i (+ i 1)) (stringSlice b i (+ i 1)))) i (firstDiff a b (+ i 1) n))

fn around s: String at: Int64 -> String
  (optionOr (stringSlice s (max 0 (- at 50)) (min (stringLength s) (+ at 70))) "")

fn report! kw: (Map String String) field: String want: String got: String -> Bool
  (if (= want got)
    true
    (let [(at (firstDiff want got 0 (max (stringLength want) (stringLength got))))]
      (do (println (str "(:editsDiff :scenario \"" (get kw "scenario") "\" :n " (get kw "n") " :field " field " :byte " (stringFromInt64 at)
                        " :want \"" (k/escapeAsnVal (around want at)) "\" :got \"" (k/escapeAsnVal (around got at)) "\")"))
          false)))

fn hostTail part: String -> String
  (mt (stringIndexOf part "\"") ((some i) (str "*" (optionOr (stringSlice part i (stringLength part)) ""))) ((none) part))

fn normHost s: String -> String
  (let [(parts (stringSplit s ":syntaxHost \"python"))]
    (stringJoin (cons (optionOr (listHead parts) "") (map hostTail (optionOr (listTail parts) (list)))) ":syntaxHost \"python"))

fn step! r: Replay kw: (Map String String) exact: Bool host: String -> Replay
  (let [(form (get kw "form"))
        (n (optionOr (stringToInt64 (get kw "n")) 0))
        (isHarness (stringStartsWith? form "(:harness"))
        (r2 (if isHarness (harness! r form) r))
        (out (if isHarness (ops/StepOutcome :lines (list) :errCount 0) (dispatch! (vfsFor! r.ws (get kw "session")) (routed! r.ws host) n form (list))))
        (lines (normHost (stringJoin out.lines "\n")))
        (diverged (mapHas? kw "linesAsl"))
        (want (normHost (get kw (if diverged "linesAsl" "lines"))))
        (loose (and (not exact) (= (get kw "hashOrder") "true")))
        (linesOk (if loose (= (stringLength lines) (stringLength want)) (report! kw "lines" want lines)))
        (errOk (report! kw "err" (get kw "err") (stringFromInt64 out.errCount)))
        (treeOk (report! kw "tree" (get kw "tree") (tree! r.ws)))
        (stagedOk (report! kw "staged" (get kw "staged") (staged! r.ws)))
        (ok (and linesOk errOk treeOk stagedOk))]
    (Replay :ws r2.ws :steps (+ r.steps 1) :failures (+ r.failures (if ok 0 1)) :loose (+ r.loose (if loose 1 0)) :diverged (+ r.diverged (if diverged 1 0))))

fn fresh! parent: String sid: String -> Replay
  (let [(ws (str parent "/" sid))]
    (do (resultOr (pathRemove ws) ())
        (resultOr (dirCreate (str ws "/.asl")) ())
        (Replay :ws ws :steps 0 :failures 0 :loose 0 :diverged 0)))

fn tally a: Replay b: Replay -> Replay
  (with b :steps (+ a.steps b.steps) :failures (+ a.failures b.failures) :loose (+ a.loose b.loose) :diverged (+ a.diverged b.diverged))

fn replayAll! parent: String exact: Bool host: String lines: (List String) cur: Replay sid: String total: Replay -> Replay
  (mt (listHead lines)
    ((none) (tally total cur))
    ((some line)
      (let [(rest (optionOr (listTail lines) (list)))
            (kw (kwOf line))
            (lsid (get kw "scenario"))
            (switch (and (not (stringEmpty? lsid)) (!= lsid sid)))
            (total2 (if (and switch (not (stringEmpty? sid))) (tally total cur) total))
            (base (if switch (fresh! parent lsid) cur))]
        (cond
          ((stringStartsWith? line "(:file ") (replayAll! parent exact host rest (setupFile! base kw) lsid total2))
          ((stringStartsWith? line "(:link ") (replayAll! parent exact host rest (addLink! base (get kw "path") (get kw "target")) lsid total2))
          ((stringStartsWith? line "(:step ") (replayAll! parent exact host rest (step! base kw exact host) lsid total2))
          (else (replayAll! parent exact host rest cur sid total))))))

fn unitChecks! root: String -> Bool
  (let [(ws (str root "/unit"))
        (vs (do (resultOr (pathRemove ws) ()) (resultOr (dirCreate (str ws "/.asl")) ()) (resultOr (dirCreate (str ws "/bare")) ()) (vfsFor! ws "")))
        (dirOf (fn [(r (Result v/Vfs String))] -> String (mt r ((ok c) c.dir) ((err x) (str "err " x)))))
        (envDir (optionOr (envGet "ASL_VFS_DIR") ""))
        (lp (v/lockPath vs (str ws "/a.txt")))]
    (do
      (assert (= (dirOf (v/vfsContextFrom! ws "" "" "/h")) (str ws "/.asl/vfs")) "without ASL_VFS_DIR a workspace with .asl keeps its store in .asl/vfs")
      (assert (= (dirOf (v/vfsContextFrom! ws (str ws "/given") "" "/h")) (str ws "/given")) "ASL_VFS_DIR set names the store")
      (assert (= (dirOf (v/vfsContextFrom! (str ws "/bare") "" "" ws)) (str ws "/.cache/asl/vfs/" (optionOr (stringSlice (v/shaText (str ws "/bare")) 0 16) ""))) "a workspace without .asl stores under the home cache by root digest")
      (assert (stringStartsWith? (dirOf (v/vfsContextFrom! ws "" "a/b" "/h")) "err ASL_SESSION must match") "a session naming a path is refused")
      (assert (= (dirOf (v/vfsContext! ws)) (if (stringEmpty? envDir) (str ws "/.asl/vfs") envDir)) "vfsContext reads ASL_VFS_DIR from the environment, set or unset")
      (assert (mt (v/lockAcquire! vs (str ws "/a.txt")) ((ok fd) (and (= (fileLock lp true) (err "busy")) (resultOk? (v/lockRelease! vs (str ws "/a.txt") fd)) (not (fileExists? lp)))) ((err _) false))
              "a held lock is busy to another open, and release removes the lock file when nothing is staged")
      (assert (= (v/withLock! vs (list lp) (str ws "/a.txt") (fn [] -> Int64 7)) (ok 7)) "a lock the caller already holds is re-entered without flock")
      (assert (= (v/jsonQuote "a\"\\\n\x01é𝄞") "\"a\\\"\\\\\\n\\u0001\\u00e9\\ud834\\udd1e\"") "metas quote strings as json.dumps with ensure_ascii")
      (assert (and (e/fnmatch "sub/x/y.txt" "sub/*") (e/fnmatch "b.txt" "[a-c].txt") (not (e/fnmatch "d.txt" "[!d].txt")) (e/fnmatch "a?c" "a?c") (not (e/fnmatch "sub" "sub/*"))) "fnmatch: * crosses slashes, classes and negation")
      (assert (= (e/parseOwns "(\"a b\" c)") (list "a b")) "quoted owns win over bare words")
      (assert (= (e/parseOwns "(sub [x] true)") (list "sub" "x")) "bare owns split on space and brackets, true dropped")
      (assert (and (e/linesFailed (list "  (:step :id 3 :op \"edit\" :file \"x\" :status \"rejected\" :error-code \":E\")") 0)
                   (not (e/linesFailed (list "(:step :id 3 :op \"edit\" :status \"ok\" :note \"x :status \\\"rejected\\\"\")") 0)))
              "a rejected status after quoted pairs fails the step; the same words inside a value do not")
      (assert (= (e/unifiedDiff! (list "a\n" "b\n") (list "a\n" "c\n") "x" "y" 2) (list "--- x\n" "+++ y\n" "@@ -1,2 +1,2 @@\n" " a\n" "-b\n" "+c\n")) "unified diff of a one-line change")
      (assert (listEmpty? (e/unifiedDiff! (list "same\n") (list "same\n") "x" "y" 2)) "equal sequences give no diff lines")
      (let [(chBad (routed! ws "/nonexistent/path/to/asl-host"))
            (vBad (e/validateStaged! chBad (str ws "/foo.asl") (none) "(module foo :x [] :i [])\n" false))
            (wBad (e/writeStep! vs chBad (list) 99 (mapEmpty) (list "foo.asl" "(module foo :x [] :i [])\n")))]
        (assert (= vBad.code ":ERR_CHECK_FAILED") "validation with a nonexistent host path fails with ERR_CHECK_FAILED")
        (assert (= wBad.errCount 1) "writeStep with nonexistent host fails with an error"))
      (resultOr (pathRemove ws) ())
      true))

fn resultOk? r: (Result Unit String) -> Bool
  (mt r ((ok _) true) ((err _) false))

fn currentHost! repo: String -> (Option String)
  (mt (envGet "ASL_HOST")
    ((some h) (if (fileExists? h)
                (some (resultOr (realPath h) h))
                (do (println (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (assert false (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (none))))
    ((none) (let [(p (str repo "/asl/host/out/asl-host"))]
              (if (fileExists? p)
                (some (resultOr (realPath p) p))
                (do (println (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (assert false (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (none))))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (text (resultOr (fileReadString (str root "/asl/packages/asl-forms/tests/fixtures/recorded/edits.asn")) ""))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:")) (stringSplit text "\n")))
        (header (kwOf (optionOr (listHead lines) "")))
        (recorded (get header "wsParent"))
        (here (str (resultOr (realPath "/tmp") "/tmp") "/aslFormsEdits"))
        (exact (= recorded here))
        (want (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:step ")) lines)))]
    (assert (= (get header "base") "75a7d7ba") "the fixture is pinned to base 75a7d7ba")
    (assert (>= want 120) "the fixture holds at least 120 recorded steps")
    (assert (unitChecks! here) "unit checks ran")
    (mt (currentHost! root)
      ((none) false)
      ((some host)
       (let [(zero (Replay :ws "" :steps 0 :failures 0 :loose 0 :diverged 0))
             (r (replayAll! here exact host lines zero "" zero))
             (compared (listLength (filter (fn [(l String)] -> Bool (stringContains? l " :compare \"")) lines)))]
         (do
           (resultOr (pathRemove here) ())
           (println (str "(:editsParity :steps " (stringFromInt64 r.steps) " :failures " (stringFromInt64 r.failures) " :hashOrderLoose " (stringFromInt64 r.loose) " :divergences " (stringFromInt64 r.diverged) " :exactRoot " (if exact "true" "false") ")"))
           (assert (= r.steps want) "every recorded step replayed")
           (assert (and (> compared 0) (= r.diverged compared)) "every :compare step is checked against its recorded ASL receipt")
           (assert (= r.failures 0) "every step gives the recorded receipt, error count, tree and staged store")
           true)))))
