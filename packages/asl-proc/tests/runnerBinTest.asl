(module asl-proc/tests/runnerBinTest :x [runTests] :i [(asl-proc/runnerBin :a rb)])

fn ! scratch tag: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/runnerBinTest-" tag "-" (stringFromInt64 (monotonicNs)))

fn ! setup! -> (Pair String String)
  (let [(root (scratch "root"))
        (cache (scratch "cache"))
        (dir (str cache "/binhead"))
        (_ (dirCreate root))
        (_ (dirCreate cache))
        (_ (dirCreate dir))
        (_ (dirCreate (str dir "/src")))
        (_ (fileWrite (str root "/dep.asl") "same bytes"))
        (_ (fileWrite (str dir "/src/dep.asl") "same bytes"))
        (_ (fileWrite (str dir "/bin") "#!/bin/sh\nexit 0\n"))
        (_ (fileWrite (str dir "/deps") "dep.asl\n"))
        (_ (fileWrite (rb/headPath cache root) dir))]
    (pair root cache))


fn ! runTests -> Bool
  (let [(s (setup!))
        (root (pairFirst s))
        (cache (pairSecond s))
        (dir (str cache "/binhead"))
        (fallback (str root "/asl/host/out/asl-host"))
        (freshResolved (rb/resolveFrom cache root fallback))
        (staleWrite (fileWrite (str root "/dep.asl") "changed bytes"))
        (staleResolved (rb/resolveFrom cache root fallback))
        (emptyCache (scratch "emptyCache"))
        (emptyResolved (rb/resolveFrom emptyCache root fallback))
        (_ (pathRemove root))
        (_ (pathRemove cache))]
    (do
      (assert (ok? staleWrite) "stale fixture write succeeds")
      (assert (= freshResolved (str dir "/bin")) "a cache whose deps match the tree resolves the native bin")
      (assert (= staleResolved fallback) "one changed source byte falls back to the built runner")
      (assert (= emptyResolved fallback) "no head file for this root falls back to the built runner")
      true))
