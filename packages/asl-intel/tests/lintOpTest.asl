(module asl-intel/tests/lintOpTest
  :x [runTests]
  :i [(asl-intel :a intel)])

fn quadSrc -> String
  "(module q/quad :x [walkByIndex])\n\nfn walkByIndex xs: (List Int64) i: Int64 -> Int64\n  (if (>= i (listLength xs)) 0\n    (+ (optionOr (listGet xs i) 0) (walkByIndex xs (+ i 1))))\n"

fn cleanSrc -> String
  "(module q/clean :x [sumList])\n\nfn sumList xs: (List Int64) -> Int64\n  (mt (listHead xs)\n    ((none) 0)\n    ((some h) (+ h (sumList (optionOr (listTail xs) (list))))))\n"

fn ! fixtureDir! tag: String -> String
  (let [(base (optionOr (envGet "TMPDIR") "/tmp"))
        (dir (str base "/asl-intel-lintop-" tag "-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (do (assert (ok? made) (str "dirCreate failed for lintOpTest fixture " dir))
        dir))

fn ! testFlagsQuadraticFixtureThroughDispatch -> Bool
  (let [(dir (fixtureDir! "quad"))
        (path (str dir "/quad.asl"))
        (written (fileWrite path (quadSrc)))
        (o (intel/runIntel! (intel/makeCtx!) (list "lint" path)))
        (cleaned (pathRemove dir))]
    (do (assert (ok? written) "write quadratic fixture")
        (assert (= o.code 0) (str "intel lint exits 0 through runIntel! (CHECKPARITYLINT-OP: was exit 1, 'Unknown intel subcommand: lint', before the op was wired): " o.err))
        (assert (stringContains? o.out "LINT_QUADRATIC_LISTGET") (str "receipt names the code: " o.out))
        (assert (stringContains? o.out ":count 1") (str "exactly one row on the one-fn fixture: " o.out))
        (assert (stringContains? o.out "walkByIndex") (str "receipt names the offending fn: " o.out))
        (assert (ok? cleaned) "remove quadratic fixture dir")
        true))

fn ! testCleanFixtureHasNoRows -> Bool
  (let [(dir (fixtureDir! "clean"))
        (path (str dir "/clean.asl"))
        (written (fileWrite path (cleanSrc)))
        (o (intel/runIntel! (intel/makeCtx!) (list "lint" path)))
        (cleaned (pathRemove dir))]
    (do (assert (ok? written) "write clean fixture")
        (assert (= o.code 0) (str "intel lint exits 0 with no sites: " o.err))
        (assert (stringContains? o.out ":count 0") (str "no rows on a listHead/listTail walk: " o.out))
        (assert (ok? cleaned) "remove clean fixture dir")
        true))

fn ! runTests -> Bool
  (do (assert (testFlagsQuadraticFixtureThroughDispatch) "intel lint, dispatched through runIntel! (the same path 'asl (:intel ...)' uses), flags the synthetic quadratic fixture")
      (assert (testCleanFixtureHasNoRows) "intel lint on a listHead/listTail walk reports zero rows")
      true)
