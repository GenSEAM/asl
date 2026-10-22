(module asl-cli/tests/asl1CacheDepsTest
  :x [runTests]
  :i [(asl-cli/asl1Cache :a cache) (asl-cli/system :a sys)])

fn lines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringLines text)))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (compiler (str root "/asl/packages/asl-compiler/src/asl1.asl"))
        (lib (str root "/asl/host/out/libaslrt.a"))
        (noHost (sys/Context :root root :scriptDir (str root "/bin") :argv0 (str root "/bin/asl") :hostBin "/nonexistent/asl-host"))
        (native (cache/closure! noHost compiler lib "clang"))
        (nativeLines (lines (resultOr native "")))]
    (do (assert (ok? native) (str "the closure came from a native asl1 with no asl-host to fall back on: " (match native ((ok _) "") ((err e) e))))
        (assert (> (listLength nativeLines) 10) "the asl1 closure spans the compiler packages")
        (assert (listContains? nativeLines "asl/packages/asl-target-llvm/src/main.asl") "paths are root-relative")
        true))
