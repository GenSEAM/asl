(module asl-target-llvm/parRoute
  :x [parCalls routes? routeModule routeHost! routedNames? finishText helperDefinitions]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/parallel :a par)
      (asl-target-llvm/sysRoute :a rt)])

fn routedNames -> (List String)
  (list "parMap" "parFold")

fn parCalls m: ty/SsaModule -> (List (Pair String Int64))
  (fold (fn [(acc (List (Pair String Int64))) (f ty/SsaFunction)] -> (List (Pair String Int64))
          (fold (fn [(acc2 (List (Pair String Int64))) (b ty/SsaBlock)] -> (List (Pair String Int64))
                  (fold (fn [(acc3 (List (Pair String Int64))) (i ty/SsaInstr)] -> (List (Pair String Int64))
                          (mt i.op
                            ((ty/opBuiltin n args)
                              (let [(p (pair n (listLength args)))]
                                (if (and (listContains? (routedNames) n) (not (listContains? acc3 p))) (listAppend acc3 (list p)) acc3)))
                            (_ acc3)))
                        acc2 b.instrs))
                acc f.blocks))
        (list) m.functions)

fn routes? m: ty/SsaModule -> Bool
  (not (listEmpty? (parCalls m)))

fn rewriteOp op: ty/SsaOp -> ty/SsaOp
  (mt op
    ((ty/opBuiltin n args) (if (listContains? (routedNames) n) (ty/opCall (par/wrapperName n (listLength args)) args) op))
    (_ op))

fn rewriteFunction f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock b.label b.params
             (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr (ty/ssaInstr i.dest i.ty (rewriteOp i.op))) b.instrs)
             b.term))
         f.blocks))

fn diag code: String message: String locus: String -> ty/IrDiag
  (ty/makeIrDiag code message locus)

fn poolWith strings: (List String) wanted: (List String) -> (Pair (List String) (Map String Int64))
  (fold (fn [(acc (Pair (List String) (Map String Int64))) (s String)] -> (Pair (List String) (Map String Int64))
          (let [(have (pairFirst acc))]
            (mt (listIndexOf have s)
              ((some i) (pair have (mapSet (pairSecond acc) s i)))
              ((none) (pair (listAppend have (list s)) (mapSet (pairSecond acc) s (listLength have)))))))
        (pair strings (mapEmpty)) wanted)

fn mergeExterns own: (List ty/SsaExtern) added: (List ty/SsaExtern) locus: String -> (Result (List ty/SsaExtern) (List ty/IrDiag))
  (let [(clashes (filter (fn [(e ty/SsaExtern)] -> Bool (listAny? (fn [(o ty/SsaExtern)] -> Bool (and (= o.name e.name) (not (= o e)))) own)) added))
        (fresh (filter (fn [(e ty/SsaExtern)] -> Bool (not (listAny? (fn [(o ty/SsaExtern)] -> Bool (= o.name e.name)) own))) added))]
    (if (listEmpty? clashes)
      (ok (listAppend own fresh))
      (err (map (fn [(e ty/SsaExtern)] -> ty/IrDiag (diag "ERR_LLVM_PARROUTE_EXTERN" (str "extern '" e.name "' is declared with another signature than asl-target-llvm/parallel needs") locus)) clashes))))

fn routeVerified facts: libc/TripleFacts m: ty/SsaModule calls: (List (Pair String Int64)) -> (Result rt/Routed (List ty/IrDiag))
  (let [(pooled (poolWith m.strings (par/parStrings)))]
    (mt (par/parFunctions facts (pairSecond pooled) calls)
      ((err e) (err (list (diag "ERR_LLVM_PARROUTE_FACTS" e m.name))))
      ((ok added)
        (let [(names (map (fn [(f ty/SsaFunction)] -> String f.name) added))
              (clashes (filter (fn [(f ty/SsaFunction)] -> Bool (listContains? names f.name)) m.functions))]
          (if (not (listEmpty? clashes))
            (err (map (fn [(f ty/SsaFunction)] -> ty/IrDiag (diag "ERR_LLVM_PARROUTE_NAME" (str "module function '" f.name "' has the name of a routed parallel function") f.name)) clashes))
            (mt (mergeExterns m.externs (par/parExterns facts) m.name)
              ((err ds) (err ds))
              ((ok externs)
                (ok (rt/Routed :result (ty/ssaModule m.name (pairFirst pooled) m.types m.records externs (listAppend m.globals (par/parGlobals))
                                         (listAppend (map rewriteFunction m.functions) added))
                               :internal names)))))))))

fn routeModule facts: libc/TripleFacts m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (let [(calls (parCalls m))]
    (if (listEmpty? calls)
      (ok (rt/Routed :result m :internal (list)))
      (mt (vfy/verifySsa m)
        ((err ds) (err ds))
        ((ok _) (routeVerified facts m calls)))))

fn unameWords text: String -> (Option (Pair String String))
  (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace text "\n" " ") " ")))]
    (if (= (listLength ws) 2)
      (some (pair (optionOr (listGet ws 0) "") (optionOr (listGet ws 1) "")))
      (none)))

fn ! routeHost! m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (if (routes? m)
    (let [(out (processRun "uname -s -m"))
          (host (if (= out.exitCode 0) (unameWords out.stdout) (none)))]
      (mt host
        ((none) (err (list (diag "ERR_LLVM_PARROUTE_HOST" (str "uname -s -m exited " out.exitCode " printing '" out.stdout "' " out.stderr) m.name))))
        ((some p) (mt (rt/routeFactsFor (rt/tripleOf (pairFirst p) (pairSecond p)))
                    ((none) (ok (rt/Routed :result m :internal (list))))
                    ((some facts) (routeModule facts m))))))
    (ok (rt/Routed :result m :internal (list))))

fn helperDefinitions -> (List (Pair String String))
  (list (pair "declare ptr @aslParWord0(%Val)"
              "define internal ptr @aslParWord0(%Val %v) {\n  %w = extractvalue %Val %v, 0\n  %p = inttoptr i64 %w to ptr\n  ret ptr %p\n}")
        (pair "declare ptr @aslParWord1(%Val)"
              "define internal ptr @aslParWord1(%Val %v) {\n  %w = extractvalue %Val %v, 1\n  %p = inttoptr i64 %w to ptr\n  ret ptr %p\n}")
        (pair "declare %Val @aslParMakeVal(ptr, ptr)"
              "define internal %Val @aslParMakeVal(ptr %a, ptr %b) {\n  %x = ptrtoint ptr %a to i64\n  %y = ptrtoint ptr %b to i64\n  %v0 = insertvalue %Val undef, i64 %x, 0\n  %v1 = insertvalue %Val %v0, i64 %y, 1\n  ret %Val %v1\n}")
        (pair "declare ptr @aslParAlloc(i32, i64)"
              "define internal ptr @aslParAlloc(i32 %t, i64 %n) {\n  %o = call ptr @asl_alloc(i32 %t, i64 %n)\n  ret ptr %o\n}")
        (pair "declare ptr @aslParErrorMsg()"
              "define internal ptr @aslParErrorMsg() {\n  %text = call ptr @aslErrorText()\n  ret ptr %text\n}")
        (pair "declare i32 @setjmp(ptr)" "declare i32 @setjmp(ptr) returns_twice"))

fn allocDecl -> String
  "declare ptr @asl_alloc(i32, i64)"

fn finishLines lines: (List String) -> (Result (List String) String)
  (let [(missing (filter (fn [(d (Pair String String))] -> Bool (!= (listLength (filter (fn [(l String)] -> Bool (= l (pairFirst d))) lines)) 1)) (helperDefinitions)))]
    (if (not (listEmpty? missing))
      (err (str "the emitted text does not declare exactly once: " (stringJoin (map (fn [(d (Pair String String))] -> String (pairFirst d)) missing) "; ")))
      (let [(replaced (map (fn [(l String)] -> String
                             (fold (fn [(acc String) (d (Pair String String))] -> String (if (= l (pairFirst d)) (pairSecond d) acc)) l (helperDefinitions)))
                           lines))]
        (ok (if (listContains? lines (allocDecl)) replaced (listAppend replaced (list (allocDecl))))))))

fn routedNames? internal: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringStartsWith? n "asl-target-llvm/parallel.")) internal)

fn finishText routed: Bool res: (Result String (List ty/IrDiag)) -> (Result String (List ty/IrDiag))
  (mt res
    ((err ds) (err ds))
    ((ok text)
      (if (not routed)
        (ok text)
        (mt (finishLines (stringSplit text "\n"))
          ((err e) (err (list (diag "ERR_LLVM_PARROUTE_TEXT" e "asl-target-llvm/parRoute"))))
          ((ok lines) (ok (stringJoin lines "\n")))))))
