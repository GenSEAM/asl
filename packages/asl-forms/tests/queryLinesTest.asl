(module asl-forms/tests/queryLinesTest
  :x [runTests]
  :i [(asl-forms/search :a s)])

fn fixtureBody -> String
  (str "(module fx/a :x [outer])\n\nfn outer x: Int64 -> Int64\n"
       "  (let [(r (g " (stringRepeat "a" 70) " allResultsTotal2 pad " (stringRepeat "b" 70) "))]\n"
       "    (+ x 1)))\n")

fn bigBody -> String
  (str "fn big -> Int64\n  a" (stringRepeat "é" 2000) "needle" (stringRepeat "é" 2000) "\n")
fn textOf out: String -> String
  (let [(i (optionOr (stringIndexOf out ":text \"") 0))] (optionOr (stringSlice out (+ i 7) (stringLength out)) ""))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/queryLinesTest-" (stringFromInt64 (procSelf))))
        (src (str dir "/src"))
        (mk (and (ok? (dirCreate dir)) (ok? (dirCreate src))))
        (w (and (ok? (fileWrite (str src "/a.asl") (fixtureBody))) (ok? (fileWrite (str src "/b.asl") (bigBody)))))
        (ctx (s/KnowCtx :ws (resultOr (realPath dir) dir) :toolRoot "" :binDir "" :vfsDir "" :toolsFile "" :home ""))
        (o (s/queryStep! ctx 1 (mapEmpty) (list "allRe")))
        (out (optionOr (listHead o.lines) ""))
        (o2 (s/queryStep! ctx 1 (mapSet (mapEmpty) "in" "all") (list "allresultstotal2")))
        (out2 (optionOr (listHead o2.lines) ""))
        (o3 (s/queryStep! ctx 1 (mapEmpty) (list "needle")))
        (out3 (optionOr (listHead o3.lines) ""))
        (gone (and (ok? (pathRemove (str src "/a.asl"))) (ok? (pathRemove (str src "/b.asl"))) (ok? (pathRemove src)) (ok? (pathRemove dir))))]
    (do
      (assert (and mk w) "fixture: a workspace under the test's own TMPDIR dir")
      (assert (stringContains? out "(:at \"src/a.asl:4\" :after \"outer\" :text \"") (str "a hit names path:line and the nearest definition above it: " out))
      (assert (stringContains? out " allResultsTotal2 pad ") (str "the excerpt holds the whole token around a partial query: " out))
      (assert (not (stringContains? out ":text \"a")) (str "the excerpt starts on a delimiter, not inside the run of a before the match: " out))
      (assert (not (stringContains? out "b\")")) (str "the excerpt ends on a delimiter, not inside the run of b after the match: " out))
      (assert (stringContains? out2 "(:at \"src/a.asl:4\" :after \"outer\"") "a case-insensitive query keeps the line number")
      (assert (stringContains? out3 "(:at \"src/b.asl:2\"") (str "the long-token hit names its line: " (optionOr (stringSlice out3 0 (min 300 (stringLength out3))) "")))
      (assert (< (stringLength out3) 900) (str "one hit on a 4 KB token stays bounded: " (stringFromInt64 (stringLength out3))))
      (assert (stringContains? (textOf out3) "needle") "the bounded excerpt still holds the match")
      (assert (and (stringStartsWith? (textOf out3) "...") (stringContains? out3 "...\")")) (str "both cut edges carry the ... marker: " out3))
      (assert gone "fixture removed")
      true))
