(module asl/tools/tests/roWrapperTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr) (asl-ir/link :a lk)])

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "nativeTest#placeWrapper!: with its entries directory writable the wrapper is the given in-tree path and the overrides are unchanged; with that directory read-only the wrapper goes under CDIR/roEntries/KEY, imports the placeholder nativeTestRo/target, and the closure loaded with the returned overrides holds the real entry module and the modules it imports from the tree")
fn entry -> String
  "asl/tools/observe/observe.asl"

fn text -> String
  "(module nativeTestEntry\n  :x [main]\n  :i [(asl/tools/observe/observe :a suite)])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (suite/main args)\n"

fn ! chmod! mode: String path: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "/bin/chmod" mode path) "." (fr/childEnv (list))) (fr/limits 30 4)))] (= d.exit 0))

fn ! paths units: (List lk/LinkUnit) -> (List String)
  (map (fn [(u lk/LinkUnit)] -> String (resultOr (realPath u.path) u.path)) units)

fn ! runTests -> Bool
  (let [(ws (resultOr (realPath ".") "."))
        (base (str ".asl/cache/roWrapperTest/" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs))))
        (open (str base "/open"))
        (shut (str base "/shut"))
        (made (and (ok? (dirCreate (str open "/entries"))) (ok? (dirCreate (str shut "/entries")))))
        (locked (and made (chmod! "a-w" (str shut "/entries"))))
        (wOpen (str open "/entries/k1.asl"))
        (wShut (str shut "/entries/k2.asl"))
        (pOpen (nt/placeWrapper! open (entry) "k1" wOpen (text) (mapEmpty)))
        (pShut (nt/placeWrapper! shut (entry) "k2" wShut (text) (mapEmpty)))
        (real (resultOr (realPath (str ws "/" (entry))) ""))
        (shutW (match pShut ((ok p) (pairFirst p)) ((err _) "")))
        (shutO (match pShut ((ok p) (pairSecond p)) ((err _) (mapEmpty))))
        (loaded (match pShut ((ok p) (lk/loadClosureOver! (pairFirst p) (pairSecond p))) ((err e) (err (list)))))
        (held (match loaded ((ok us) (paths us)) ((err _) (list))))
        (openText (resultOr (fileReadString wOpen) "unreadable"))
        (shutText (resultOr (fileReadString shutW) "unreadable"))
        (unlocked (chmod! "u+w" (str shut "/entries")))
        (removed (fr/runOneLimited (fr/job (list "/bin/rm" "-rf" base) "." (fr/childEnv (list))) (fr/limits 60 4)))]
    (do
      (assert (and made locked) "a writable and a read-only entries directory are set up")
      (assert (match pOpen ((ok p) (and (= (pairFirst p) wOpen) (= (mapSize (pairSecond p)) 0))) ((err _) false)) "writable: the wrapper is the in-tree path and no override is added")
      (assert (= openText (text)) (str "writable: the wrapper text is written as given: " openText))
      (assert (and (ok? pShut) (stringStartsWith? shutW (str shut "/roEntries/k2/"))) (str "read-only: the wrapper goes under the cache's roEntries: " shutW (match pShut ((err e) e) ((ok _) ""))))
      (assert (stringContains? shutText "(nativeTestRo/target :a suite)") (str "read-only: the wrapper imports the placeholder: " shutText))
      (assert (= (mapValues shutO) (list real)) (str "read-only: one override, to the entry's real path " real))
      (assert (ok? loaded) "read-only: the closure loads with the overrides")
      (assert (and (listContains? held real) (listAny? (fn [(p String)] -> Bool (stringEndsWith? p "/asl/tools/observe/common.asl")) held)) (str "read-only: the closure holds the entry and its tree imports: " (stringJoin held " ")))
      (assert (and unlocked (= removed.exit 0)) "the fixture is removed")
      true))
