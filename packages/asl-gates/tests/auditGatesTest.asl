(module ws/auditGatesTest
  :x [runTests]
  :i [(asl-gates/auditGates :a ag) (asl-gates/auditMain :a am) (asl-gates/suiteRunner :a sr) (asl-proc/coreProcess :a p) (asl-proc/gitFixture :a gf)])

enum AVal
  (aStr raw: String)
  (aKw name: String)
  (aNum v: Int64)
  (aSym name: String)
  (aList items: (List AVal))

(schema Tally
  (:f cases Int64)
  (:f pinned (List String))
  (:f fails (List String)))

fn fixturePath -> String
  "tests/parity/audit/auditFixture.asn"

fn byteAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn cut s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn spaceOrComment bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (byteAt bs n i))]
    (cond
      ((or (= b 32) (= b 10) (= b 9) (= b 13)) (spaceOrComment bs n (+ i 1)))
      ((= b 59) (spaceOrComment bs n (lineEnd bs n i)))
      (else i)))

fn lineEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (lineEnd bs n (+ i 1)))

fn strClose bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet bs i) 34) i)
    ((= (bytesGet bs i) 92) (strClose bs n (+ i 2)))
    (else (strClose bs n (+ i 1))))

fn tokenEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (byteAt bs n i))]
    (if (or (< b 0) (= b 32) (= b 10) (= b 9) (= b 13) (= b 40) (= b 41) (= b 34)) i (tokenEnd bs n (+ i 1))))

fn readList s: String bs: Bytes n: Int64 i: Int64 acc: (List AVal) -> (Result (Pair AVal Int64) String)
  (let [(j (spaceOrComment bs n i))]
    (cond
      ((>= j n) (err "unclosed list"))
      ((= (bytesGet bs j) 41) (ok (pair (aList (listReverse acc)) (+ j 1))))
      (else
       (mt (readVal s bs n j)
         ((err e) (err e))
         ((ok vr) (readList s bs n (pairSecond vr) (cons (pairFirst vr) acc)))))))

fn readVal s: String bs: Bytes n: Int64 i: Int64 -> (Result (Pair AVal Int64) String)
  (let [(j (spaceOrComment bs n i)) (b (byteAt bs n j))]
    (cond
      ((< b 0) (err "value expected at end"))
      ((= b 40) (readList s bs n (+ j 1) (list)))
      ((= b 34)
       (let [(k (strClose bs n (+ j 1)))]
         (if (< k 0) (err (str "unterminated string at " (stringFromInt64 j))) (ok (pair (aStr (cut s (+ j 1) k)) (+ k 1))))))
      (else
       (let [(k (tokenEnd bs n j)) (tok (cut s j k))]
         (cond
           ((= k j) (err (str "unexpected byte at " (stringFromInt64 j))))
           ((stringStartsWith? tok ":") (ok (pair (aKw (cut tok 1 (stringLength tok))) k)))
           (else (mt (stringToInt64 tok) ((some v) (ok (pair (aNum v) k))) ((none) (ok (pair (aSym tok) k))))))))))

fn readAll s: String bs: Bytes n: Int64 i: Int64 acc: (List AVal) -> (Result (List AVal) String)
  (let [(j (spaceOrComment bs n i))]
    (if (>= j n)
      (ok (listReverse acc))
      (mt (readVal s bs n j)
        ((err e) (err e))
        ((ok vr) (readAll s bs n (pairSecond vr) (cons (pairFirst vr) acc))))))

fn itemsOf v: AVal -> (List AVal)
  (mt v ((aList xs) xs) ((aStr _) (list)) ((aKw _) (list)) ((aNum _) (list)) ((aSym _) (list)))

fn kwName v: AVal -> String
  (mt v ((aKw k) k) ((aStr _) "") ((aNum _) "") ((aSym _) "") ((aList _) ""))

fn symName v: AVal -> String
  (mt v ((aSym k) k) ((aStr _) "") ((aNum _) "") ((aKw _) "") ((aList _) ""))

fn numOf v: AVal -> Int64
  (mt v ((aNum k) k) ((aStr _) -1) ((aSym _) -1) ((aKw _) -1) ((aList _) -1))

fn strRaw v: AVal -> (Option String)
  (mt v ((aStr r) (some r)) ((aNum _) (none)) ((aSym _) (none)) ((aKw _) (none)) ((aList _) (none)))

fn headOf v: AVal -> String
  (mt (listHead (itemsOf v)) ((some x) (kwName x)) ((none) ""))

fn plGet xs: (List AVal) key: String -> (Option AVal)
  (mt (listHead xs)
    ((none) (none))
    ((some x)
     (let [(rest (optionOr (listTail xs) (list)))]
       (mt x
         ((aKw k) (if (= k key) (listHead rest) (plGet (optionOr (listTail rest) (list)) key)))
         ((aStr _) (plGet rest key))
         ((aNum _) (plGet rest key))
         ((aSym _) (plGet rest key))
         ((aList _) (plGet rest key))))))

fn field v: AVal key: String -> (Option AVal)
  (plGet (optionOr (listTail (itemsOf v)) (list)) key)

fn hexVal b: Int64 -> Int64
  (cond
    ((and (>= b 48) (<= b 57)) (- b 48))
    ((and (>= b 97) (<= b 102)) (- b 87))
    ((and (>= b 65) (<= b 70)) (- b 55))
    (else -1))

fn asciiChar b: Int64 -> String
  (cut " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- b 32) (- b 31))

fn controlChar b: Int64 -> String
  (cut "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f" b (+ b 1))

fn decodeText raw: String -> (Result String String)
  (let [(bs (stringToBytes raw))]
    (textLoop raw bs (bytesLength bs) 0 0 (list)))

fn textLoop raw: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (Result String String)
  (cond
    ((>= i n) (ok (stringJoin (listReverse (cons (cut raw start n) acc)) "")))
    ((!= (bytesGet bs i) 92) (textLoop raw bs n (+ i 1) start acc))
    (else
     (let [(e (byteAt bs n (+ i 1)))
           (pre (cons (cut raw start i) acc))]
       (cond
         ((= e 110) (textLoop raw bs n (+ i 2) (+ i 2) (cons "\n" pre)))
         ((= e 114) (textLoop raw bs n (+ i 2) (+ i 2) (cons "\r" pre)))
         ((= e 116) (textLoop raw bs n (+ i 2) (+ i 2) (cons "\t" pre)))
         ((or (= e 92) (= e 34)) (textLoop raw bs n (+ i 2) (+ i 2) (cons (asciiChar e) pre)))
         ((= e 120)
          (let [(v (+ (* 16 (hexVal (byteAt bs n (+ i 2)))) (hexVal (byteAt bs n (+ i 3)))))]
            (cond
              ((and (>= v 0) (< v 32)) (textLoop raw bs n (+ i 4) (+ i 4) (cons (controlChar v) pre)))
              ((= v 127) (textLoop raw bs n (+ i 4) (+ i 4) (cons "\x7f" pre)))
              (else (err (str "\\x escape " (stringFromInt64 v) " is not text"))))))
         (else (err "bad escape"))))))

fn escLen bs: Bytes n: Int64 i: Int64 acc: Int64 -> Int64
  (cond
    ((>= i n) acc)
    ((!= (bytesGet bs i) 92) (escLen bs n (+ i 1) (+ acc 1)))
    ((= (byteAt bs n (+ i 1)) 120) (escLen bs n (+ i 4) (+ acc 1)))
    (else (escLen bs n (+ i 2) (+ acc 1))))

fn fillBytes! bs: Bytes n: Int64 i: Int64 out: Bytes k: Int64 -> Bytes
  (if (>= i n)
    out
    (let [(b (bytesGet bs i))]
      (if (!= b 92)
        (do (bytesSet out k b) (fillBytes! bs n (+ i 1) out (+ k 1)))
        (let [(e (byteAt bs n (+ i 1)))]
          (cond
            ((= e 120) (do (bytesSet out k (+ (* 16 (hexVal (byteAt bs n (+ i 2)))) (hexVal (byteAt bs n (+ i 3))))) (fillBytes! bs n (+ i 4) out (+ k 1))))
            ((= e 110) (do (bytesSet out k 10) (fillBytes! bs n (+ i 2) out (+ k 1))))
            ((= e 114) (do (bytesSet out k 13) (fillBytes! bs n (+ i 2) out (+ k 1))))
            ((= e 116) (do (bytesSet out k 9) (fillBytes! bs n (+ i 2) out (+ k 1))))
            (else (do (bytesSet out k e) (fillBytes! bs n (+ i 2) out (+ k 1)))))))))

fn decodeBytes! raw: String -> Bytes
  (let [(bs (stringToBytes raw)) (n (bytesLength bs))]
    (fillBytes! bs n 0 (bytesAlloc (escLen bs n 0 0)) 0))

fn rawOf v: (Option AVal) -> (Option String)
  (mt v ((some x) (strRaw x)) ((none) (none)))

fn textField v: AVal key: String -> String
  (mt (rawOf (field v key))
    ((none) "")
    ((some r) (resultOr (decodeText r) (str "<undecodable " key ">"))))

fn numField v: AVal key: String -> Int64
  (mt (field v key) ((some x) (numOf x)) ((none) -1))

fn listField v: AVal key: String -> (List AVal)
  (mt (field v key) ((some x) (itemsOf x)) ((none) (list)))

fn gitArgs args: (List String) -> (List String)
  (listAppend (list "-c" "init.defaultBranch=work" "-c" "commit.gpgsign=false" "-c" "core.autocrlf=false" "-c" "core.symlinks=true"
                    "-c" "user.name=parity" "-c" "user.email=parity@localhost")
              args)

fn runGit! root: String args: (List String) stdin: (Option String) date: (Option String) -> (Result String String)
  (let [(c0 (p/withEnv (p/withTimeout (p/withCwd (p/cmd "git" (listAppend (list "-C" root) (gitArgs args))) root) 600000)
                       "GIT_CEILING_DIRECTORIES" (gf/ceilingFor! root)))
        (c1 (mt stdin ((some s) (p/withStdin c0 s)) ((none) c0)))
        (c2 (mt date
              ((none) c1)
              ((some d) (p/withEnv (p/withEnv (p/withEnv (p/withEnv (p/withEnv (p/withEnv c1 "GIT_AUTHOR_NAME" "parity") "GIT_AUTHOR_EMAIL" "parity@localhost") "GIT_AUTHOR_DATE" d)
                                                        "GIT_COMMITTER_NAME" "parity") "GIT_COMMITTER_EMAIL" "parity@localhost") "GIT_COMMITTER_DATE" d))))]
    (mt (p/exec! c2)
      ((err _) (err (str "git " (stringJoin args " ") " could not run")))
      ((ok o) (if (= o.exitCode 0) (ok o.stdout) (err (str "git " (stringJoin args " ") ": " o.stderr))))))

fn parentDir path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn writeOne! root: String f: AVal -> (Result Bool String)
  (let [(xs (itemsOf f))]
    (mt (rawOf (listGet xs 1))
      ((none) (err "file entry without a path"))
      ((some rawPath)
       (mt (decodeText rawPath)
         ((err e) (err e))
         ((ok rel)
          (let [(full (str root "/" rel))]
            (mt (rawOf (listGet xs 2))
              ((none) (resultMap (pathRemove full) (fn [(u Unit)] -> Bool true)))
              ((some rawData)
               (mt (dirCreate (parentDir full))
                 ((err e) (err e))
                 ((ok _) (mt (fileWrite full (decodeBytes! rawData)) ((ok _) (ok true)) ((err e) (err (str "write " full ": " e))))))))))))))

fn writeAllFiles! root: String fs: (List AVal) -> (Result Bool String)
  (mt (listHead fs)
    ((none) (ok true))
    ((some f) (mt (writeOne! root f) ((err e) (err e)) ((ok _) (writeAllFiles! root (optionOr (listTail fs) (list)))))))

fn linkTarget l: AVal -> String
  (mt (rawOf (listGet (itemsOf l) 2)) ((some r) (resultOr (decodeText r) "")) ((none) ""))

fn linkPath l: AVal -> String
  (mt (rawOf (listGet (itemsOf l) 1)) ((some r) (resultOr (decodeText r) "")) ((none) ""))

fn addLinks! root: String ls: (List AVal) -> (Result Bool String)
  (mt (listHead ls)
    ((none) (ok true))
    ((some l)
     (mt (runGit! root (list "hash-object" "-w" "--stdin") (some (linkTarget l)) (none))
       ((err e) (err e))
       ((ok blob)
        (mt (runGit! root (list "update-index" "--add" "--cacheinfo" (str "120000," (stringTrim blob) "," (linkPath l))) (none) (none))
          ((err e) (err e))
          ((ok _) (addLinks! root (optionOr (listTail ls) (list)))))))))

fn checkoutLinks! root: String ls: (List AVal) -> (Result Bool String)
  (mt (listHead ls)
    ((none) (ok true))
    ((some l)
     (mt (runGit! root (list "checkout" "--" (linkPath l)) (none) (none))
       ((err e) (err e))
       ((ok _) (checkoutLinks! root (optionOr (listTail ls) (list)))))))

fn pad2 k: Int64 -> String
  (if (< k 10) (str "0" (stringFromInt64 k)) (stringFromInt64 k))

fn commitAll! root: String cs: (List AVal) k: Int64 -> (Result Bool String)
  (mt (listHead cs)
    ((none) (ok true))
    ((some c)
     (let [(links (listField c "links"))
           (date (str "2026-01-" (pad2 (+ k 1)) "T00:00:00+0000"))
           (steps (mt (writeAllFiles! root (listField c "files"))
                    ((err e) (err e))
                    ((ok _)
                     (mt (runGit! root (list "add" "-A") (none) (none))
                       ((err e) (err e))
                       ((ok _)
                        (mt (addLinks! root links)
                          ((err e) (err e))
                          ((ok _)
                           (mt (runGit! root (list "commit" "-q" "--no-verify" "--allow-empty" "-m" (str "c" (stringFromInt64 k))) (none) (some date))
                             ((err e) (err e))
                             ((ok _) (checkoutLinks! root links))))))))))]
       (mt steps ((err e) (err e)) ((ok _) (commitAll! root (optionOr (listTail cs) (list)) (+ k 1)))))))

fn chmodFixture! root: String paths: (List AVal) -> (Result Bool String)
  (mt (listHead paths)
    ((none) (ok true))
    ((some f)
     (mt (rawOf (some f))
       ((none) (err "executable entry without a path"))
       ((some raw)
        (let [(path (resultOr (decodeText raw) ""))
              (cmd (p/withTimeout (p/withCwd (p/cmd "chmod" (list "+x" (str root "/" path))) root) 600000))]
          (mt (p/exec! cmd)
            ((err _) (err (str "chmod " path " could not run")))
            ((ok o) (if (= o.exitCode 0) (chmodFixture! root (optionOr (listTail paths) (list))) (err (str "chmod " path " failed"))))))))))

fn configureFixture! root: String c: AVal -> (Result Bool String)
  (let [(remote (mt (field c "remote") ((some x) (= (symName x) "true")) ((none) false)))
        (addRemote (if remote (resultMap (runGit! root (list "remote" "add" "origin" "https://example.invalid/repo.git") (none) (none)) (fn [(s String)] -> Bool true)) (ok true)))]
    (mt addRemote ((err e) (err e)) ((ok _) (chmodFixture! root (listField c "executable")))) )

fn buildTree! root: String c: AVal -> (Result Bool String)
  (mt (dirCreate root)
    ((err e) (err e))
    ((ok _)
     (let [(isGit (mt (field c "git") ((some x) (= (symName x) "true")) ((none) false)))
           (commits (listField c "commits"))
           (mainAt (numField c "main"))
           (made (if isGit
                   (mt (runGit! root (list "init" "-q") (none) (none))
                     ((err e) (err e))
                     ((ok _)
                      (mt (commitAll! root commits 0)
                        ((err e) (err e))
                        ((ok _)
                         (if (>= mainAt 0)
                           (resultMap (runGit! root (list "branch" "-f" "main" (str "HEAD~" (stringFromInt64 (- (- (listLength commits) 1) mainAt)))) (none) (none)) (fn [(s String)] -> Bool true))
                           (ok true))))))
                   (ok true)))]
       (mt made ((err e) (err e))
         ((ok _)
          (mt (writeAllFiles! root (listField c "edits"))
            ((err e) (err e))
            ((ok _) (configureFixture! root c))))))))

fn normRoot s: String root: String real: String -> String
  (stringReplace (if (stringEmpty? real) s (stringReplace s real "$ROOT")) root "$ROOT")

fn envOf c: AVal -> String
  (mt (rawOf (field c "env")) ((some r) (resultOr (decodeText r) "")) ((none) ""))

fn argsOf c: AVal -> (List String)
  (map (fn [(a AVal)] -> String (mt (rawOf (some a)) ((some r) (resultOr (decodeText r) "")) ((none) ""))) (listField c "args"))

fn normDate text: String -> String
  (let [(prefix "(:foreignBaseline :v 1 :owner \"GF2\" :date \"")
        (k (stringLength prefix))
        (date (cut text k (+ k 10)))
        (bs (stringToBytes date))
        (shape (and (= (stringLength date) 10) (= (cut date 4 5) "-") (= (cut date 7 8) "-")
                    (listAll? (fn [(i Int64)] -> Bool (and (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 57))) (list 0 1 2 3 5 6 8 9))))]
    (if (and (stringStartsWith? text prefix) shape (= (cut text (+ k 10) (+ k 11)) "\""))
      (str prefix "<date>" (cut text (+ k 10) (stringLength text)))
      text))

fn digitsEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 57)) (digitsEnd bs n (+ i 1)) i)

fn normWall text: String -> String
  (let [(key ":wallMs ")]
    (mt (stringIndexOf text key)
      ((none) text)
      ((some at)
       (let [(start (+ at (stringLength key)))
             (bs (stringToBytes text))
             (end (digitsEnd bs (bytesLength bs) start))]
         (if (= end start)
           text
           (str (cut text 0 start) "<ms>" (normWall (cut text end (stringLength text)))))))))

fn mismatch id: String what: String want: String got: String -> String
  (str id " " what ": want " (cut want 0 (min 1600 (stringLength want))) " got " (cut got 0 (min 1600 (stringLength got))))

fn compareRun! c: AVal root: String -> (List String)
  (let [(id (textField c "id"))
        (args (argsOf c))
        (lockWanted (= (symName (optionOr (field c "lock") (aSym "false"))) "true"))
        (lockHeld (if lockWanted (fileLock (str root "/.git/aslRunner.lock") true) (ok 0)))
        (r (am/runAudit! root args "" (stringContains? (envOf c) "ASL_IN_RUNNER=1")))
        (released (if lockWanted (mt lockHeld ((ok fd) (fdClose fd)) ((err _) (ok ()))) (ok ())))
        (real (resultOr (realPath root) ""))
        (stdout (str (normWall (normRoot r.receipt root real)) "\n"))
        (stderr (str (normWall (normRoot r.summary root real)) "\n"))
        (wantOut (textField c "stdout"))
        (wantErr (textField c "stderr"))
        (wantExit (numField c "exit"))]
    (listAppend (if (and lockWanted (not (ok? lockHeld))) (list (str id " failed to hold the runner lock")) (list))
      (listAppend (if (= stdout wantOut) (list) (list (mismatch id "stdout" wantOut stdout)))
        (listAppend (if (= stderr wantErr) (list) (list (mismatch id "stderr" wantErr stderr)))
                    (if (= r.exitCode wantExit) (list) (list (mismatch id "exit" (stringFromInt64 wantExit) (stringFromInt64 r.exitCode))))))))

fn tallyAdd t: Tally cases: Int64 pinned: (List String) fails: (List String) -> Tally
  (Tally :cases (+ t.cases cases) :pinned (listAppend t.pinned pinned) :fails (listAppend t.fails fails))

fn synthetic! tmp: String t: Tally c: AVal -> Tally
  (let [(root (str tmp "/" (textField c "id")))]
    (mt (buildTree! root c)
      ((err e) (tallyAdd t 1 (list) (list (str (textField c "id") " tree: " e))))
      ((ok _) (tallyAdd t 1 (list) (compareRun! c root)))))

fn pinned! tmp: String repo: String forms: (List AVal) t: Tally sha: String -> Tally
  (let [(root (str tmp "/pinned-" (cut sha 0 12)))
        (cases (filter (fn [(f AVal)] -> Bool (and (= (headOf f) "case") (= (textField f "sha") sha))) forms))
        (made (mt (runGit! repo (list "clone" "-q" "--shared" "--no-checkout" repo root) (none) (none))
                ((err e) (err e))
                ((ok _)
                 (mt (runGit! root (list "checkout" "-q" "--detach" sha) (none) (none))
                   ((err e) (err e))
                   ((ok _)
                    (mt (runGit! root (list "branch" "-f" "main" sha) (none) (none))
                      ((err e) (err e))
                      ((ok _) (runGit! root (list "remote" "remove" "origin") (none) (none)))))))))]
    (mt made
      ((err e) (tallyAdd t (listLength cases) (list sha) (list (str sha " clone: " e))))
      ((ok _)
       (let [(fails (fold (fn [(acc (List String)) (c AVal)] -> (List String) (listAppend acc (compareRun! c root))) (list) cases))]
         (tallyAdd t (listLength cases) (list sha) fails)))))

fn uniq xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn replay! forms: (List AVal) repo: String tmp: String -> Tally
  (let [(synth (filter (fn [(f AVal)] -> Bool (and (= (headOf f) "case") (= (mt (field f "tree") ((some x) (kwName x)) ((none) "")) "synthetic"))) forms))
        (shas (uniq (map (fn [(f AVal)] -> String (textField f "sha"))
                         (filter (fn [(f AVal)] -> Bool (and (= (headOf f) "case") (= (mt (field f "tree") ((some x) (kwName x)) ((none) "")) "pinned"))) forms))))
        (t0 (Tally :cases 0 :pinned (list) :fails (list)))
        (t1 (fold (fn [(t Tally) (c AVal)] -> Tally (synthetic! tmp t c)) t0 synth))]
    (fold (fn [(t Tally) (sha String)] -> Tally (pinned! tmp repo forms t sha)) t1 shas))

fn loadFixture! -> (Result (List AVal) String)
  (mt (fileReadString (fixturePath))
    ((err e) (err e))
    ((ok text)
     (let [(bs (stringToBytes text))]
       (readAll text bs (bytesLength bs) 0 (list)))))

fn testRecordRefusal! tmp: String -> Bool
  (let [(root (str tmp "/recordRefusal"))
        (setup (mt (gf/initContained! root)
                 ((err e) (err e))
                 ((ok _)
                  (mt (fileWrite (str root "/README.md") (stringToBytes "clean\\n"))
                    ((err e) (err e))
                    ((ok _)
                     (mt (runGit! root (list "add" "README.md") (none) (none))
                       ((err e) (err e))
                       ((ok _)
                        (mt (runGit! root (list "commit" "-q" "-m" "base") (none) (none))
                          ((err e) (err e))
                          ((ok _)
                           (mt (fileWrite (str root "/README.md") (stringToBytes "dirty\\n"))
                             ((err e) (err e))
                             ((ok _) (ok true))))))))))))
        (c (mt setup
             ((err e) (ag/failCheck "fullGreenRecord" "ERR_FIXTURE_SETUP" e (none) (none)))
             ((ok _) (ag/recordCheck! root ":full"))))
        (cleaned (pathRemove root))]
    (do
      (assert (ok? setup) "record refusal fixture is a committed tree with a dirty worktree")
      (assert (and (= c.status ":failed") (= c.err "ERR_RECORD_REFUSED"))
              "dirty fullGreen record request is refused")
      (assert (ok? cleaned) "record refusal temp tree removed")
      true))

fn recordResult r: AVal -> sr/SuiteResult
  (sr/makeSuiteResult (textField r "suite") (textField r "cause") "" "" (numField r "asserts") (numField r "refutes") 0 0)

fn recordFails! tmp: String c: AVal -> (List String)
  (let [(id (textField c "id"))
        (root (str tmp "/record-" id))]
    (mt (buildTree! root c)
      ((err e) (list (str id " tree: " e)))
      ((ok _)
       (mt (ag/writeRecord! root (map recordResult (listField c "results")))
         ((err e) (list (str id " write: " e)))
         ((ok rel)
          (let [(content (resultOr (fileReadString (str root "/" rel)) ""))]
            (listAppend (if (= rel (textField c "path")) (list) (list (mismatch id "path" (textField c "path") rel)))
                        (if (= content (textField c "content")) (list) (list (mismatch id "content" (textField c "content") content))))))))))

fn testPlaceholderDigest -> Bool
  (do
    (assert (ag/lineHasPlaceholder? "(:r :digest \"0123456789abcdef\" :prev (:digest \"0000000000000000\"))")
            "a zero :digest after a real one on the same line is a placeholder")
    (assert (ag/lineHasPlaceholder? "(:r :digest \"0000000000000000\")") "16 zeros is a placeholder")
    (assert (ag/lineHasPlaceholder? "(:r :digest \"00000000000000000\")") "17 zeros is a placeholder")
    (refute (ag/lineHasPlaceholder? "(:r :digest \"000000000000000\")") "15 zeros is not a placeholder")
    (refute (ag/lineHasPlaceholder? "(:r :digest \"0000000000000000a\" :b (:digest \"00000000000000001\"))")
            "zeros followed by another hex digit are not a placeholder")
    true)

fn testRoot! tmp: String -> Bool
  (let [(root (str tmp "/rootOption"))
        (made (dirCreate root))
        (init (runGit! root (list "init" "-q") (none) (none)))
        (tasks (dirCreate (str root "/.asl/mem/tasks")))
        (task (fileWrite (str root "/.asl/mem/tasks/t.asn") (stringToBytes "(:task :id \"t\" :digest \"placeholder\")\n")))
        (added (runGit! root (list "add" ".asl/mem/tasks/t.asn") (none) (none)))
        (committed (runGit! root (list "commit" "-q" "-m" "base") (none) (none)))
        (result (am/main (list "steps" "--root" root)))
        (run (am/runAudit! root (list "steps") "" false))
        (repo (stringTrim (resultOr (runGit! "." (list "rev-parse" "--show-toplevel") (none) (none)) "")))
        (envRun (p/exec! (p/withCwd (p/cmd "env" (list (str "ROOT_DIR=" root) (str repo "/asl/host/out/asl-host") "run" (str repo "/asl/packages/asl-gates/src/auditMain.asl") "steps")) repo)))
        (envOutput (mt envRun ((err _) "") ((ok o) o.stdout)))
        (cliRoot (p/exec! (p/withCwd (p/cmd (str repo "/asl/host/out/asl-host") (list "run" (str repo "/asl/packages/asl-gates/src/auditMain.asl") "gates" "--static" "--root" root)) repo)))
        (cliOutput (mt cliRoot ((err _) "") ((ok o) o.stdout)))
        (cleaned (pathRemove root))]
    (do
      (assert (and (ok? made) (and (ok? init) (and (ok? tasks) (and (ok? task) (and (ok? added) (ok? committed)))))) "explicit root is a committed fixture tree")
      (assert (and (ok? result) (= (resultOr result -1) run.exitCode)) "--root selects the fixture toolchain root")
      (assert (stringContains? run.receipt "ERR_PLACEHOLDER_DIGEST") "fixture root's placeholder is the observed receipt")
      (assert (stringContains? envOutput "ERR_PLACEHOLDER_DIGEST") "ROOT_DIR selects fixture root without --root")
      (assert (and (stringContains? cliOutput ":scope :static") (not (stringContains? cliOutput "ERR_USAGE"))) "--root is stripped before gates rejects extra arguments")
      (assert (ok? cleaned) "root fixture removed")
      true))

fn testFullAsync! tmp: String -> Bool
  (let [(root (str tmp "/full Async \"quoted\" apostrophe'quoted"))
        (bin (dirCreate (str root "/bin")))
        (stub (fileWrite (str root "/bin/asl") (stringToBytes "#!/bin/sh\necho \"$1\" > spawn.receipt\necho '(:manage :status :ok)'\n")))
        (chmod (p/exec! (p/withCwd (p/cmd "chmod" (list "+x" "bin/asl")) root)))
        (job (ag/spawnFullJob! root (list "--full" "--record" "--sync" "--jobs=3")))
        (form (resultOr (fileReadString (str root "/spawn.receipt")) ""))
        (badStub (fileWrite (str root "/bin/asl") (stringToBytes "#!/bin/sh\nprintf 'head%0400d' 0\necho ' missing \"status\"'\nexit 7\n")))
        (badJob (ag/spawnFullJob! root (list "--full")))
        (badEv (mt badJob ((ok _) "") ((err e) e)))
        (silentStub (fileWrite (str root "/bin/asl") (stringToBytes "#!/bin/sh\necho '(:manage :status :failed)'\n")))
        (silentJob (ag/spawnFullJob! root (list "--full")))
        (cleaned (pathRemove root))]
    (do
      (assert (and (ok? bin) (and (ok? stub) (and (ok? chmod) (ok? job)))) "stub manager launches successfully")
      (assert (stringStartsWith? (resultOr job "") "auditGates") "full async launch has a job id")
      (assert (stringContains? form "audit gates --sync --full --record --jobs=3") "async job forwards caller flags except its caller --sync")
      (assert (stringContains? form "apostrophe'\\''quoted' && bin/asl audit gates --sync") "root apostrophes are shell-quoted in the manage frame")
      (assert (and (ok? badStub) (ok? silentStub)) "failing manager stubs installed")
      (assert (err? badJob) "nonzero manager exit is rejected")
      (assert (stringContains? badEv "0 missing \"status\"") "spawn evidence is raw manager output, escaped once by fmtCheck")
      (assert (and (= (stringLength badEv) 300) (not (stringContains? badEv "head"))) "spawn evidence keeps the last 300 characters like audit.py out[-300:]")
      (assert (err? silentJob) "exit 0 without :status :ok is rejected")
      (assert (ok? cleaned) "async stub root removed")
      true))

fn testTerminatedMapping -> Bool
  (let [(c (ag/snapshotFault "gate5Suites" (sr/Fault :kind "terminated" :msg "signal 15")))]
    (do
      (assert (= c.id "internal") "terminated snapshot is identified as internal")
      (assert (= c.err "ERR_AUDIT_INTERNAL") "terminated snapshot maps to ERR_AUDIT_INTERNAL")
      true))

fn ! runTests -> Bool
  (let [(forms (resultOr (loadFixture!) (list)))
        (header (optionOr (listHead forms) (aList (list))))
        (repo (stringTrim (resultOr (runGit! "." (list "rev-parse" "--show-toplevel") (none) (none)) "")))
        (tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/aslAuditParity." (stringFromInt64 (nowNs))))
        (made (dirCreate tmp))
        (t (replay! forms repo tmp))
        (refused (testRecordRefusal! tmp))
        (rootOk (testRoot! tmp))
        (asyncOk (testFullAsync! tmp))
        (terminatedOk (testTerminatedMapping))
        (records (filter (fn [(f AVal)] -> Bool (= (headOf f) "record")) forms))
        (recordMismatches (fold (fn [(acc (List String)) (c AVal)] -> (List String) (listAppend acc (recordFails! tmp c))) (list) records))
        (cleaned (pathRemove tmp))]
    (do
      (assert (= (headOf header) "auditParity") "fixture header is (:auditParity ...)")
      (assert (ok? made) "temp root created")
      (assert (= t.cases (numField header "cases")) (str "replayed cases " (stringFromInt64 t.cases) " = header :cases"))
      (assert (= t.cases 55) "exactly 55 fixture cases")
      (assert (= t.pinned (list "399dadd4d3782e4e24d10327a901215b38696613" "c92dce1dacec30d3048a60527ad7df2562829045" "5e05a063ace2300cedeca2215c9fe454fbe2b611")) "three exact pinned main commits")
      (assert refused "record refusal parity")
      (assert rootOk "explicit toolchain root")
      (assert asyncOk "full async spawn stub")
      (assert terminatedOk "terminated runner faults map to internal audit errors")
      (assert (testPlaceholderDigest) "placeholder :digest detection")
      (assert (= (listLength records) (numField header "records")) "every fixture record replayed")
      (assert (> (listLength records) 0) "at least one fullGreen record case")
      (assert (listEmpty? recordMismatches) (str "record mismatches:\n" (stringJoin recordMismatches "\n")))
      (assert (listEmpty? t.fails) (str (stringFromInt64 (listLength t.fails)) " mismatches:\n" (stringJoin t.fails "\n")))
      (assert (ok? cleaned) "temp root removed")
      (assert (not (fileExists? tmp)) (str tmp " is gone after the run"))
      true))
