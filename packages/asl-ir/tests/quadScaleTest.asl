(module asl-ir/tests/quadScaleTest
  :x [wideModule workloadCpuUs runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)])

fn leafFunction i: Int64 -> ty/SsaFunction
  (ty/ssaFunction (str "f" i) (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal)
                  (list (ty/ssaBlock "entry" (list) (list (ty/ssaInstr "%r" (ty/tyVal) (ty/opCall "g" (list "x")))) (ty/termReturn "%r"))))

fn callInstr i: Int64 -> ty/SsaInstr
  (ty/ssaInstr (str "%c" i) (ty/tyVal) (ty/opCall (str "f" i) (list "x")))

fn builtinInstr i: Int64 -> ty/SsaInstr
  (ty/ssaInstr (str "%b" i) (ty/tyVal) (ty/opBuiltin "wide" (list "x")))

fn wideFunction n: Int64 -> ty/SsaFunction
  (ty/ssaFunction "main" (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal)
                  (list (ty/ssaBlock "entry" (list) (listAppend (map callInstr (range 0 n)) (map builtinInstr (range 0 n))) (ty/termReturn "x"))))

fn wideModule n: Int64 -> ty/SsaModule
  (ty/ssaModule "q/wide" (list)
                (map (fn [(i Int64)] -> ty/SsaTypeDecl (ty/ssaTypeDecl (str "T" (/ i 2)) (list (ty/ssaVariant "v" 0)))) (range 0 n))
                (map (fn [(i Int64)] -> ty/SsaRecordDecl (ty/ssaRecordDecl (str "R" (/ i 2)) (list "a"))) (range 0 n))
                (list) (list)
                (cons (ty/ssaFunction "g" (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal) (list (ty/ssaBlock "entry" (list) (list) (ty/termReturn "x"))))
                      (cons (wideFunction n) (map leafFunction (range 0 n)))))

fn ! cpuUs -> Int64
  (mt (procRusage)
    ((err e) (do (assert false (str "procRusage failed: " e)) 0))
    ((ok usage) (+ usage.selfUserUs usage.selfSysUs)))

fn workload m: ty/SsaModule -> Int64
  (let [(main (optionOr (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name "main")) m.functions)) (wideFunction 0)))
        (perModule (map (fn [(f ty/SsaFunction)] -> ty/SsaModule (ty/ssaModule f.name (list) (list) (list) (list) (list) (list f))) m.functions))
        (rewritten (lk/rewriteModuleBuiltins (mapSet (mapEmpty) "wide" "g") m))]
    (+ (listLength (lk/firstByName m.types))
       (+ (listLength (lk/firstRecordByName m.records))
          (+ (listLength (lk/allFunctions perModule))
             (+ (listLength (lk/functionBuiltinRefs main))
                (+ (listLength (vfy/verifySsaDiags rewritten))
                   (stringLength (prn/printSsa rewritten))))))))

fn ! measureOnce m: ty/SsaModule -> Int64
  (let [(t0 (cpuUs)) (size (workload m)) (t1 (cpuUs))]
    (do (assert (> size 0) "the workload computes") (- t1 t0)))

fn ! workloadCpuUs n: Int64 -> Int64
  (let [(m (wideModule n))
        (best (min (measureOnce m) (measureOnce m)))]
    (do (print (str "(quadScale :n " n " :cpuUs " best ")"))
        best))

fn ! testWorkloadShape -> Bool
  (let [(m (wideModule 6))
        (rewritten (lk/rewriteModuleBuiltins (mapSet (mapEmpty) "wide" "g") m))
        (main (optionOr (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name "main")) rewritten.functions)) (wideFunction 0)))
        (text (prn/printSsa rewritten))]
    (do (assert (= (map (fn [(d ty/SsaTypeDecl)] -> String d.name) (lk/firstByName m.types)) (list "T0" "T1" "T2")) "firstByName keeps the first of each name in order")
        (assert (= (map (fn [(d ty/SsaRecordDecl)] -> String d.name) (lk/firstRecordByName m.records)) (list "R0" "R1" "R2")) "firstRecordByName keeps the first of each name in order")
        (assert (= (listLength (lk/functionBuiltinRefs (wideFunction 6))) 6) "every builtin instruction is a builtin reference")
        (assert (= (listLength main.blocks) 1) "the rewritten main keeps one block")
        (assert (stringContains? text "(let %b5 val (call g x))") (str "the builtin calls are rewritten to the resolved function in order:\n" text))
        (assert (= (map (fn [(d ty/IrDiag)] -> String d.locus) (vfy/verifySsaDiags rewritten)) (list "q/wide/T0" "q/wide/T1" "q/wide/T2" "q/wide/R0" "q/wide/R1" "q/wide/R2"))
                (str "verify reports each repeated type and record once, in declaration order: " (vfy/verifySsaDiags rewritten)))
        true))

fn ! testWorkloadIsLinear -> Bool
  (let [(small (workloadCpuUs 3000))
        (large (workloadCpuUs 6000))]
    (do (assert (> small 0) "the 3000-wide workload is measured")
        (assert (<= (* large 10) (* small 25))
                (str "link merge, builtin rewrite, verify and print of a module with n functions, n types and a 2n-instruction block scale linearly: 2x n cost "
                     large "us CPU vs " small "us, above 2.5x"))
        true))

fn ! runTests -> Bool
  (do (assert (testWorkloadShape) "testWorkloadShape")
      (assert (testWorkloadIsLinear) "testWorkloadIsLinear")
      true)
