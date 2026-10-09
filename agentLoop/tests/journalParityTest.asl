(module asl/agentLoop/tests/journalParityTest
  :x [runTests]
  :i [(asl/agentLoop/journal :a j) (asl/agentLoop/tests/parity :a t) (asl/agentLoop/plan :a p) (asl/agentLoop/core :a c) (asl-proc/coreProcess :a cp)])

fn fixturePath -> String
  "asl/agentLoop/tests/journalParityFixtures.asn"

fn ! baseSha -> String
  (let [head (optionOr (listHead (stringLines (resultOr (fileReadString (fixturePath)) ""))) "")
        k (optionOr (stringIndexOf head ":base \"") -1)]
    (if (< k 0) "" (c/sliceOf head (+ k 7) (+ k 47))))

fn ! repoRoot -> String
  (resultOr (realPath ".") ".")

fn gitEnv c: cp/ProcessCmd -> cp/ProcessCmd
  (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv)))
        c
        (list (pair "GIT_AUTHOR_NAME" "t") (pair "GIT_AUTHOR_EMAIL" "t@t") (pair "GIT_COMMITTER_NAME" "t")
              (pair "GIT_COMMITTER_EMAIL" "t@t") (pair "GIT_AUTHOR_DATE" "2026-01-01T00:00:00Z")
              (pair "GIT_COMMITTER_DATE" "2026-01-01T00:00:00Z")))

fn ! gitRun! cwd: String args: (List String) -> (Result String String)
  (mt (cp/exec! (gitEnv (cp/withTimeout (cp/withCwd (cp/cmd "git" (listAppend (list "-c" "commit.gpgsign=false" "-c" "core.hooksPath=/dev/null" "-c" "init.defaultBranch=main") args)) cwd) 60000)))
    ((ok o) (if (= o.exitCode 0) (ok o.stdout) (err (str "git " (c/joinSep args " ") ": " o.stderr))))
    ((err _) (err "git did not start")))

fn ! baseBlob! rel: String -> (Result String String)
  (let [spec (str (baseSha) ":" rel)]
    (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" (list "show" spec)) (repoRoot)) 60000))
      ((err _) (err "git did not start"))
      ((ok o)
        (if (not (= o.exitCode 0))
          (err (str "git show " spec " failed"))
          (mt (cp/exec! (cp/withCwd (cp/cmd "git" (list "cat-file" "-s" spec)) (repoRoot)))
            ((err _) (err "git did not start"))
            ((ok s)
              (let [size (optionOr (stringToInt64 (stringTrim s.stdout)) -1)]
                (ok (if (= size (+ (stringLength o.stdout) 1)) (str o.stdout "\n") o.stdout)))))))))

fn ! writeUnder! root: String rel: String text: String -> (Result String String)
  (let [path (str root "/" rel)]
    (mt (dirCreate (j/pathDirname path))
      ((err e) (err e))
      ((ok _) (mt (fileWrite path text) ((ok _) (ok "")) ((err e) (err e))))))

fn ! chmodPath! path: String mode: String -> (Result String String)
  (mt (cp/exec! (cp/cmd "chmod" (list mode path)))
    ((ok o) (if (= o.exitCode 0) (ok "") (err o.stderr)))
    ((err _) (err "chmod did not start")))

fn ! setupStep! root: String step: (List String) -> (Result String String)
  (let [kind (optionOr (listHead step) "")
        a1 (optionOr (listGet step 1) "")
        a2 (optionOr (listGet step 2) "")]
    (cond
      ((= kind "dir") (mt (dirCreate (str root "/" a1)) ((ok _) (ok "")) ((err e) (err e))))
      ((= kind "file") (writeUnder! root a1 a2))
      ((= kind "mode") (chmodPath! (str root "/" a1) a2))
      ((= kind "base") (mt (baseBlob! a2) ((err e) (err e)) ((ok text) (writeUnder! root a1 text))))
      ((= kind "git") (gitRun! (str root "/" a1) (listDrop step 2)))
      ((= kind "rm") (mt (pathRemove (str root "/" a1)) ((ok _) (ok "")) ((err e) (err e))))
      (else (err (str "unknown setup step " kind)))))

fn ! setup! root: String steps: (List p/SexpNode) -> (Result String String)
  (fold (fn [acc st] (mt acc ((err e) (err e)) ((ok _) (setupStep! root (t/argStrs st))))) (ok "") steps)

fn ! tempRoot! n: Int64 -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/u6jt_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 n))]
    (do (dirCreate path) (resultOr (realPath path) path)))

fn norm root: String s: String -> String
  (stringReplace s root "@ROOT@")

fn subRoot root: String s: String -> String
  (stringReplace s "@ROOT@" root)

fn ! walk! root: String rel: String -> (List (Pair String String))
  (let [dir (if (stringEmpty? rel) root (str root "/" rel))
        names (filter (fn [nm] (not (= nm ".git"))) (resultOr (dirList dir) (list)))]
    (fold (fn [acc nm]
            (let [r (if (stringEmpty? rel) nm (str rel "/" nm))
                  full (str root "/" r)]
              (mt (fileStat full)
                ((ok st)
                  (if st.isDir
                    (listAppend (listAppend acc (list (pair (str r "/") (t/sList (list (t/sStr (str r "/")) "nil" "nil"))))) (walk! root r))
                    (listAppend acc (list (pair r (t/sList (list (t/sStr r) (t/sStr (norm root (resultOr (fileReadString full) ""))) (t/sInt (& st.mode 511)))))))))
                ((err _) acc))))
          (list) names))

fn ! tree! root: String -> String
  (t/sList (map pairSecond (listSortBy pairFirst (walk! root ""))))

fn ! status! root: String rel: String -> String
  (mt (cp/exec! (cp/withCwd (cp/cmd "git" (list "status" "--porcelain=v1" "--untracked-files=all")) (str root "/" rel)))
    ((ok o) (t/sStr (if (= o.exitCode 0) (if (stringEmpty? o.stdout) "" (str o.stdout "\n")) "not a repo")))
    ((err _) (t/sStr "not a repo")))

fn snapSer root: String s: j/Snapshot -> String
  (t/sDict (list (pair "bytes" (mt s.bytes ((some b) (t/sStr (norm root b))) ((none) "nil")))
                 (pair "mode" (t/sOptInt s.mode))
                 (pair "dirs" (t/sStrs (map (fn [d] (norm root d)) s.dirs)))))

fn filesSer root: String w: j/Written -> String
  (mt w.files
    ((none) "nil")
    ((some fs) (t/sDict (map (fn [pr] (pair (pairFirst pr) (snapSer root (pairSecond pr)))) fs))))

fn raised root: String e: String -> String
  (t/sDict (list (pair "raise" (t/sStr (norm root e)))))

fn optNorm root: String o: (Option String) -> String
  (mt o ((some s) (t/sStr (norm root s))) ((none) "nil"))

fn ! snapCalls! root: String w: j/Written calls: (List p/SexpNode) -> (Result j/Written String)
  (fold (fn [acc call]
          (mt acc
            ((err e) (err e))
            ((ok w1)
              (let [parts (t/argItems call)]
                (mt (j/snapshotBeforeWrite w1 (subRoot root (t/argStr (t/argAt parts 0))))
                  ((err e) (err e))
                  ((ok w2) (mt (setup! root (t/argItems (t/argAt parts 1))) ((err e) (err e)) ((ok _) (ok w2)))))))))
        (ok w) calls)

fn ! snapPaths! w: j/Written paths: (List String) -> (Result j/Written String)
  (fold (fn [acc path] (mt acc ((err e) (err e)) ((ok w1) (j/snapshotBeforeWrite w1 path)))) (ok w) paths)

fn ! headOf! dir: String -> String
  (mt (cp/exec! (cp/withCwd (cp/cmd "git" (list "rev-parse" "HEAD")) dir)) ((ok o) (stringTrim o.stdout)) ((err _) ""))

fn pickHead head: String n: p/SexpNode -> (Option String)
  (if (t/argNil? n) none (some (if (= (t/argStr n) "@HEAD@") head (t/argStr n))))

fn ! fsCase! n: Int64 args: (List p/SexpNode) body: (fn [String (List p/SexpNode)] -> String) -> String
  (let [root (tempRoot! n)
        out (mt (setup! root (t/argItems (t/argAt args 0)))
              ((err e) (str "(setup failed " (t/sStr e) ")"))
              ((ok _) (body root (listDrop args 1))))]
    (do (pathRemove root) out))

fn ! journalWriteCase root: String a: (List p/SexpNode) -> String
  (mt (j/journalWrite (subRoot root (t/argStr (t/argAt a 0))) (t/argStr (t/argAt a 1)))
    ((err e) (raised root e))
    ((ok _) (t/sDict (list (pair "tree" (tree! root))))))

fn ! snapshotCase root: String a: (List p/SexpNode) -> String
  (let [w0 (if (t/argBool (t/argAt a 0)) (j/newWritten root none) (j/idleWritten root))]
    (mt (snapCalls! root w0 (t/argItems (t/argAt a 1)))
      ((err e) (raised root e))
      ((ok w) (t/sDict (list (pair "files" (filesSer root w)) (pair "tree" (tree! root)))))))

fn ! retainCase root: String a: (List p/SexpNode) -> String
  (mt (j/retainJournal (subRoot root (t/argStr (t/argAt a 0))) (subRoot root (t/argStr (t/argAt a 1))) (t/argStr (t/argAt a 2)))
    ((err e) (raised root e))
    ((ok _) (t/sDict (list (pair "tree" (tree! root))))))

fn ! resumeCase root: String a: (List p/SexpNode) -> String
  (let [rootDir (subRoot root (t/argStr (t/argAt a 2)))]
    (mt (j/applyResumePatch (j/newWritten rootDir none) rootDir (subRoot root (t/argStr (t/argAt a 0))) (t/argStr (t/argAt a 1)))
      ((err e) (raised root e))
      ((ok res)
        (t/sDict (list (pair "ret" (t/sList (list (optNorm root (pairFirst (pairSecond res))) (optNorm root (pairSecond (pairSecond res))))))
                       (pair "files" (filesSer root (pairFirst res)))
                       (pair "tree" (tree! root))
                       (pair "status" (status! root "r")))))))

fn ! handBackCase root: String a: (List p/SexpNode) -> String
  (let [rdir (str root "/r")
        head (headOf! rdir)
        w0 (j/newWritten rdir (pickHead head (t/argAt a 0)))]
    (mt (snapPaths! w0 (t/argStrs (t/argAt a 1)))
      ((err e) (raised root e))
      ((ok w1)
        (mt (setup! root (t/argItems (t/argAt a 2)))
          ((err e) (str "(mutate failed " (t/sStr e) ")"))
          ((ok _)
            (mt (j/handBack w1 rdir (subRoot root (t/argStr (t/argAt a 3))) (t/argStr (t/argAt a 4)) (t/argBool (t/argAt a 5)) (pickHead head (t/argAt a 6)))
              ((err e) (raised root e))
              ((ok res)
                (t/sDict (list (pair "ret" (t/sList (list (optNorm root (pairFirst (pairSecond res))) (t/sStrs (map (fn [x] (norm root x)) (pairSecond (pairSecond res)))))))
                               (pair "files" (filesSer root (pairFirst res)))
                               (pair "tree" (tree! root))
                               (pair "status" (status! root "r")))))))))))

fn retSer root: String r: (Result String String) -> String
  (mt r
    ((ok s) (t/sDict (list (pair "ret" (t/sStr (norm root s))))))
    ((err e) (raised root e)))

fn ! harnessCase root: String a: (List p/SexpNode) -> String
  (retSer root (j/harnessLayers (subRoot root (t/argStr (t/argAt a 2))) (subRoot root (t/argStr (t/argAt a 0))) (t/argStr (t/argAt a 1))))

fn ! promptCase root: String a: (List p/SexpNode) -> String
  (retSer root (j/buildSystemPrompt (subRoot root (t/argStr (t/argAt a 6))) (t/argStr (t/argAt a 0)) (subRoot root (t/argStr (t/argAt a 1)))
                                    (t/argStr (t/argAt a 2)) (t/argStrs (t/argAt a 3)) (t/argOptInt (t/argAt a 4)) (t/argBool (t/argAt a 5))))

fn ! filePatchCase a: (List p/SexpNode) -> String
  (let [old (t/argOptStr (t/argAt a 1))
        new (t/argOptStr (t/argAt a 2))
        size (+ (stringLength (optionOr old "")) (stringLength (optionOr new "")))
        t0 (monotonicNs)
        out (j/filePatch! (t/argStr (t/argAt a 0)) old new (t/argInt (t/argAt a 3)))
        ms (/ (- (monotonicNs) t0) 1000000)]
    (do
      (if (> size 100000) (do (assert (< ms 5000) (str "filePatch on " (stringFromInt64 size) " bytes took " (stringFromInt64 ms) " ms")) true) true)
      (t/sStr out)))

fn ! dispatch! n: Int64 fname: String a: (List p/SexpNode) -> String
  (cond
    ((= fname "writtenField") (t/sStr (j/writtenField (t/argStrs (t/argAt a 0)))))
    ((= fname "handBackFields") (t/sStr (j/handBackFields (t/argOptStr (t/argAt a 0)) (t/argStrs (t/argAt a 1)))))
    ((= fname "patchLines") (t/sStrs (j/patchLines (t/argOptStr (t/argAt a 0)))))
    ((= fname "filePatch") (filePatchCase a))
    ((= fname "journalWrite") (fsCase! n a journalWriteCase))
    ((= fname "snapshotBeforeWrite") (fsCase! n a snapshotCase))
    ((= fname "retainJournal") (fsCase! n a retainCase))
    ((= fname "applyResumePatch") (fsCase! n a resumeCase))
    ((= fname "handBack") (fsCase! n a handBackCase))
    ((= fname "harnessLayers") (fsCase! n a harnessCase))
    ((= fname "buildSystemPrompt") (fsCase! n a promptCase))
    (else (str "(unknown fn " fname ")")))

fn ! runTests -> Bool
  (let [fns (list "harnessLayers" "buildSystemPrompt" "retainJournal" "journalWrite" "snapshotBeforeWrite" "patchLines"
                  "filePatch" "applyResumePatch" "handBack" "writtenField" "handBackFields")
        passed (t/replay! (fixturePath) fns (fn [fname args] (dispatch! (monotonicNs) fname args)))]
    (do
      (assert (= (stringLength (baseSha)) 40) "the fixture names its 40-hex base")
      (> passed 0)))
