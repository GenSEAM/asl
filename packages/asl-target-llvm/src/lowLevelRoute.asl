(module asl-target-llvm/lowLevelRoute
  :x [Feature features sizedFeature bitFeature bufFeature atomicFeature rawFeature viewFeature featureNames routedBuiltins wrapperName kindCode kindWidth kindSigned? lowLevelCalls routes? routesWith? routeModule routeModuleWith routeLinked routedNames?]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-checker/numKinds :a nk)
      (asl-target-llvm/sysRoute :a rt)])

schema Feature
  name: String
  builtins: (List String)
  functions: (List ty/SsaFunction)
  externs: (List ty/SsaExtern)

; (:m :ref LL-ROUTE-HUB :do "one empty table per feature emitter; sizedRt bitRt bufRt atomicRt rawRt viewRt each fill their own through a function that returns their Feature, and a builtin no table lists stays unrouted")
fn emptyFeature name: String -> Feature
  (Feature :name name :builtins (list) :functions (list) :externs (list))

fn sizedFeature -> Feature
  (emptyFeature "sizedRt")

fn bitFeature -> Feature
  (emptyFeature "bitRt")

fn bufFeature -> Feature
  (emptyFeature "bufRt")

fn atomicFeature -> Feature
  (emptyFeature "atomicRt")

fn rawFeature -> Feature
  (emptyFeature "rawRt")

fn viewFeature -> Feature
  (emptyFeature "viewRt")

fn features -> (List Feature)
  (list (sizedFeature) (bitFeature) (bufFeature) (atomicFeature) (rawFeature) (viewFeature))

fn featureNames -> (List String)
  (map (fn [(f Feature)] -> String f.name) (features))

fn routedBuiltins fs: (List Feature) -> (List String)
  (fold (fn [(acc (List String)) (f Feature)] -> (List String) (listAppend acc f.builtins)) (list) fs)

fn wrapperName builtin: String -> String
  (str "asl-target-llvm/lowLevelRoute." builtin)

fn kindCode name: String -> Int64
  (nk/intKindCode name)

fn kindWidth name: String -> Int64
  (nk/intKindWidth name)

fn kindSigned? name: String -> Bool
  (nk/intKindSigned? name)

fn diag code: String message: String locus: String -> ty/IrDiag
  (ty/makeIrDiag code message locus)

fn lowLevelCalls fs: (List Feature) m: ty/SsaModule -> (List String)
  (let [(wanted (routedBuiltins fs))]
    (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
            (fold (fn [(acc2 (List String)) (b ty/SsaBlock)] -> (List String)
                    (fold (fn [(acc3 (List String)) (i ty/SsaInstr)] -> (List String)
                            (match i.op
                              ((ty/opBuiltin n _) (if (and (listContains? wanted n) (not (listContains? acc3 n))) (listAppend acc3 (list n)) acc3))
                              (_ acc3)))
                          acc2 b.instrs))
                  acc f.blocks))
          (list) m.functions))

fn routesWith? fs: (List Feature) m: ty/SsaModule -> Bool
  (not (listEmpty? (lowLevelCalls fs m)))

fn routes? m: ty/SsaModule -> Bool
  (routesWith? (features) m)

fn rewriteOp wanted: (List String) op: ty/SsaOp -> ty/SsaOp
  (match op
    ((ty/opBuiltin n args) (if (listContains? wanted n) (ty/opCall (wrapperName n) args) op))
    (_ op))

fn rewriteFunction wanted: (List String) f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock b.label b.params
             (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr (ty/ssaInstr i.dest i.ty (rewriteOp wanted i.op))) b.instrs)
             b.term))
         f.blocks))

fn mergeExterns own: (List ty/SsaExtern) added: (List ty/SsaExtern) locus: String -> (Result (List ty/SsaExtern) (List ty/IrDiag))
  (let [(clashes (filter (fn [(e ty/SsaExtern)] -> Bool (listAny? (fn [(o ty/SsaExtern)] -> Bool (and (= o.name e.name) (not (rt/sameSignature? o e)))) own)) added))
        (fresh (filter (fn [(e ty/SsaExtern)] -> Bool (not (listAny? (fn [(o ty/SsaExtern)] -> Bool (= o.name e.name)) own))) added))]
    (if (listEmpty? clashes)
      (ok (listAppend (map (fn [(o ty/SsaExtern)] -> ty/SsaExtern (rt/nativeIfAny o added)) own) fresh))
      (err (map (fn [(e ty/SsaExtern)] -> ty/IrDiag (diag "ERR_LLVM_LLROUTE_EXTERN" (str "extern '" e.name "' is declared with another signature than a low-level emitter needs") locus)) clashes))))

fn usedFeatures fs: (List Feature) wanted: (List String) -> (List Feature)
  (filter (fn [(f Feature)] -> Bool (listAny? (fn [(n String)] -> Bool (listContains? wanted n)) f.builtins)) fs)

fn dedupeFunctions fns: (List ty/SsaFunction) -> (List ty/SsaFunction)
  (fold (fn [(acc (List ty/SsaFunction)) (f ty/SsaFunction)] -> (List ty/SsaFunction)
          (if (listAny? (fn [(g ty/SsaFunction)] -> Bool (= g.name f.name)) acc) acc (listAppend acc (list f))))
        (list) fns)

fn routeVerified fs: (List Feature) m: ty/SsaModule wanted: (List String) -> (Result rt/Routed (List ty/IrDiag))
  (let [(used (usedFeatures fs wanted))
        (added (dedupeFunctions (fold (fn [(acc (List ty/SsaFunction)) (f Feature)] -> (List ty/SsaFunction) (listAppend acc f.functions)) (list) used)))
        (clashes (filter (fn [(f ty/SsaFunction)] -> Bool (listAny? (fn [(g ty/SsaFunction)] -> Bool (= g.name f.name)) m.functions)) added))]
    (if (not (listEmpty? clashes))
      (err (map (fn [(f ty/SsaFunction)] -> ty/IrDiag (diag "ERR_LLVM_LLROUTE_NAME" (str "module function '" f.name "' has the name of a routed low-level function") f.name)) clashes))
      (match (mergeExterns m.externs (fold (fn [(acc (List ty/SsaExtern)) (f Feature)] -> (List ty/SsaExtern) (listAppend acc f.externs)) (list) used) m.name)
        ((err ds) (err ds))
        ((ok externs)
          (ok (rt/Routed :result (ty/ssaModule m.name m.strings m.types m.records externs m.globals
                                   (listAppend (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (rewriteFunction wanted f)) m.functions) added))
                         :internal (map (fn [(f ty/SsaFunction)] -> String f.name) added)))))))

fn routeModuleAs fs: (List Feature) m: ty/SsaModule check: Bool -> (Result rt/Routed (List ty/IrDiag))
  (let [(wanted (lowLevelCalls fs m))]
    (if (listEmpty? wanted)
      (ok (rt/Routed :result m :internal (list)))
      (match (if check (vfy/verifySsa m) (ok ()))
        ((err ds) (err ds))
        ((ok _) (routeVerified fs m wanted)))))

fn routeModuleWith fs: (List Feature) m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (routeModuleAs fs m true)

fn routeModule m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (routeModuleAs (features) m true)

fn routeLinked m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (routeModuleAs (features) m false)

fn routedNames? internal: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringStartsWith? n "asl-target-llvm/lowLevelRoute.")) internal)
