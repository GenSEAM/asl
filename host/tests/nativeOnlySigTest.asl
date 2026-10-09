(module asl/host/tests/nativeOnlySigTest
  :x [runTests])

fn nativeRowsPresent rows: String route: String -> Bool
  (let [(row (optionOr (stringIndexOf rows "{\"") -1))]
    (if (= row -1) true
      (let [(tail (optionOr (stringSlice rows (+ row 2) (stringLength rows)) ""))
            (end (optionOr (stringIndexOf tail "\"") -1))]
        (if (= end -1) false
          (let [(name (optionOr (stringSlice tail 0 end) ""))
                (rest (optionOr (stringSlice tail (+ end 1) (stringLength tail)) ""))]
            (and (stringContains? route (str "\"" name "\"")) (nativeRowsPresent rest route)))))))

fn nativeTableMatchesRoute source: String route: String -> Bool
  (let [(start (optionOr (stringIndexOf source "nativeOnlySigs[] = {") -1))]
    (if (= start -1) false
      (let [(tail (optionOr (stringSlice source (+ start (stringLength "nativeOnlySigs[] = {")) (stringLength source)) ""))
            (end (optionOr (stringIndexOf tail "};") -1))]
        (if (= end -1) false
          (nativeRowsPresent (optionOr (stringSlice tail 0 end) "") route)))))

fn ! runTests -> Bool
  (let [(handoff (processRun "asl/host/out/asl-host check asl/packages/asl-net/src/handoff.asl"))
        (fixture (processRun "asl/host/out/asl-host check asl/packages/asl-web/tests/fixtures/handoffProgram.asl"))
        (route (resultOr (fileRead "asl/packages/asl-target-llvm/src/sysRoute.asl") ""))
        (types (resultOr (fileRead "asl/host/src/types.c") ""))
        (made (processRun "mktemp"))
        (path (stringReplace made.stdout "\n" ""))
        (source (fileWrite path "(module nativeOnlyProbe :x [])\n(unixSocketPair)\n"))
        (run (processRun (str "asl/host/out/asl-host run " path)))
        (valueMade (processRun "mktemp"))
        (valuePath (stringReplace valueMade.stdout "\n" ""))
        (valueSource (fileWrite valuePath "(module nativeOnlyValueProbe :x [])\n(let [(f unixSocketPair)] (f))\n"))
        (valueRun (processRun (str "asl/host/out/asl-host run " valuePath)))
        (typeMade (processRun "mktemp"))
        (typePath (stringReplace typeMade.stdout "\n" ""))
        (typeSource (fileWrite typePath "(module nativeOnlyTypeProbe :x [])\n(sockSendFd \"bad\" 2)\n"))
        (typeCheck (processRun (str "asl/host/out/asl-host check " typePath)))
        (effectMade (processRun "mktemp"))
        (effectPath (stringReplace effectMade.stdout "\n" ""))
        (effectSource (fileWrite effectPath "(module nativeOnlyEffectProbe :x [])\nfn pureProbe a: Int64 -> (Result Int64 String)\n  (sockRecvFd a)\n"))
        (effectCheck (processRun (str "asl/host/out/asl-host check " effectPath)))
        (clean (processRun (str "rm -f " path " " valuePath " " typePath " " effectPath)))]
    (do
      (assert (= handoff.exitCode 0) (str "host checks handoff.asl: " handoff.stderr))
      (assert (= fixture.exitCode 0) (str "host checks handoffProgram.asl: " fixture.stderr))
      (assert (nativeTableMatchesRoute types route) "every native-only signature table name is present in sysRoute")
      (assert (ok? typeSource) "writes type-check probe")
      (assert (not (= typeCheck.exitCode 0)) (str "type mismatch is rejected without unknown symbol: " typeCheck.stderr))
      (assert (stringContains? typeCheck.stderr "ERR_TYPE_MISMATCH") (str "native parameter type is checked: " typeCheck.stderr))
      (assert (ok? effectSource) "writes effect-check probe")
      (assert (not (= effectCheck.exitCode 0)) (str "effect violation is rejected without unknown symbol: " effectCheck.stderr))
      (assert (stringContains? effectCheck.stderr "ERR_EFFECT_UNMARKED") (str "native effect is checked: " effectCheck.stderr))
      (assert (ok? source) "writes VM native-only call probe")
      (assert (ok? valueSource) "writes VM native-only value probe")
      (assert (not (= valueRun.exitCode 0)) "VM rejects native-only builtin used as a value")
      (assert (stringContains? valueRun.stderr "ERR_CAPABILITY_ABSENT") (str "value call reaches native-only capability guard: " valueRun.stderr))
      (assert (stringContains? valueRun.stderr "unixSocketPair") (str "value call names native-only builtin: " valueRun.stderr))
      (assert (not (= run.exitCode 0)) "VM rejects native-only call")
      (assert (stringContains? run.stderr "ERR_CAPABILITY_ABSENT") (str "VM reports absent capability: " run.stderr))
      (assert (stringContains? run.stderr "unixSocketPair") (str "VM names native-only builtin: " run.stderr))
      (assert (stringContains? run.stderr "asl-target-llvm/sysRoute") (str "VM names native route: " run.stderr))
      (assert (= clean.exitCode 0) "removes temporary probe files")
      true))
