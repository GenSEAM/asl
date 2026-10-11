(module asl-target-llvm/tests/emitAllocTest
  :x [runTests main]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-target-llvm :a nat)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a route)])

fn entryPath -> String
  "asl/packages/asl-target-llvm/tests/fixtures/emitAlloc/entry.asl"

fn facts -> (Option libc/TripleFacts)
  (mt (route/hostFactsOf "Darwin arm64")
    ((ok o) o)
    ((err _) (none)))

fn lowerUnit units: (List lk/LinkUnit) prelude: lk/LinkUnit acc: lk/LinkAcc u: lk/LinkUnit -> lk/LinkAcc
  (mt (low/lowerLinked u.forms u.positions (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude prelude.forms :strings acc.strings :only (none)))
    ((ok m) (lk/LinkAcc :strings m.strings :modules (listAppend acc.modules (list m)) :requested acc.requested :diags acc.diags))
    ((err ds) (lk/LinkAcc :strings acc.strings :modules acc.modules :requested acc.requested :diags (listAppend acc.diags ds))))

fn emitted res: (Result String (List irTy/IrDiag)) -> Int64
  (mt res ((ok text) (stringLength text)) ((err _) -1))

fn ! emittedBytes emit: Bool -> Int64
  (mt (lk/loadClosure! (entryPath))
    ((err _) -1)
    ((ok units)
      (mt (lk/loadClosure! (lk/preludePath))
        ((err _) -1)
        ((ok pUnits)
          (mt (facts)
            ((none) -1)
            ((some f)
              (let [(prelude (optionOr (listHead pUnits) (lk/emptyUnit "prelude")))
                    (entryName (optionOr (listHead (map (fn [(u lk/LinkUnit)] -> String u.name) (filter (fn [(u lk/LinkUnit)] -> Bool (= u.path (entryPath))) units))) ""))
                    (lowered (fold (fn [(acc lk/LinkAcc) (u lk/LinkUnit)] -> lk/LinkAcc (lowerUnit units prelude acc u))
                                   (lk/LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))
                    (withPrelude (lk/lowerPrelude prelude lowered))
                    (preludeMods (filter (fn [(m irTy/SsaModule)] -> Bool (= m.name prelude.name)) withPrelude.modules))
                    (preludeMod (irTy/ssaModule "prelude" withPrelude.strings (lk/firstByName (fold (fn [(a (List irTy/SsaTypeDecl)) (m irTy/SsaModule)] -> (List irTy/SsaTypeDecl) (listAppend a m.types)) (list) preludeMods))
                                                (lk/firstRecordByName (fold (fn [(a (List irTy/SsaRecordDecl)) (m irTy/SsaModule)] -> (List irTy/SsaRecordDecl) (listAppend a m.records)) (list) preludeMods))
                                                (list) (list) (lk/allFunctions preludeMods)))
                    (sizes (cons (if emit (emitted (nat/emitLlvmModuleFor f preludeMod)) 0)
                                 (map (fn [(m irTy/SsaModule)] -> Int64
                                        (cond
                                          ((not emit) 0)
                                          ((= m.name entryName) (emitted (nat/emitLlvmProgramFor f m (str m.name ".main"))))
                                          (else (emitted (nat/emitLlvmModuleFor f m)))))
                                      lowered.modules)))]
                (cond
                  ((not (listEmpty? withPrelude.diags)) -1)
                  ((listAny? (fn [(n Int64)] -> Bool (< n 0)) sizes) -1)
                  (else (fold (fn [(a Int64) (n Int64)] -> Int64 (+ a n)) 0 sizes))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(n (emittedBytes (!= (listHead args) (some "lower"))))]
    (if (< n 0) (err "corpus lowering or emission failed") (do (println (str "emitted " n)) (ok 0))))

fn statsLine text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringSplit text "\n"))) "")

fn bytesAllocated line: String -> Int64
  (let [(tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens ":bytesAllocated")
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! runMode mode: String -> Int64
  (let [(out (processRun (str "ASL_GC_STATS=1 asl/host/out/asl-host run asl/packages/asl-target-llvm/tests/emitAllocTest.asl " mode " 2>&1")))]
    (do (assert (= out.exitCode 0) (str mode " run exits 0: " out.stdout))
        (bytesAllocated (statsLine out.stdout))))

fn ! runTests -> Bool
  (let [(lowerOnly (runMode "lower"))
        (full (runMode "emit"))
        (emitBytes (- full lowerOnly))]
    (do
      (println (str "emitAlloc lower " lowerOnly " emit " full " delta " emitBytes))
      (assert (and (> lowerOnly 0) (> full lowerOnly)) "both runs report bytesAllocated and emission allocates")
      (assert (< emitBytes 253400000) (str "jsonTest corpus emit allocates < 253.4 MB, got " emitBytes))
      true))
