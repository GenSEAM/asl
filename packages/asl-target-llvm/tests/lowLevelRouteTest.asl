(module asl-target-llvm/tests/lowLevelRouteTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/lowLevelRoute :a llr)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/ssa :a ssa)])

fn mkBlock label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn oneBlockFn name: String params: (List ty/SsaParam) instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaFunction
  (ty/ssaFunction name (list) params (ty/tyI64) (list (mkBlock "entry" instrs term)))

fn moduleOf externs: (List ty/SsaExtern) functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" (list) (list) (list) externs (list) functions)

fn callerOf builtin: String -> ty/SsaFunction
  (oneBlockFn "run" (list)
    (list (ty/ssaInstr "a" (ty/tyI64) (ty/opConst (ty/constInt 7)))
          (ty/ssaInstr "r" (ty/tyI64) (ty/opBuiltin builtin (list "a"))))
    (ty/termReturn "r"))

fn helperFn builtin: String -> ty/SsaFunction
  (oneBlockFn (llr/wrapperName builtin) (list (ty/ssaParam "x" (ty/tyI64))) (list) (ty/termReturn "x"))

fn fixtureFeature -> llr/Feature
  (llr/Feature :name "fixtureRt" :builtins (list "llFixtureId") :functions (list (helperFn "llFixtureId")) :externs (list))

fn facts -> (Option libc/TripleFacts)
  (match (rt/routeFactsFor "darwin-arm64")
    ((some f) (some f))
    ((none) (rt/routeFactsFor "linux-x86_64")))

fn ! testDefaultTables -> Bool
  (do (assert (= (llr/featureNames) (list "sizedRt" "bitRt" "bufRt" "atomicRt" "rawRt" "viewRt")) "the hub holds one table per feature emitter, in design order")
      (assert (listEmpty? (llr/routedBuiltins (llr/features))) "every table starts empty, so no new builtin name is routed yet")
      (assert (not (llr/routes? (moduleOf (list) (list (callerOf "llFixtureId"))))) "a module calling an unlisted name is not routed by the default tables")
      (assert (= (llr/wrapperName "llFixtureId") "asl-target-llvm/lowLevelRoute.llFixtureId") "a routed name maps to a function under the hub's namespace")
      true)

fn ! testKindTable -> Bool
  (do (assert (= (llr/kindCode "U8") 1) "U8 has kind code 1 from numKinds")
      (assert (= (llr/kindCode "U64") 7) "U64 has kind code 7 from numKinds")
      (assert (= (llr/kindCode "I64") 0) "I64 has kind code 0 from numKinds")
      (assert (= (llr/kindWidth "U16") 16) "U16 is 16 bits wide")
      (assert (llr/kindSigned? "I32") "I32 is signed")
      (assert (not (llr/kindSigned? "U32")) "U32 is unsigned")
      true)

fn ! testRoutedDefinition -> Bool
  (let [(m (moduleOf (list) (list (callerOf "llFixtureId"))))]
    (match (llr/routeModuleWith (list (fixtureFeature)) m)
      ((err ds) (assert false (str "a listed name routes: " ds)))
      ((ok r)
        (do (assert (= r.internal (list (llr/wrapperName "llFixtureId"))) "the routed function is the one internal name")
            (assert (listAny? (fn [(f ty/SsaFunction)] -> Bool (= f.name (llr/wrapperName "llFixtureId"))) r.result.functions) "the module gains the feature's definition")
            (assert (= (llr/lowLevelCalls (list (fixtureFeature)) r.result) (list)) "no routed builtin call remains after rewriting")
            true))))

fn ! testUnroutedStaysAbsent -> Bool
  (match (facts)
    ((none) (assert false "a verified triple facts table exists on this host"))
    ((some fx)
      (let [(m (moduleOf (list) (list (callerOf "llNobodyRoutes"))))]
        (match (llvm/routeForWith (list (fixtureFeature)) fx m)
          ((err ds) (assert false (str "routing an unlisted name leaves the module as is: " ds)))
          ((ok r)
            (do (assert (listEmpty? r.internal) "no function is added for an unlisted name")
                (assert (= r.result m) "the module is untouched")
                (assert (err? (ssa/emitLlvmModule r.result)) "emitting the unlisted builtin stays an error")
                true))))))

fn ! testHubInMainRoute -> Bool
  (match (facts)
    ((none) (assert false "a verified triple facts table exists on this host"))
    ((some fx)
      (let [(m (moduleOf (list) (list (callerOf "llFixtureId"))))]
        (match (llvm/routeForWith (list (fixtureFeature)) fx m)
          ((err ds) (assert false (str "routeForWith routes a listed name: " ds)))
          ((ok r)
            (match (ssa/emitLlvmModule r.result)
              ((err ds) (assert false (str "the routed module emits: " ds)))
              ((ok text)
                (do (assert (stringContains? text "lowLevelRoute.llFixtureId") "the emitted text defines and calls the routed function")
                    (assert (stringContains? text "define") "the emitted text has definitions")
                    (assert (ok? (llvm/routeFor fx m)) "the default route leaves an unlisted-table module routable")
                    true))))))))

fn ! runTests -> Bool
  (do (testDefaultTables)
      (testKindTable)
      (testRoutedDefinition)
      (testUnroutedStaysAbsent)
      (testHubInMainRoute)
      true)
