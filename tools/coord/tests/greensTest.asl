(module asl-tools/coord/tests/greensTest
  :x [runTests]
  :i [(asl-tools/coord/greens :a gz) (asl-tools/coord/conductor :a cd) (asl-tools/fleet/run :a fr)])

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "a merged unit's green receipts outlive its trains dir: dropTrains! writes them to greens.asn first, a failed attempt file (silentSuites) writes nothing, a re-merge of a tree replaces its row, and the file keeps only the newest rows")
fn green m: String -> String
  (str "(:train :head \"h\" :merged \"" m "\" :red () :blocked (:fresh 0 :preexisting 0) :suites (\"s/a.asl\" \"s/b.asl\") :seconds 1)")

fn excl m: String -> String
  (str "(:train :head \"h\" :merged \"" m "\" :red () :preexisting ((\"s/p.asl\" \"br\" 1 0 :kind suite :why x)) :assertLoss (\"s/l.asl\") :knownRed ((\"s/k.asl\" \"br\" 1 0 :kind suite :why y)) :baseRedOutside () :flaky ((\"s/f.asl\" 2)) :blocked (:fresh 0 :preexisting 1) :deadline (:unrun (\"s/u.asl\")) :suites (\"s/a.asl\" \"s/p.asl\" \"s/k.asl\" \"s/f.asl\" \"s/l.asl\" \"s/u.asl\" \"s/z.asl\") :seconds 1)")

fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/greensTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! runTests -> Bool
  (let [(store (scratch))
        (_ (fr/shellOut (str "/bin/mkdir -p " store "/trains/U1 " store "/trains/U2 " store "/trains/U3 " store "/trains/U4") 5000))
        (_ (fileWrite (str store "/trains/U1/000001.out") (str "(:trainAttempt :n 1)\n" (green "m1") "\n")))
        (_ (fileWrite (str store "/trains/U2/000001.out") (str "(:train :status :failed :error (:err :silentSuites :ran 2 :why \"x\"))\n" (green "m2") "\n")))
        (_ (fileWrite (str store "/trains/U3/000001.out") (str (green "m3") "\n")))
        (_ (fileWrite (str store "/trains/U4/000001.out") (str (excl "m4") "\n")))
        (n1 (cd/dropTrains! store "U1"))
        (n2 (cd/dropTrains! store "U2"))
        (_ (cd/dropTrains! store "U3"))
        (_ (cd/dropTrains! store "U4"))
        (tmpLeft (filter (fn [(f String)] -> Bool (stringContains? f ".tmp.")) (resultOr (dirList store) (list))))
        (rows (gz/readGreens! store))
        (gone (listEmpty? (resultOr (dirList (str store "/trains/U1")) (list))))
        (old (map (fn [(i Int64)] -> String (str "(:green :merged \"o" (stringFromInt64 i) "\" :at 1 :suites (\"s/a.asl\"))")) (range 0 5)))
        (fresh (list "(:green :merged \"o2\" :at 2 :suites (\"s/b.asl\"))" "(:green :merged \"n\" :at 2 :suites (\"s/c.asl\"))"))
        (merged (gz/greensMerge old fresh 4))
        (_ (fr/shellOut (str "/bin/rm -rf " store) 5000))]
    (do (assert (and n1 (and n2 gone)) "dropTrains! still removes the unit's dir")
        (assert (= (map pairFirst rows) (list "m4" "m3" "m1")) (str "the merged units' green rows are kept newest first, the failed attempt's is not: " (stringJoin (map pairFirst rows) " ")))
        (assert (= (optionOr (listLast (map pairSecond rows)) (list)) (list "s/a.asl" "s/b.asl")) "the row keeps the cleared suites")
        (assert (= (optionOr (listHead (map pairSecond rows)) (list "none")) (list "s/a.asl" "s/z.asl")) (str "a knownRed, flaky, preexisting, assertLoss or unrun suite is not recorded: " (stringJoin (optionOr (listHead (map pairSecond rows)) (list)) " ")))
        (assert (listEmpty? tmpLeft) "greens.asn is written through a temp file that is renamed away")
        (assert (= (map (fn [(l String)] -> String (gz/mergedOf l)) merged) (list "o3" "o4" "o2" "n")) (str "a fresh row replaces the old row of its tree and only the newest 4 stay: " (stringJoin (map (fn [(l String)] -> String (gz/mergedOf l)) merged) " "))) 
        true))
