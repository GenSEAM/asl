(module asl-target-llvm/tests/eqAliasNativeTest
  :x [runTests]
  :i [(asl-ir/lower :a low)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)
      (tools/fleet/run :a run)])

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! shWithin cmd: String timeoutS: Int64 -> Captured
  (let [(root (optionOr (envGet "ASL_ROOT") "."))
        (prelude (optionOr (envGet "ASL_PRELUDE") (str root "/asl/prelude/prelude.asl")))
        (path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (base (str (optionOr (envGet "TMPDIR") "/tmp") "/eqAliasNativeTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(cd " (shellQuote root) " && (" cmd ")) > " (shellQuote outPath) " 2> " (shellQuote errPath))) root
                                         (run/childEnv (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" prelude) (str "PATH=" path))))
                                 (run/limits timeoutS 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn ! sh cmd: String -> Captured
  (shWithin cmd 1200)

fn source -> String
  (stringJoin (list
    "(module eqAlias :x [main])"
    "(schema Pt (:f x Int64) (:f y Int64))"
    "fn ! main -> Int64"
    "  (let [(a (== 7 7)) (b (== 7 8)) (c (== 1.5 1.5)) (d (== \"hi\" \"hi\")) (e (== (Pt :x 1 :y 2) (Pt :x 1 :y 2))) (g (== (list 1 2 3) (list 1 2 3)))]"
    "    (do (println (str a \" \" b \" \" c \" \" d \" \" e \" \" g)) 0))") "\n")

fn diagText diags: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) diags) "; ")

fn ! testEqAliasAcrossTypes -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/eqAliasNativeTest." (monotonicNs)))
        (made (dirCreate dir))
        (src (str dir "/eqAlias.asl"))
        (ll (str dir "/eqAlias.ll"))
        (exe (str dir "/eqAlias"))]
    (do
      (assert (ok? made) "eqAlias temporary fixture directory created")
      (assert (ok? (fileWrite src (source))) "eqAlias fixture source written")
      (mt (low/lowerSource (source))
        ((err diags) (do (assert (listEmpty? diags) (str "eqAlias fixture lowers: " (diagText diags))) false))
        ((ok m)
         (mt (llvm/emitLlvmProgramNative! m "main")
           ((err diags) (do (assert (listEmpty? diags) (str "eqAlias fixture emits: " (diagText diags))) false))
           ((ok code)
            (do
              (assert (ok? (fileWrite ll code)) "eqAlias LLVM fixture written")
              (let [(linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " (shellQuote ll) " -x none asl/host/out/libaslrt.a -lm -o " (shellQuote exe))))]
                (assert (= linked.exitCode 0) (str "eqAlias fixture linked: " linked.stderr)))
              (let [(native (sh (shellQuote exe)))
                    (interp (sh (str (shellQuote (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host")) " run " (shellQuote src))))]
                (do
                  (assert (= native.exitCode 0) (str "eqAlias native fixture exits 0: " native.stderr))
                  (assert (= interp.exitCode 0) (str "eqAlias interpreter fixture exits 0: " interp.stderr))
                  (assert (= native.exitCode interp.exitCode) "eqAlias native and interpreter exit statuses agree")
                  (assert (= native.stdout interp.stdout) (str "eqAlias native output " native.stdout " matches interpreter " interp.stdout))
                  (assert (= native.stdout "true false true true true true\n") (str "== on Int64, Float64, String, a record and a list all compute correctly natively: " native.stdout))
                  true)))))))
      (assert (ok? (pathRemove dir)) "eqAlias temporary fixture directory removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testEqAliasAcrossTypes) "== lowers natively on Int64, Float64, String, a record and a list, matching the interpreter")
    true)
