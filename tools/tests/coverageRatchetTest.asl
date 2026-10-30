(module aslTools/coverageRatchetTest
  :x [runTests]
  :i [(asl-tools/coverageRatchet :a cr)])

fn srcText -> String
  "(module p/m\n  :x [alpha beta\n      Gamma gone]\n  :i [])\n(module p/n :x [delta] :i [])\nfn alpha x: Int64 -> Int64 x\n"

fn testText -> String
  "(module p/mTest :x [runTests] :i [(p/m :a m)])\nfn ! runTests -> Bool\n  (and (= (m/alpha 1) 1) (= (m/beta 2) 2) (= (delta 3) 3))\n"

fn ignoredText -> String
  "(assert (gone 1) \"only inside node_modules\")\n"

fn counts rows: (List cr/Count) pkg: String -> (Option cr/Count)
  (listHead (filter (fn [(c cr/Count)] -> Bool (= c.pkg pkg)) rows))

fn coveredOf rows: (List cr/Count) pkg: String -> Int64
  (match (counts rows pkg) ((none) (- 0 1)) ((some c) c.covered))

fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! build! root: String -> Bool
  (and (ok? (dirCreate root))
       (ok? (dirCreate (str root "/asl")))
       (ok? (dirCreate (str root "/asl/packages")))
       (ok? (dirCreate (str root "/asl/packages/p")))
       (ok? (dirCreate (str root "/asl/packages/p/src")))
       (ok? (dirCreate (str root "/asl/packages/p/tests")))
       (ok? (dirCreate (str root "/asl/packages/q")))
       (ok? (dirCreate (str root "/asl/packages/q/src")))
       (ok? (dirCreate (str root "/tests")))
       (ok? (dirCreate (str root "/tests/node_modules")))
       (put! (str root "/asl/packages/p/src/m.asl") (srcText))
       (put! (str root "/asl/packages/p/tests/mTest.asl") (testText))
       (put! (str root "/asl/packages/q/src/z.asl") "(module q/z :x [] :i [])\n")
       (put! (str root "/tests/node_modules/x.asl") (ignoredText)))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/coverageRatchetTest-" (stringFromInt64 (monotonicNs))))
        (made (build! base))
        (baselinePath (str base "/baseline.asn"))
        (missing (cr/main (list "--root" base "--baseline" baselinePath)))
        (updated (cr/main (list "--root" base "--baseline" baselinePath "--update" "--date" "2026-10-30")))
        (rows (cr/packageCounts! base))
        (baselineText (optionOr (match (fileReadString baselinePath) ((ok t) (some t)) ((err _) (none))) ""))
        (steady (cr/main (list "--root" base "--baseline" baselinePath)))
        (vOk (cr/verdict! base baselinePath))
        (removed (pathRemove (str base "/asl/packages/p/tests/mTest.asl")))
        (dropped (cr/main (list "--root" base "--baseline" baselinePath)))
        (vBad (cr/verdict! base baselinePath))
        (vNone (cr/verdict! base (str base "/none.asn")))
        (vEmpty (cr/verdict! (str base "/tests") baselinePath))
        (rowsAfter (cr/packageCounts! base))
        (refused (cr/main (list "--root" base "--baseline" baselinePath "--update")))
        (baselineAfter (optionOr (match (fileReadString baselinePath) ((ok t) (some t)) ((err _) (none))) ""))
        (cleaned (pathRemove base))
        (parsed (cr/parseBaseline baselineText))
        (low (list (cr/Count :pkg "p" :exports 3 :covered 1)))
        (high (list (cr/Count :pkg "p" :exports 3 :covered 2)))]
    (do
      (assert made "the fixture tree is written")
      (assert (= (cr/exportedFns (srcText)) (list "alpha" "beta" "gone" "delta")) "exports span lines and modules, and a type name is not a function")
      (assert (= (cr/exportedFns "(module m :x [] :i [])") (list)) "an empty export list has no functions")
      (assert (= (cr/afterLastSeparator "m/beta") "beta") "an aliased call is counted by its function name")
      (assert (= (cr/afterLastSeparator "a.b.c") "c") "only the part after the last dot counts")
      (assert (= (cr/afterLastSeparator "plain") "plain") "a bare name stays whole")
      (assert (mapHas? (cr/tokenSet "(m/beta 2) note" (mapEmpty)) "beta") "a token inside a call is found")
      (assert (not (mapHas? (cr/tokenSet "(m/beta 2)" (mapEmpty)) "alp")) "a prefix of a name is not the name")
      (assert (= (coveredOf rows "p") 3) "alpha, beta and delta are called, gone appears only under node_modules")
      (assert (= (match (counts rows "p") ((some c) c.exports) ((none) 0)) 4) "the package has four lowercase exports")
      (assert (none? (counts rows "q")) "a package without exports has no row")
      (assert (err? missing) "no baseline file is an error that names --update")
      (assert (= updated (ok 0)) "update writes the first baseline")
      (assert (= (coveredOf parsed "p") 3) "the written baseline round-trips its covered count")
      (assert (= (cr/parseBaseline (cr/renderBaseline "d" high)) high) "render then parse returns the rows")
      (assert (= (cr/parseBaseline "(:pkg p :exports x :covered 2)") (list)) "a row with a non-number is dropped")
      (assert (= steady (ok 0)) "an unchanged tree passes")
      (assert (ok? removed) "the covering test is removed")
      (assert (= (coveredOf rowsAfter "p") 0) "without its test the package covers nothing")
      (assert (= dropped (ok 1)) "removing the only covering test turns the ratchet red")
      (assert (and (listEmpty? vOk.violations) (= vOk.packages 1) (= vOk.covered 3)) "the verdict of an unchanged tree is clean with its totals")
      (assert (and (= (listLength vBad.violations) 1) (= vBad.covered 0)) "the verdict names the package that lost its test")
      (assert (= (listLength vNone.violations) 1) "a missing baseline is one violation")
      (assert (and (listEmpty? vEmpty.violations) (= vEmpty.packages 0)) "a tree without packages has nothing to ratchet")
      (assert (= refused (err "baseline not raised: a package is below it")) "update refuses to lower the baseline")
      (assert (= baselineAfter baselineText) "a refused update leaves the baseline as it was")
      (assert (= (listLength (cr/violations parsed rowsAfter)) 1) "one package is below its baseline")
      (assert (stringContains? (optionOr (listHead (cr/violations parsed rowsAfter)) "") "p: covered 0") "the violation names the package and its count")
      (assert (listEmpty? (cr/violations low high)) "a higher count passes")
      (assert (listEmpty? (cr/violations high high)) "an equal count passes")
      (assert (= (listLength (cr/violations high low)) 1) "a lower count fails")
      (assert (= (listLength (cr/violations high (list))) 1) "a baseline row whose package vanished fails")
      (assert (= (cr/raised low high) high) "raising takes the higher count")
      (assert (= (cr/raised high low) high) "raising never lowers a count")
      (assert (= (listLength (cr/raised (list) high)) 1) "a new package gets a row")
      (assert (ok? cleaned) "the fixture tree is removed")
      true))
