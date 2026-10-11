(module asl-parser/tests/parseExportScaleTest
  :x [declsSource parseExportScaleCpuUs runTests]
  :i [(asl-parser/ast :a a)])

fn fnDeclText i: Int64 -> String
  (str "fn f" i " -> Int64\n  (+ " i " " i ")\n\n")

fn fnNameOf i: Int64 -> String
  (str "f" i)

fn declsSource n: Int64 -> String
  (let [(names (stringJoin (map fnNameOf (range 0 n)) " "))
        (decls (stringJoin (map fnDeclText (range 0 n)) ""))]
    (str "(module q/escale :x [" names "] :i [])\n\n" decls))

fn ! cpuUs -> Int64
  (mt (procRusage)
    ((err e) (do (assert false (str "procRusage failed: " e)) 0))
    ((ok usage) (+ usage.selfUserUs usage.selfSysUs)))

fn ! parseWorkload n: Int64 -> Int64
  (let [(src (declsSource n))]
    (mt (a/parseForChecker src)
      ((ok forms) (listLength forms))
      ((err e) (do (assert false (str "declsSource(" (stringFromInt64 n) ") parses: " e.msg)) 0))))

fn ! measureOnce n: Int64 -> Int64
  (let [(t0 (cpuUs)) (size (parseWorkload n)) (t1 (cpuUs))]
    (do (assert (> size 0) "the workload parses to a nonempty form list")
        (- t1 t0)))

fn ! parseExportScaleCpuUs n: Int64 -> Int64
  (let [(best (min (measureOnce n) (min (measureOnce n) (measureOnce n))))]
    (do (print (str "(parseExportScale :n " n " :cpuUs " best ")"))
        best))

fn blankDefun -> a/DefunNode
  (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "" :docstring "" :body (list) :bodyPos (list))

fn asDefun t: a/TopForm -> a/DefunNode
  (mt t ((a/topDefun d) d) (_ (blankDefun)))

fn isDefun? t: a/TopForm -> Bool
  (mt t ((a/topDefun _) true) (_ false))

fn defsOf forms: (List a/TopForm) -> (List a/DefunNode)
  (mt (listHead forms)
    ((none) (list))
    ((some t) (mt t
                ((a/topModule m) (map asDefun (filter isDefun? m.defs)))
                (_ (list)))))

fn ! testExportFlagsAreExact -> Bool
  (let [(src (str "(module q/esel :x [f0 f2] :i [])\n\n" (fnDeclText 0) (fnDeclText 1) (fnDeclText 2)))
        (forms (mt (a/parseForChecker src) ((ok fs) fs) ((err e) (do (assert false (str "q/esel parses: " e.msg)) (list)))))
        (defs (defsOf forms))
        (byName (fn [(n String)] -> Bool (optionOr (mt (listHead (filter (fn [(d a/DefunNode)] -> Bool (= d.name n)) defs)) ((some d) (some d.isExported)) ((none) (none))) false)))]
    (do (assert (= (listLength defs) 3) (str "q/esel has 3 fn decls, got " (listLength defs)))
        (assert (byName "f0") "f0 is in :x and must be isExported")
        (assert (not (byName "f1")) "f1 is not in :x and must not be isExported")
        (assert (byName "f2") "f2 is in :x and must be isExported")
        true))

fn ! testParseScalesLinearlyInExportCount -> Bool
  (let [(small (parseExportScaleCpuUs 2000))
        (large (parseExportScaleCpuUs 8000))
        (ratio (/ (* large 100) small))]
    (do (assert (> small 0) "the 2000-decl workload is measured")
        (print (str "(parseExportScale :ratio4x " ratio " :pct)"))
        (assert (<= (* large 100) (* small 800))
                (str "parseForChecker of a module exporting n of its own n functions (listContains?/O(n) per decl would be O(n^2), ~16x at 4x n) scales close to linearly: 4x n cost "
                     large "us CPU vs " small "us (ratio " ratio "%), above the 8x (800%) bound"))
        true))

fn ! runTests -> Bool
  (do (assert (testExportFlagsAreExact) "testExportFlagsAreExact")
      (assert (testParseScalesLinearlyInExportCount) "testParseScalesLinearlyInExportCount")
      true)
