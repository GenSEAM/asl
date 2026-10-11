(module asl-target-llvm/tests/emitRefsTimingTest
  :x [runTests main]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-target-llvm :a nat)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a route)])

fn entryPath -> String
  "asl/packages/asl-target-llvm/tests/fixtures/emitRefs/sourceEntry.asl"

fn facts -> (Option libc/TripleFacts)
  (mt (route/hostFactsOf "Darwin arm64")
    ((ok o) o)
    ((err _) (none)))

fn lowerUnit units: (List lk/LinkUnit) prelude: lk/LinkUnit acc: lk/LinkAcc u: lk/LinkUnit -> lk/LinkAcc
  (mt (low/lowerLinked u.forms u.positions (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude prelude.forms :strings acc.strings :only (none)))
    ((ok m) (lk/LinkAcc :strings m.strings :modules (listAppend acc.modules (list m)) :requested acc.requested :diags acc.diags))
    ((err ds) (lk/LinkAcc :strings acc.strings :modules acc.modules :requested acc.requested :diags (listAppend acc.diags ds))))

fn ! emitMicros -> (List (Pair String Int64))
  (mt (lk/loadClosure! (entryPath))
    ((err _) (list (pair "closure" -1)))
    ((ok units)
      (mt (lk/loadClosure! (lk/preludePath))
        ((err _) (list (pair "prelude" -1)))
        ((ok pUnits)
          (mt (facts)
            ((none) (list (pair "facts" -1)))
            ((some f)
              (let [(prelude (optionOr (listHead pUnits) (lk/emptyUnit "prelude")))
                    (lowered (fold (fn [(acc lk/LinkAcc) (u lk/LinkUnit)] -> lk/LinkAcc (lowerUnit units prelude acc u))
                                   (lk/LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))]
                (if (not (listEmpty? lowered.diags))
                  (list (pair "lower" -1))
                  (map (fn [(m irTy/SsaModule)] -> (Pair String Int64)
                         (pair m.name (fold (fn [(best Int64) (i Int64)] -> Int64
                                              (let [(t0 (monotonicNs))
                                                    (res (if (= m.name "emitRefsSourceEntry") (nat/emitLlvmProgramFor f m (str m.name ".main")) (nat/emitLlvmModuleFor f m)))
                                                    (t1 (monotonicNs))]
                                                (cond
                                                  ((err? res) -1)
                                                  ((< best 0) best)
                                                  (else (min best (/ (- t1 t0) 1000))))))
                                            9223372036854775807 (range 0 3))))
                       lowered.modules)))))))))

fn microsOf rows: (List (Pair String Int64)) name: String -> Int64
  (optionOr (listHead (map (fn [(r (Pair String Int64))] -> Int64 (pairSecond r)) (filter (fn [(r (Pair String Int64))] -> Bool (= (pairFirst r) name)) rows))) -1)

fn ! runningNatively? -> Bool
  (mt (procExePath)
    ((ok p) (not (stringEndsWith? p "/asl-host")))
    ((err _) false))

fn ! main args: (List String) -> (Result Int64 String)
  (do
    (map (fn [(r (Pair String Int64))] -> () (println (str "emitRefsTiming " (pairFirst r) " us " (pairSecond r)))) (emitMicros))
    (ok 0))

fn ! runTests -> Bool
  (let [(rows (emitMicros))
        (wrapper (microsOf rows "emitRefsSourceEntry"))
        (source (microsOf rows "asl-syntax/core/source"))
        (native (runningNatively?))
        (wrapperLimit (if native 15000 40000))
        (sourceLimit (if native 250000 650000))]
    (do
      (println (str "emitRefsTiming wrapper us " wrapper " source us " source " mode " (if native "native" "host")))
      (assert (> wrapper 0) "the entry wrapper emits")
      (assert (> source 0) "asl-syntax/core/source emits")
      (assert (< wrapper wrapperLimit)
              (if native "entry wrapper emit < 15 ms (native; ~6 ms measured 2026-10-10 at head, ~35 ms with U3-REFS-SET reverted)"
                "entry wrapper emit < 40 ms (host; ~26.5 ms measured 2026-10-10 at head, ~53.4 ms with U3-REFS-SET reverted)"))
      (assert (< source sourceLimit)
              (if native "asl-syntax/core/source emit < 250 ms (native; ~91 ms measured 2026-10-10 at head, ~438 ms with U3-REFS-SET reverted)"
                "asl-syntax/core/source emit < 650 ms (host; ~357 ms measured 2026-10-10 at head, ~865 ms with U3-REFS-SET reverted)"))
      true))
