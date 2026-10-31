(module aslTools/goldenRegenTest
  :x [runTests]
  :i [(asl-tools/goldenRegen :a gr)])

; (:m :ref QUAD-GOLDEN-AUTO :do "gate for the pure parts of goldenRegen and its git classification on a temp repo: multiset line difference, the path a golden line names, the number after a marker, the link-closure files of a linked text, and a three-commit repo where the pin comes from the commit that last touched the pinned text, only later commits count, and a line with no path is untraced")

fn gitIn! dir: String args: (List String) -> Bool
  (let [(d (gr/git! dir (listAppend (list "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false") args)))]
    (= d.exit 0))

fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! testPure -> Bool
  (do (assert (= (gr/onlyIn (list "a" "b" "b" "c") (list "b" "c" "d")) (list "a" "b")) "a line twice in A and once in B is reported once")
      (assert (listEmpty? (gr/onlyIn (list) (list "x"))) "nothing in A, nothing reported")
      (assert (= (gr/significant (list "" "  " ")" " ) " "keep" " x ")) (list "keep" " x ")) "blank lines and a lone closing paren are dropped")
      (assert (= (gr/pathOfLine "{:name \"x\" :path \"asl/packages/p/src/a.asl\" :n 1}") "asl/packages/p/src/a.asl") "a summary :path")
      (assert (= (gr/pathOfLine "asl/tools/x.asl:12:3 rule-2 msg") "asl/tools/x.asl") "a diagnostic locus")
      (assert (= (gr/pathOfLine "(module asl/packages/q/b.asl") "asl/packages/q/b.asl") "a module line")
      (assert (= (gr/pathOfLine "asl-cli/verify without a path") "") "a module name is not a path")
      (assert (= (gr/pathOfLine "asl/packages/foo") "") "no .asl suffix, no path")
      (assert (= (gr/numberAfter "x (= (listLength units) 61) y" "(= (listLength units) ") 61) "the number after the marker")
      (assert (= (gr/numberAfter "x" "(= (listLength units) ") -1) "a missing marker is -1")
      (assert (= (gr/numberAfter "(= (listLength units) )" "(= (listLength units) ") -1) "a marker with no digits is -1")
      (assert (= (gr/digitsPrefix "123abc") "123") "leading digits")
      (assert (= (gr/digitsPrefix "abc") "") "no leading digits")
      (assert (= (gr/closureFiles (stringJoin (list "asl/a/x.asl a/x ()" "asl/a/y.asl a/y ((pair \"k\" \"asl/a/x.asl\"))" "asl/a/x.asl a/x ()" "" "(ok)" "asl/z.asl") "\n"))
                 (list "asl/a/x.asl" "asl/a/y.asl"))
              "closure files are the distinct unit paths above the (ok) line")
      true)

fn ! testRepo -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/goldenRegenTest-" (stringFromInt64 (monotonicNs))))
        (src (str base "/asl/src/x.asl"))
        (golden (str base "/golden.txt"))
        (made (and (ok? (dirCreate base)) (and (ok? (dirCreate (str base "/asl"))) (ok? (dirCreate (str base "/asl/src"))))))
        (init (gitIn! base (list "init" "-q")))
        (w1 (and (put! src "v1\n") (put! golden "a\n")))
        (c1 (and (gitIn! base (list "add" "-A")) (gitIn! base (list "commit" "-q" "-m" "c1"))))
        (w2 (put! src "v2\n"))
        (c2 (and (gitIn! base (list "add" "-A")) (gitIn! base (list "commit" "-q" "-m" "c2"))))
        (w3 (put! golden "a\nb\n"))
        (c3 (and (gitIn! base (list "add" "-A")) (gitIn! base (list "commit" "-q" "-m" "c3"))))
        (head (stringTrim (gr/git! base (list "rev-parse" "HEAD")).out))
        (first (stringTrim (gr/git! base (list "rev-list" "--max-parents=0" "HEAD")).out))
        (second (stringTrim (gr/git! base (list "rev-parse" "HEAD~1")).out))
        (pinFile (gr/pinOf! base "golden.txt"))
        (pinText (gr/pinOfText! base "golden.txt" "a"))
        (pinNew (gr/pinOfText! base "golden.txt" "b"))
        (pinMiss (gr/pinOfText! base "golden.txt" "nowhere"))
        (after (gr/commitsIn! base pinText "asl/src/x.asl"))
        (late (gr/commitsIn! base pinFile "asl/src/x.asl"))
        (none (gr/commitsIn! base "" "asl/src/x.asl"))
        (cs (gr/changesOf! base pinText (list "asl/src/x.asl 1 old") (list "asl/src/x.asl 1 new" "a line with no path")))
        (ok1 (gr/changesOf! base pinText (list "asl/src/x.asl 1 old") (list "asl/src/x.asl 1 new")))
        (gone (pathRemove base))]
    (do (assert (and made (and init (and w1 (and c1 (and w2 (and c2 (and w3 c3))))))) "the temp repo has three commits")
        (assert (= pinFile head) "the pin of a file is the last commit touching it")
        (assert (= pinText first) "the pin of a text is the commit that last added or removed it, not the later unrelated edit of the file")
        (assert (= pinNew head) "a text added in the last commit pins to that commit")
        (assert (= pinMiss head) "a text that never occurs falls back to the last commit touching the file")
        (assert (= (listLength after) 1) (str "one commit touched the source after the first: " (stringJoin after " ")))
        (assert (stringStartsWith? second (optionOr (listHead after) "?")) "that commit is the second, not the third")
        (assert (listEmpty? late) "no source commit after the last pin")
        (assert (listEmpty? none) "an empty pin finds no commits")
        (assert (= (listLength cs) 2) (str "two paths changed, the empty path and the source: " (listLength cs)))
        (assert (= (map (fn [(c gr/PathChange)] -> String c.path) cs) (list "" "asl/src/x.asl")) "paths come out sorted, the empty path first")
        (assert (gr/untraced? cs) "a line with no path has no commit and is untraced")
        (assert (not (gr/untraced? ok1)) "a path with a commit in range is traced")
        (assert (= (map (fn [(c gr/PathChange)] -> Int64 (+ c.removed c.added)) ok1) (list 2)) "removed and added lines are counted per path")
        (assert (ok? gone) "the temp repo is removed")
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "testPure")
      (assert (testRepo) "testRepo")
      true)
