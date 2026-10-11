(module asl-ir/tests/lowerImportScaleTest
  :x [depSource importScaleCpuUs runTests]
  :i [(asl-ir/lower :a low)
      (asl-ir/types :a ty)
      (asl-parser/ast :a ast)])

fn depDeclText i: Int64 -> String
  (str "fn d" i " -> Int64\n  (+ " i " " i ")\n\n")

fn depNameOf i: Int64 -> String
  (str "d" i)

fn depSource n: Int64 -> String
  (let [(names (stringJoin (map depNameOf (range 0 n)) " "))
        (decls (stringJoin (map depDeclText (range 0 n)) ""))]
    (str "(module q/iscale :x [" names "] :i [])\n\n" decls))

fn mainCallingSource -> String
  "(module q/imain :x [m] :i [(q/iscale :a dep)])\n\nfn m -> Int64\n  (dep/d0)\n"

fn parsed src: String -> (List ast/TopForm)
  (mt (ast/parse src) ((ok fs) fs) ((err _) (list)))

fn ! cpuUs -> Int64
  (mt (procRusage)
    ((err e) (do (assert false (str "procRusage failed: " e)) 0))
    ((ok usage) (+ usage.selfUserUs usage.selfSysUs)))

fn linkedAgainst depForms: (List ast/TopForm) -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(mainSrc (mainCallingSource))
        (mainForms (parsed mainSrc))
        (positions (low/declPositions mainSrc))]
    (low/lowerLinked mainForms positions (low/LinkScope :path "q/imain.asl" :imports (mapSet (mapEmpty) "dep" depForms) :prelude (list) :strings (list) :only (none))))

fn ! importWorkload n: Int64 -> Int64
  (let [(depForms (parsed (depSource n)))]
    (mt (linkedAgainst depForms)
      ((ok m) (listLength m.functions))
      ((err ds) (do (assert false (str "depSource(" (stringFromInt64 n) ") links: " (listLength ds) " diag(s)")) 0))))

fn ! measureOnce n: Int64 -> Int64
  (let [(t0 (cpuUs)) (size (importWorkload n)) (t1 (cpuUs))]
    (do (assert (> size 0) "the workload links to a nonempty function list")
        (- t1 t0)))

fn ! importScaleCpuUs n: Int64 -> Int64
  (let [(best (min (measureOnce n) (min (measureOnce n) (measureOnce n))))]
    (do (print (str "(importScale :n " n " :cpuUs " best ")"))
        best))

fn linkedCalling depForms: (List ast/TopForm) callee: String -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(mainSrc (str "(module q/imain2 :x [m] :i [(q/ihide :a dep)])\n\nfn m -> Int64\n  (dep/" callee ")\n"))
        (mainForms (parsed mainSrc))
        (positions (low/declPositions mainSrc))]
    (low/lowerLinked mainForms positions (low/LinkScope :path "q/imain2.asl" :imports (mapSet (mapEmpty) "dep" depForms) :prelude (list) :strings (list) :only (none))))

fn ! testHiddenImportsStayHidden -> Bool
  (let [(depSrc "(module q/ihide :x [visible0] :i [])\n\nfn visible0 -> Int64\n  0\n\nfn hidden1 -> Int64\n  1\n")
        (depForms (parsed depSrc))
        (visibleRes (linkedCalling depForms "visible0"))
        (hiddenRes (linkedCalling depForms "hidden1"))]
    (do (assert (mt visibleRes ((ok _) true) ((err _) false)) "an export in :x links through the import")
        (assert (mt hiddenRes ((ok _) false) ((err _) true)) "a dep function not in :x must stay unreachable through the import")
        true))

fn ! testImportScalesLinearlyInDepSize -> Bool
  (let [(small (importScaleCpuUs 4000))
        (large (importScaleCpuUs 16000))
        (ratio (/ (* large 100) small))]
    (do (assert (> small 0) "the 4000-decl dep workload is measured")
        (print (str "(importScale :ratio4x " ratio " :pct)"))
        (assert (<= (* large 100) (* small 800))
                (str "lowerLinked against a dep module exporting all n of its own n functions (visible?/listContains? O(n) per decl would be O(n^2), ~16x at 4x n) scales close to linearly: 4x n cost "
                     large "us CPU vs " small "us (ratio " ratio "%), above the 8x (800%) bound"))
        true))

fn ! runTests -> Bool
  (do (assert (testHiddenImportsStayHidden) "testHiddenImportsStayHidden")
      (assert (testImportScalesLinearlyInDepSize) "testImportScalesLinearlyInDepSize")
      true)
