(module asl-cli/tests/asl1CacheDepsTest
  :x [runTests]
  :i [(asl-cli/asl1Cache :a cache) (asl-cli/system :a sys) (tools/fleet/run :a run)])

fn lines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringLines text)))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (compiler (str root "/asl/packages/asl-compiler/src/asl1.asl"))
        (lib (str root "/asl/host/out/libaslrt.a"))
        (noHost (sys/Context :root root :scriptDir (str root "/bin") :argv0 (str root "/bin/asl") :hostBin "/nonexistent/asl-host"))
        (native (cache/closure! noHost compiler lib "clang"))
        (hosted (run/runOneLimited (run/job (list (str root "/asl/host/out/asl-host") "run" compiler "deps" compiler) root (run/childEnv (list))) (run/limits 600 8)))]
    (do (assert (ok? native) (str "the closure came from a native asl1 with no asl-host to fall back on: " (mt native ((ok _) "") ((err e) e))))
        (assert (= hosted.exit 0) (str "asl-host printed the closure: " hosted.out))
        (assert (> (listLength (lines hosted.out)) 10) "the asl1 closure spans the compiler packages")
        (assert (= (lines (resultOr native "")) (lines hosted.out)) "the native closure lists the files asl-host lists, in its order")
        (assert (listContains? (lines (resultOr native "")) "asl/packages/asl-target-llvm/src/main.asl") "paths are root-relative, as asl-host prints them")
        true))
