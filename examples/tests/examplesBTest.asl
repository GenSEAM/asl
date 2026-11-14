(module aslExamples/tests/examplesBTest
  :x [runTests]
  :i [(aslExamples/moduleExample :a mx)
      (aslExamples/moduleUser :a mu)
      (aslExamples/fileExample :a fe)
      (aslExamples/stringExample :a sx)
      (aslExamples/mapExample :a mp)])

fn runTests -> Bool
  (let [(path (str "/tmp/aslExamplesB-" (stringFromInt64 (procSelf)) ".txt"))
        (cs (mp/counts (list "a" "b" "a")))]
    (do
      (assert (= (mx/double 3) 6) "double")
      (assert (= (mx/cube 3) 27) "cube")
      (assert (= (mu/quad 2) 8) "quad")
      (assert (= (mu/squarePlusOne 4) 17) "squarePlusOne")
      (assert (= (mu/doublePlusSquare 2) 8) "doublePlusSquare")
      (assert (= (fe/roundTrip path "a\nb") (ok "a\nb")) "roundTrip")
      (assert (= (fe/lineCount path) (ok 2)) "lineCount")
      (assert (= (fe/readOr path "x") "a\nb") "readOr present")
      (assert (ok? (pathRemove path)) "cleanup")
      (assert (= (fe/readOr path "x") "x") "readOr missing")
      (assert (err? (fe/lineCount path)) "lineCount missing")
      (assert (= (sx/words "a b c") (list "a" "b" "c")) "words")
      (assert (= (sx/csv (list "a" "b")) "a,b") "csv")
      (assert (sx/hasTarget "agent slang" "slang") "hasTarget")
      (assert (= (sx/prefix "abcdef" 3) "abc") "prefix")
      (assert (= (sx/prefix "ab" 5) "ab") "prefix short")
      (assert (= (sx/shout "hi") "HI!") "shout")
      (assert (= (mp/getOr cs "a" 0) 2) "counts")
      (assert (= (mp/getOr cs "z" 7) 7) "getOr")
      (assert (= (mp/getOr (mp/bump cs "b") "b" 0) 2) "bump")
      (assert (= (mp/sortedKeys cs) (list "a" "b")) "sortedKeys")
      true))
