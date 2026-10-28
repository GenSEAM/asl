(module asl/host/tests/buildExitTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

; (:m :ref HOSTBUILD-EXIT-MASK :do "the real build.sh runs in a scratch tree that holds only it, a prelude and an asl-cli/nativeBuild.asl stub; the asl1 and clang it calls are scripts the existing ASL_NATIVE_ASL1 and CLANG hooks name, so no host, seed or native CLI starts, and the aslNativeBuild the fake clang links exits with the code the case picks")
fn fakeAsl1 depsExit: Int64 -> String
  (str "#!/bin/sh\n"
       "case \"$1\" in\n"
       "  deps) [ " depsExit " = 0 ] || exit " depsExit "; echo asl/packages/asl-cli/src/nativeBuild.asl ;;\n"
       "  build) while [ $# -gt 0 ]; do [ \"$1\" = -o ] && echo '; fake ir' > \"$2\"; shift; done ;;\n"
       "esac\n"
       "exit 0\n")

fn fakeClang cliExit: Int64 -> String
  (str "#!/bin/sh\n"
       "[ \"$1\" = --version ] && { echo 'fake clang 1'; exit 0; }\n"
       "out=''; while [ $# -gt 0 ]; do [ \"$1\" = -o ] && out=$2; shift; done\n"
       "printf '#!/bin/sh\\nexit " cliExit "\\n' > \"$out\" && chmod +x \"$out\"\n")

fn ! sh! cwd: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv (list))) (run/limits 60 8))

fn ! write! dir: String name: String text: String -> Bool
  (and (ok? (dirCreate dir)) (ok? (fileWrite (str dir "/" name) text)))

fn ! scratchTree! root: String tree: String depsExit: Int64 cliExit: Int64 -> Bool
  (let [(script (resultOr (fileReadString (str root "/asl/host/build.sh")) ""))]
    (and (not (stringEmpty? script))
         (and (write! (str tree "/asl/host") "build.sh" script)
              (and (write! (str tree "/asl/prelude") "prelude.asl" "; scratch prelude\n")
                   (and (write! (str tree "/asl/prelude/native") "stub.asl" "; scratch native\n")
                        (and (write! (str tree "/asl/packages/asl-cli/src") "nativeBuild.asl" "; scratch nativeBuild\n")
                             (and (write! (str tree "/fake") "asl1" (fakeAsl1 depsExit))
                                  (and (write! (str tree "/fake") "clang" (fakeClang cliExit))
                                       (= (sh! tree (list "/bin/chmod" "+x" "fake/asl1" "fake/clang")).exit 0)))))))))

fn hostRow? row: String -> Bool
  (or (stringStartsWith? row "ASL_HOST_") (or (stringStartsWith? row "ASL_NATIVE_") (stringStartsWith? row "CLANG=")))

fn ! build! tree: String -> run/Done
  (let [(env (listAppend (list (str "ASL_HOST_CACHE_DIR=" tree "/hosts") (str "ASL_NATIVE_ASL1=" tree "/fake/asl1") (str "CLANG=" tree "/fake/clang"))
                         (filter (fn [(row String)] -> Bool (not (hostRow? row))) (run/childEnv (list)))))]
    (run/runOneLimited (run/job (list "/bin/sh" (str tree "/asl/host/build.sh")) tree env) (run/limits 60 8)))

fn ! case! root: String work: String name: String depsExit: Int64 cliExit: Int64 -> run/Done
  (let [(tree (str work "/" name))]
    (if (scratchTree! root tree depsExit cliExit) (build! tree)
      (run/Done :idx 0 :exit 127 :out "scratch tree not made" :ms 0 :verdict "setup")))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/buildExit/" (stringFromInt64 (procSelf))))
        (_ (sh! root (list "/bin/rm" "-rf" work)))
        (pass (case! root work "pass" 0 0))
        (cliFails (case! root work "cliFails" 0 1))
        (depsFail (case! root work "depsFail" 1 0))
        (cleaned (sh! root (list "/bin/rm" "-rf" work)))]
    (do (assert (= pass.exit 0) (str "a build whose every step succeeds exits 0: " pass.exit " " pass.out))
        (refute (stringContains? pass.out "failed step") (str "and names no failed step: " pass.out))
        (assert (stringContains? pass.out "no libaslrt.a") (str "the scratch tree took the no-runtime path, so only the CLI steps ran: " pass.out))
        (assert (= cliFails.exit 1) (str "a failing native CLI build makes build.sh exit 1: " cliFails.exit " " cliFails.verdict " " cliFails.out))
        (assert (stringContains? cliFails.out "build.sh: the native CLI build failed") (str "the CLI build failure is said: " cliFails.out))
        (assert (stringContains? cliFails.out "build.sh: failed step: native CLI") (str "the failing step is named: " cliFails.out))
        (assert (= depsFail.exit 1) (str "a failing asl1 deps step makes build.sh exit 1: " depsFail.exit " " depsFail.out))
        (assert (stringContains? depsFail.out "asl1 deps of asl-cli/nativeBuild failed") (str "the deps failure is said: " depsFail.out))
        (assert (= cleaned.exit 0) "the work dir was removed")
        true))
