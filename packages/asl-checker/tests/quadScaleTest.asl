(module asl-checker/tests/quadScaleTest
  :x [wideSource checkCpuUs runTests]
  :i [(asl-parser/ast :a a) (asl-checker/check :a chk) (asl-checker/types :a ty)])

fn importSrc i: Int64 -> String
  (str "(q/m" i " :a m" i ")")

fn wideSource n: Int64 -> String
  (str "(module q/wide :x [main] :i [" (stringJoin (map importSrc (range 0 n)) " ") "])\n\n"
       "fn main -> Int64\n  (listLength (list " (stringJoin (map stringFromInt64 (range 0 n)) " ") "))\n")

fn ! cpuUs -> Int64
  (mt (procRusage)
    ((err e) (do (assert false (str "procRusage failed: " e)) 0))
    ((ok usage) (+ usage.selfUserUs usage.selfSysUs)))

fn ! checkOnce forms: (List a/TopForm) -> Int64
  (let [(t0 (cpuUs)) (ds (chk/checkModule forms (mapEmpty) "q/wide.asl")) (t1 (cpuUs))]
    (do (assert (> (listLength ds) 0) "the unresolved imports are diagnosed") (- t1 t0)))

fn ! checkCpuUs n: Int64 -> Int64
  (let [(forms (optionOr (resultToOption (a/parseForChecker (wideSource n))) (list)))
        (best (min (checkOnce forms) (checkOnce forms)))]
    (do (assert (= (listLength forms) 2) (str "the wide module parses into its header and main, got " (listLength forms)))
        (print (str "(quadScale :n " n " :checkCpuUs " best ")"))
        best))

fn ! testWideShape -> Bool
  (let [(forms (optionOr (resultToOption (a/parseForChecker (wideSource 5))) (list)))
        (ds (chk/checkModule forms (mapEmpty) "q/wide.asl"))
        (unresolved (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "unresolved-import")) ds))]
    (do (assert (= (listLength unresolved) 5) (str "each of the 5 imports is unresolved once: " (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds)))
        (assert (= (map (fn [(d ty/Diagnostic)] -> String d.message) unresolved)
                   (list "no module q/m4 on the search path" "no module q/m3 on the search path" "no module q/m2 on the search path" "no module q/m1 on the search path" "no module q/m0 on the search path"))
                (str "unresolved imports keep their order: " (map (fn [(d ty/Diagnostic)] -> String d.message) unresolved)))
        true))

fn ! testCheckIsLinear -> Bool
  (let [(small (checkCpuUs 2000))
        (large (checkCpuUs 4000))]
    (do (assert (> small 0) "the 2000-wide check is measured")
        (assert (<= (* large 10) (* small 25))
                (str "checking a module with n imports and an n-argument call scales linearly: 2x n cost "
                     large "us CPU vs " small "us, above 2.5x"))
        true))

fn ! runTests -> Bool
  (do (assert (testWideShape) "testWideShape")
      (assert (testCheckIsLinear) "testCheckIsLinear")
      true)
