(module asl-target-llvm
  :x [emitLlvmModule emitLlvmProgram emitLlvmModuleFor emitLlvmProgramFor emitLlvmModuleForTarget emitLlvmProgramForTarget emitLlvmRuntimeForTarget emitLlvmSupportForTarget emitLlvmProgramNative! runtimeDecls emitLlvmType emitLlvmBlock emitLlvmStmt emitLlvmExpr emitLlvmClosure emitLlvmPanic emitLlvmSource emitLlvmSourceWith emitLlvmTargetTriple llvmPreamble emitLlvmFunction]
  :i [(asl-ir/types :a irTy)
      (asl-ir/link :a lk)
      (asl-target-llvm/types :a ty)
      (asl-target-llvm/emit :a em)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/wasmRuntime :a wr)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/parRoute :a pr)
      (asl-target-llvm/arrayRoute :a ar)])

fn emitLlvmModule m: irTy/SsaModule -> (Result String (List irTy/IrDiag))
  (emitRouted (ar/routeModule m) (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (ssa/emitLlvmModule (opt/hoistConstants r))))

fn emitLlvmProgram m: irTy/SsaModule entry: String -> (Result String (List irTy/IrDiag))
  (emitRouted (ar/routeModule m) (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (ssa/emitLlvmProgram (opt/hoistConstants r) entry)))

fn emitLlvmModuleFor facts: libc/TripleFacts m: irTy/SsaModule -> (Result String (List irTy/IrDiag))
  (emitRouted (routeFor facts m) (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (ssa/emitLlvmModule (opt/hoistConstants r))))

fn emitLlvmProgramFor facts: libc/TripleFacts m: irTy/SsaModule entry: String -> (Result String (List irTy/IrDiag))
  (emitRouted (routeFor facts m) (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (ssa/emitLlvmProgram (opt/hoistConstants r) entry)))

fn emitLlvmModuleForTarget facts: libc/TripleFacts targetFacts: target/TargetFacts m: irTy/SsaModule -> (Result String (List irTy/IrDiag))
  (mt (emitRouted (routeForTarget facts m) (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (if (target/isWasm32 targetFacts) (ssa/emitLlvmModuleWasm32 r) (ssa/emitLlvmModule r))))
    ((err ds) (err ds))
    ((ok text) (ok (ssa/trapLowering (target/lowerLlvmText text targetFacts) targetFacts))))

fn emitLlvmProgramForTarget facts: libc/TripleFacts targetFacts: target/TargetFacts m: irTy/SsaModule entry: String -> (Result String (List irTy/IrDiag))
  (mt (emitRouted (routeForTarget facts m) (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (if (target/isWasm32 targetFacts) (ssa/emitLlvmProgramWasm32 r entry) (ssa/emitLlvmProgram r entry))))
    ((err ds) (err ds))
    ((ok text) (ok (ssa/trapLowering (target/lowerLlvmText text targetFacts) targetFacts))))

fn emitLlvmRuntimeForTarget facts: libc/TripleFacts targetFacts: target/TargetFacts -> (Result String (List irTy/IrDiag))
  (gr/collectorTextForTarget facts targetFacts)

fn emitLlvmSupportForTarget facts: libc/TripleFacts targetFacts: target/TargetFacts -> (Result String (List irTy/IrDiag))
  (mt (libc/runtimeAbi facts.triple)
    ((none) (err (list (irTy/makeIrDiag "ERR_LLVM_WASM_RUNTIME" (str "libc.asl has no runtimeAbi row for " facts.triple) "asl-target-llvm"))))
    ((some abi) (if (target/isWasm32 targetFacts)
                  (ok (wr/supportText abi))
                  (err (list (irTy/makeIrDiag "ERR_LLVM_WASM_RUNTIME" (str "runtimeAbi support is emitted for wasm32 targets, not " targetFacts.triple) "asl-target-llvm"))))))

fn routeForTarget facts: libc/TripleFacts m: irTy/SsaModule -> (Result rt/Routed (List irTy/IrDiag))
  (mt (routeFor facts m)
    ((err ds) (err ds))
    ((ok r) (if (some? (libc/runtimeAbi facts.triple))
              (ok (rt/Routed :result (lowerWasmPrint r.result) :internal r.internal))
              (ok r))))

fn lowerWasmPrint m: irTy/SsaModule -> irTy/SsaModule
  (if (not (listAny? (fn [(e irTy/SsaExtern)] -> Bool (= e.name "print")) m.externs))
    m
    (irTy/ssaModule m.name m.strings m.types m.records
      (filter (fn [(e irTy/SsaExtern)] -> Bool (!= e.name "print")) m.externs)
      m.globals
      (map (fn [(f irTy/SsaFunction)] -> irTy/SsaFunction
             (irTy/ssaFunction f.name f.captures f.params f.retTy
               (map (fn [(b irTy/SsaBlock)] -> irTy/SsaBlock
                      (irTy/ssaBlock b.label b.params
                        (map (fn [(i irTy/SsaInstr)] -> irTy/SsaInstr
                               (mt i.op
                                 ((irTy/opCall callee args) (if (= callee "print") (irTy/ssaInstr i.dest i.ty (irTy/opBuiltin "print" args)) i))
                                 (_ i)))
                             b.instrs)
                        b.term))
                    f.blocks)))
           m.functions)))

fn ! emitLlvmProgramNative! m: irTy/SsaModule entry: String -> (Result String (List irTy/IrDiag))
  (emitRouted (thenPar (thenPar (rt/routeHost! m) (fn [(r irTy/SsaModule)] -> (Result rt/Routed (List irTy/IrDiag)) (pr/routeHost! r))) (fn [(r irTy/SsaModule)] -> (Result rt/Routed (List irTy/IrDiag)) (ar/routeModule r)))
              (fn [(r irTy/SsaModule)] -> (Result String (List irTy/IrDiag)) (ssa/emitLlvmProgram (opt/hoistConstants r) entry)))

fn routeFor facts: libc/TripleFacts m: irTy/SsaModule -> (Result rt/Routed (List irTy/IrDiag))
  (thenPar (thenPar (rt/routeModule facts m) (fn [(r irTy/SsaModule)] -> (Result rt/Routed (List irTy/IrDiag)) (pr/routeModule facts r))) (fn [(r irTy/SsaModule)] -> (Result rt/Routed (List irTy/IrDiag)) (ar/routeModule r)))

fn thenPar routed: (Result rt/Routed (List irTy/IrDiag)) par: (fn [irTy/SsaModule] -> (Result rt/Routed (List irTy/IrDiag))) -> (Result rt/Routed (List irTy/IrDiag))
  (mt routed
    ((err diags) (err diags))
    ((ok r) (mt (par r.result)
              ((err diags) (err diags))
              ((ok r2) (ok (rt/Routed :result r2.result :internal (listAppend r.internal r2.internal)))))))

fn emitRouted routed: (Result rt/Routed (List irTy/IrDiag)) emit: (fn [irTy/SsaModule] -> (Result String (List irTy/IrDiag))) -> (Result String (List irTy/IrDiag))
  (mt routed
    ((err diags) (err diags))
    ((ok r) (rt/internalize (ar/finishText (ar/routedNames? r.internal) (pr/finishText (pr/routedNames? r.internal) (emit r.result))) r.internal)))

fn runtimeDecls -> (List String)
  (ssa/runtimeDecls)

fn emitLlvmType t: irTy/IrType -> Str
  (ty/emitLlvmType t)

fn emitLlvmClosure name: Str envFields: (List Str) -> Str
  (ty/emitLlvmClosure name envFields)

fn emitLlvmPanic code: Int64 msg: Str -> Str
  (ty/emitLlvmPanic code msg)

fn emitLlvmTargetTriple target: Str -> Str
  (ty/emitLlvmTargetTriple target)

fn emitLlvmBlock stmts: (List irTy/IrStmt) -> Str
  (em/emitLlvmBlock stmts)

fn emitLlvmStmt stmt: irTy/IrStmt -> Str
  (em/emitLlvmStmt stmt)

fn emitLlvmExpr expr: irTy/IrExpr target: Str ty: irTy/IrType -> Str
  (em/emitLlvmExpr expr target ty)

fn emitLlvmFunction f: irTy/IrFunction -> Str
  (em/emitLlvmFunction f)

fn ! linkedSourceModule! src: String -> (Result irTy/SsaModule (List irTy/IrDiag))
  (let [(dir "asl/host/out/.emitLlvmSource")
        (made (dirCreate dir))
        (path (str dir "/" (stringFromInt64 (monotonicNs)) ".asl"))
        (written (if (ok? made) (fileWrite path src) (err "scratch directory unavailable")))
        (result (if (ok? written) (lk/linkEntryBare! path)
                  (err (list (irTy/makeIrDiag "ERR_LLVM_SCRATCH" (str "cannot write a temporary source file to link against the prelude and its imports under " dir) path)))))
        (_ (if (fileExists? path) (pathRemove path) (ok ())))]
    result)

fn ! emitLlvmSource src: String entry: String -> (Result String (List irTy/IrDiag))
  (llvmFromLowered (linkedSourceModule! src) entry)

fn emitLlvmSourceWith src: String preludeSrc: String entry: String -> (Result String (List irTy/IrDiag))
  (llvmFromLowered (lk/lowerSourceWith src preludeSrc) entry)

fn llvmFromLowered lowered: (Result irTy/SsaModule (List irTy/IrDiag)) entry: String -> (Result String (List irTy/IrDiag))
  (mt lowered
    ((err diags) (err diags))
    ((ok m)
      (let [(actualEntry (if (= entry "") "main" entry))]
        (if (listAny? (fn [(f irTy/SsaFunction)] -> Bool (= f.name actualEntry)) m.functions)
          (emitLlvmProgram m actualEntry)
          (err (list (irTy/IrDiag :code "ERR_LLVM_NO_ENTRY" :message (str "entry function " actualEntry " is not defined") :locus actualEntry)))))))

fn llvmPreamble target: Str -> Str
  (em/llvmPreamble target)
