(module asl-ir/tests/lowerAllocTes
  :x [runTests main]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (tools/nativeTest :a nt)
      (tools/fleet/run :a fr)])

fn thisFile -> String
  "asl/packages/asl-ir/tests/lowerAllocTest.asl"

fn entryPath -> String
  "asl/packages/asl-json/tests/jsonTest.asl"

fn lowerUnit units: (List lk/LinkUnit) prelude: lk/LinkUnit acc: lk/LinkAcc u: lk/LinkUnit -> lk/LinkAcc
  (mt (low/lowerLinked u.forms u.positions (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude prelude.forms :strings acc.strings :only (none)))
    ((ok m) (lk/LinkAcc :strings m.strings :modules (cons m acc.modules) :requested acc.requested :diags acc.diags))
    ((err ds) (lk/LinkAcc :strings acc.strings :modules acc.modules :requested acc.requested :diags (listAppend acc.diags ds))))

fn ! writeModules dir: String modules: (List ty/SsaModule) -> Bool
  (listAll? (fn [(m ty/SsaModule)] -> Bool (mt (fileWrite (str dir "/" (stringReplace m.name "/" "_") ".ssa") (str m)) ((ok _) true) ((err _) false))) modules)

fn ! run mode: String entry: String dir: String -> (Result Int64 String)
  (mt (lk/loadClosure! entry)
    ((err ds) (err (str "closure of " entry " fails to load: " (listLength ds) " diag(s)")))
    ((ok units)
      (mt (lk/loadClosure! (lk/preludePath))
        ((err _) (err "prelude closure fails to load"))
        ((ok pUnits)
          (let [(prelude (optionOr (listHead pUnits) (lk/emptyUnit "prelude")))]
            (if (= mode "load")
              (ok (listLength units))
              (let [(lowered0 (fold (fn [(acc lk/LinkAcc) (u lk/LinkUnit)] -> lk/LinkAcc (lowerUnit units prelude acc u))
                                    (lk/LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))
                    (lowered (lk/LinkAcc :strings lowered0.strings :modules (listReverse lowered0.modules) :requested lowered0.requested :diags lowered0.diags))
                    (withPrelude (if (= mode "units") lowered (lk/lowerPrelude prelude lowered)))]
                (cond
                  ((not (listEmpty? withPrelude.diags))
                   (err (str (listLength withPrelude.diags) " lowering diag(s), first: " (optionOr (listHead (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus " " d.message)) withPrelude.diags)) ""))))
                  ((= mode "dump")
                   (if (writeModules dir withPrelude.modules) (ok (listLength withPrelude.modules)) (err (str "cannot write modules under " dir))))
                  (else (ok (listLength withPrelude.modules)))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listGet args 0) "units"))
        (entry (optionOr (listGet args 1) (entryPath)))
        (dir (optionOr (listGet args 2) "."))]
    (if (not (or (= mode "load") (= mode "units") (= mode "lower") (= mode "dump")))
      (err (str "unknown mode " mode "; expected load, units, lower or dump"))
      (mt (run mode entry dir)
        ((ok n) (do (println (str "lowerAlloc " mode " modules " n)) (ok 0)))
        ((err e) (err e)))))

fn statsLine text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringSplit text "\n"))) "")

fn bytesAllocated line: String -> Int64
  (let [(tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens ":bytesAllocated")
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! runMode mode: String -> Int64
  (let [(built (nt/prepareRun (thisFile) (nt/fingerprint)))]
    (mt built.binary
      ((none) (do (assert false (str "lowerAllocTest builds natively: " built.reason)) -1))
      ((some bin)
       (let [(done (fr/runOneLimited (fr/job (list bin mode (entryPath)) "." (fr/childEnv (list "ASL_GC_STATS=1"))) (fr/limits 300 4)))]
         (do (assert (= done.exit 0) (str mode " run exits 0 (" done.verdict "): " done.out))
             (assert (stringContains? done.out (str "lowerAlloc " mode " modules 2")) (str mode " run covers the 2 modules of the jsonTest closure: " done.out))
             (bytesAllocated (statsLine done.out)))))))

fn ! runTests -> Bool
  (let [(loadOnly (runMode "load"))
        (full (runMode "units"))
        (lowerBytes (- full loadOnly))]
    (do
      (println (str "lowerAlloc load " loadOnly " units " full " delta " lowerBytes))
      (assert (and (> loadOnly 0) (> full loadOnly)) "both runs report bytesAllocated and lowering allocates")
      (assert (< lowerBytes 134000000) (str "lowering the jsonTest closure allocates < 134 MB (0.6x base), got " lowerBytes))
      true))
