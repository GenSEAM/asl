(module asl-gates/tests/snapshotShareTest
  :x [runTests]
  :i [(asl-gates/suiteRunner :a sr)])

fn sh! command: String -> String
  (let [(res (processRun command))]
    (do
      (assert (= res.exitCode 0) (str "fixture command exits 0: " command " -> " res.stderr))
      (stringTrim res.stdout)))

fn readText! path: String -> String
  (mt (fileReadString path)
    ((ok text) text)
    ((err _) ""))

fn looseCount! repo: String -> Int64
  (optionOr (stringToInt64 (sh! (str "find " repo "/.git/objects -type f ! -path '*/info/alternates' | wc -l | tr -d ' '"))) -1)

fn dirtyPathCount! repo: String -> Int64
  (optionOr (stringToInt64 (sh! (str "cd " repo " && git status --short | wc -l | tr -d ' '"))) -1)

fn testSnapshotSharesCommittedObjects! -> Bool
  (let [(root (sh! "mktemp -d \"/tmp/aslSnapshotShare.XXXXXX\""))
        (setup (sh! (str "cd " root " && git init -q && git config user.name fixture && git config user.email fixture@example.invalid && i=1; while [ $i -le 200 ]; do printf 'committed-%s\\n' \"$i\" > object-$i.txt; i=$((i + 1)); done && git add -A && git commit -q -m fixture")))
        (before (looseCount! root))
        (dirtyWrite (fileWrite (str root "/object-1.txt") "dirty tracked content\\n"))
        (seededBlob (sh! (str "cd " root " && git hash-object -w object-1.txt")))
        (dirtyPaths (dirtyPathCount! root))
        (snapshot (optionOr (mt (sr/makeSnapshot! root) ((ok path) (some path)) ((err _) (none))) ""))]
    (do
      (assert (>= before 200) "fixture contains at least 200 loose committed objects")
      (assert (ok? dirtyWrite) "dirty one tracked fixture path")
      (assert (not (stringEmpty? snapshot)) "snapshot creation succeeds")
      (assert (not (stringEmpty? seededBlob)) "dirty tracked blob is present in root alternates")
      (assert (= dirtyPaths 1) "fixture has one dirty tracked path")
      (let [(rootObjectsBefore (looseCount! root))
            (snapObjects (looseCount! snapshot))
            (alternates (stringTrim (readText! (str snapshot "/.git/objects/info/alternates"))))
            (dirty (readText! (str snapshot "/object-1.txt")))
            (rootObjectsAfter (looseCount! root))
            (removed (pathRemove snapshot))
            (rootRemoved (pathRemove root))]
        (do
          (assert (<= snapObjects dirtyPaths) (str "snapshot loose count " (stringFromInt64 snapObjects) " <= dirty paths " (stringFromInt64 dirtyPaths)))
          (assert (= alternates (str root "/.git/objects")) "snapshot alternates points at root objects")
          (assert (= dirty "dirty tracked content\\n") "dirty tracked content is present in snapshot")
          (assert (= rootObjectsBefore rootObjectsAfter) "snapshot creation does not write root objects")
          (assert (ok? removed) "snapshot pathRemove cleanup succeeds")
          (assert (ok? rootRemoved) "fixture pathRemove cleanup succeeds")
          true))))

fn ! runTests -> Bool
  (do
    (assert (testSnapshotSharesCommittedObjects!) "snapshot sharing fixture")
    true)
