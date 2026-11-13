(module asl-tools/coord/tests/promoteDevRowsTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/fleet/run :a fr)])

; (:m :ref NODE2-DEV-DOC-ROWS :do "TMPDIR repos removed at the end: src and its dev clone carry doc.asn marked merge=asnRows and no merge.asnRows.driver; dev and main each append a distinct :doc row, promoteDev! must merge by row (both rows kept, no marker) and leave the dev config untouched; src links this tree's bin and asl so the injected driver resolves")
fn ! base -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/promoteDevRowsTest-" (stringFromInt64 (procSelf)))

fn ! run! dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list "GIT_CONFIG_NOSYSTEM=1"))) (fr/limits 120 0))

fn ! git! dir: String argv: (List String) -> fr/Done
  (run! dir (listAppend (list "git" "-C" dir "-c" "user.name=t" "-c" "user.email=t@t") argv))

fn row s: String -> String
  (str "(:doc :symbol \"" s "\" :text \"x\")\n")

fn ! commit! dir: String text: String msg: String -> Bool
  (and (ok? (fileWrite (str dir "/doc.asn") text))
    (and (= (git! dir (list "add" "doc.asn")).exit 0) (= (git! dir (list "commit" "--quiet" "-m" msg)).exit 0)))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (b (base))
        (src (str b "/src"))
        (dev (str b "/dev"))
        (_ (run! "." (list "rm" "-rf" b)))
        (_ (dirCreate b))
        (_ (dirCreate src))
        (i (git! src (list "init" "--quiet" "-b" "main")))
        (_ (fileWrite (str src "/.gitattributes") "doc.asn merge=asnRows\n"))
        (_ (git! src (list "add" ".gitattributes")))
        (c0 (commit! src (row "base") "c0"))
        (cl (run! b (list "git" "clone" "--quiet" src dev)))
        (_ (git! dev (list "checkout" "--quiet" "-b" "dev")))
        (ln (and (= (run! src (list "ln" "-s" (str root "/bin") (str src "/bin"))).exit 0) (= (run! src (list "ln" "-s" (str root "/asl") (str src "/asl"))).exit 0)))
        (devOwn (commit! dev (str (row "base") (row "padDev")) "dev row"))
        (mainOwn (commit! src (str (row "base") (row "stringClipTest")) "main row"))
        (noDriver (stringEmpty? (stringTrim (git! dev (list "config" "--get" "merge.asnRows.driver")).out)))
        (rc (cd/realCfg (list "--repo" src "--dev-repo" dev "--dev" "dev") b))
        (r (cd/promoteDev! rc))
        (text (resultOr (fileReadString (str dev "/doc.asn")) ""))
        (stillNone (stringEmpty? (stringTrim (git! dev (list "config" "--get" "merge.asnRows.driver")).out)))
        (_ (run! "." (list "rm" "-rf" b)))]
    (do (assert (and (= i.exit 0) c0 (= cl.exit 0) ln devOwn mainOwn) "scratch src, dev clone, one row each side")
        (assert noDriver "the dev clone has no merge.asnRows.driver, as node2's")
        (assert (= r "merged") (str "main comes into dev with no conflict: " r))
        (assert (and (stringContains? text "\"padDev\"") (and (stringContains? text "\"stringClipTest\"") (stringContains? text "\"base\""))) (str "both appended rows and the base row are kept: " text))
        (assert (not (or (stringContains? text "<<<<<<<") (stringContains? text ">>>>>>>"))) "no conflict marker")
        (assert stillNone "the merge leaves the dev config untouched")
        true))
