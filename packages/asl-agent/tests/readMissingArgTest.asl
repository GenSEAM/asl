(module aslAgent/tests/readMissingArgTest
  :x [runTests]
  :i [(aslAgent/aslOps :a o)
      (aslAgent/txn :a t)
      (aslAgent/core :a c)])

; (:m :ref K9-MISSING-ARG :do "node2 2026-11-18 LL-FS-TARGET turns 4-6: (:step :op \"read\") with no :file was refused three turns running with only 'Missing file argument'; the refusal now hands a ready read of the first owned file, a misspelt path within two edits of one existing file is read there with :repaired, and an owned file the task creates is an ok read marked :new with the write shape")
fn ! fakeRun form: String root: String -> t/AslRun
  (if (stringContains? form "src/real.asl")
    (t/aslRun 0 "(:receipt :op read :status :ok :content \"fn x -> Int64\\n  1\\n\")" "")
    (t/aslRun 1 "(:receipt :op read :status :rejected :error :ERR_FILE_NOT_FOUND)" ""))

fn ! readRec root: String op: String owns: (List String) -> String
  (o/serReceipt (o/execAslOpMemo! (c/parseKv op) owns root "s" (fn [] "rid") (fn [f] true) (fn [form r] (fakeRun form r)) 8000 none))

fn ! runTests -> Bool
  (let [root (str (optionOr (envGet "TMPDIR") "/tmp") "/readMissingArg" (stringFromInt64 (monotonicNs)))
        made (and (ok? (dirCreate (str root "/src"))) (and (ok? (fileWrite (str root "/src/real.asl") "fn x -> Int64\n  1\n")) (and (ok? (fileWrite (str root "/src/aa1.asl") "a\n")) (and (ok? (fileWrite (str root "/src/aa2.asl") "b\n")) (and (ok? (fileWrite (str root "/src/naw.asl") "n\n")) (and (ok? (dirCreate (str root "/lib"))) (and (ok? (fileWrite (str root "/lib/one.asl") "1\n")) (and (ok? (fileWrite (str root "/lib/ona.asl") "2\n")) (and (ok? (dirCreate (str root "/lib/sub1"))) (and (ok? (dirCreate (str root "-out"))) (and (ok? (fileWrite (str root "-out/reel.asl") "r\n")) (ok? (fileWrite (str root "-f") "f\n")))))))))))))
        owns (list "src/*.txt" "src/real.asl" "src/new.asl")
        noFile (readRec root "(:step :op \"read\")" owns)
        typo (readRec root "(:step :op \"read\" :file \"src/rael.asl\")" owns)
        far (readRec root "(:step :op \"read\" :file \"src/other.asl\")" owns)
        twin (readRec root "(:step :op \"read\" :file \"src/aa3.asl\")" owns)
        fresh (readRec root "(:step :op \"read\" :file \"src/new.asl\")" owns)
        exists (readRec root "(:step :op \"read\" :file \"lib/one.asl\")" owns)
        dirNear (readRec root "(:step :op \"read\" :file \"lib/sub2\")" owns)
        base (optionOr (listLast (stringSplit root "/")) "")
        outName (str "../" base "-out")
        outside (readRec root (str "(:step :op \"read\" :file \"" outName "/real.asl\")") owns)
        ownedOut (readRec root (str "(:step :op \"read\" :file \".a/" base "-f\")") (list (str "../" base "-f")))
        viaDir (readRec root "(:step :op \"read\" :file \"src/rael.asl\")" (list "src/"))
        viaGlob (readRec root "(:step :op \"read\" :file \"src/rael.asl\")" (list "src/*.asl"))
        viaAll (readRec root "(:step :op \"read\" :file \"src/rael.asl\")" (list "**"))
        globNew (readRec root "(:step :op \"read\" :file \"src/zzzzzz.asl\")" (list "src/*.asl"))
        cleaned (and (ok? (pathRemove root)) (and (ok? (pathRemove (str root "-out"))) (ok? (pathRemove (str root "-f")))))]
    (do
      (assert made "the fixture root is made")
      (assert (and (stringContains? noFile "ERR_MISSING_ARG") (stringContains? noFile "(:step :op \\\"read\\\" :file \\\"src/real.asl\\\")")) (str "a read without :file is refused with a ready read of the first owned file, globs skipped: " noFile))
      (assert (and (stringContains? typo "(status \"ok\")") (and (stringContains? typo "src/real.asl") (stringContains? typo "(repaired "))) (str "a path within two edits of one existing file is read there with :repaired: " typo))
      (assert (and (not (stringContains? far "(repaired ")) (stringContains? far "(status \"rejected\")")) (str "a path far from every file stays a rejected read: " far))
      (assert (and (stringContains? fresh "(status \"ok\")") (and (stringContains? fresh "(new true)") (stringContains? fresh ":content :raw"))) (str "an owned file the task creates is an ok read marked new with the write shape: " fresh))
      (assert (not (stringContains? twin "(repaired ")) (str "a path within two edits of two files is not repaired: " twin))
      (assert (not (stringContains? fresh "(repaired ")) (str "an owned file the task creates is never read at its neighbour src/naw.asl: " fresh))
      (assert (and (stringContains? exists "(file \"lib/one.asl\")") (and (not (stringContains? exists "(repaired ")) (not (stringContains? exists "lib/ona.asl")))) (str "an existing file with a close neighbour is read as sent: " exists))
      (assert (and (not (stringContains? dirNear "(repaired ")) (stringContains? dirNear "(file \"lib/sub2\")")) (str "a directory is no candidate: " dirNear))
      (assert (and (not (stringContains? outside "(repaired ")) (not (stringContains? outside "reel.asl"))) (str "a path that leaves the root is not repaired from a directory outside it: " outside))
      (assert (and (not (stringContains? ownedOut "(repaired ")) (not (stringContains? ownedOut (str "../" base "-f")))) (str "an owned entry that leaves the root is no candidate: " ownedOut))
      (assert (and (stringContains? viaDir "(repaired ") (stringContains? viaDir "(file \"src/real.asl\")")) (str "a typo under an owned directory is still read at its one neighbour: " viaDir))
      (assert (and (stringContains? viaGlob "(repaired ") (stringContains? viaGlob "(file \"src/real.asl\")")) (str "a typo covered by an owned glob is still read at its one neighbour: " viaGlob))
      (assert (and (stringContains? viaAll "(repaired ") (stringContains? viaAll "(file \"src/real.asl\")")) (str "a typo under owns ** is still read at its one neighbour: " viaAll))
      (assert (and (stringContains? globNew "(new true)") (not (stringContains? globNew "(repaired "))) (str "a glob-covered path with no neighbour is a new file: " globNew))
      (assert cleaned "the fixture roots are removed")
      true))
