(module asl/host/tests/buildExitTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

fn clangShim -> String
  (str "#!/bin/sh\ncase \"$*\" in *nativeBuild.ll*) echo shimmed native build failure >&2; exit 1;; esac\nexec " (optionOr (envGet "CLANG") "clang") " \"$@\"\n")

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 60 8))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/buildExit/" (stringFromInt64 (procSelf))))
        (fresh (sh! root (list "/bin/rm" "-rf" work)))
        (made (dirCreate work))
        (shim (str work "/clang"))
        (wrote (fileWrite shim (clangShim)))
        (mode (sh! root (list "/bin/chmod" "755" shim)))
        (env (listAppend (list (str "ASL_HOST_OUT=" work "/out") (str "ASL_HOST_CACHE_DIR=" work "/hosts") (str "ASL_NATIVE_RT=" root "/asl/host/out/libaslrt.a") (str "CLANG=" shim))
               (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST_") (or (stringStartsWith? row "ASL_NATIVE_") (stringStartsWith? row "CLANG="))))) (run/childEnv (list)))))
        (built (run/runOneLimited (run/job (list "/bin/sh" (str root "/asl/host/build.sh")) root env) (run/limits 1200 64)))
        (cleaned (sh! root (list "/bin/rm" "-rf" work)))]
    (do (assert (ok? made) "the work dir was created")
        (assert (stringContains? built.out "shimmed native build failure") (str "the injected native CLI failure ran: " built.out))
        (assert (stringContains? built.out "no native CLI") "the log names the native CLI failure")
        (refute (= built.exit 0) "build.sh exits non-zero when its native CLI build failed")
        (assert (= cleaned.exit 0) "the work dir was removed")
        true))
