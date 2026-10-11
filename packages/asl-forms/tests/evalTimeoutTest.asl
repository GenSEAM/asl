(module asl-forms/tests/evalTimeoutTest :x [runTests] :i [(asl-forms/evalOp :a ev)])

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (tmp (str root "/evalTimeoutTest-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (cache (str tmp "/cache"))
        (marker (str tmp "/slow-clang.marker"))
        (clang (str tmp "/clang"))
        (stub (str "#!/bin/sh\nif mkdir '" marker ".once' 2>/dev/null; then\n  sleep 7\n  printf 'invoked\\n' >> '" marker "'\nfi\nexec /usr/bin/clang \"$@\"\n"))
        (created (dirCreate tmp))]
    (mt created
      ((err _) false)
      ((ok _)
        (let [(cacheCreated (dirCreate cache))
              (stubWritten (fileWrite clang stub))]
          (mt cacheCreated
            ((err _) (do (pathRemove tmp) false))
            ((ok _) (mt stubWritten
              ((err _) (do (pathRemove tmp) false))
              ((ok _) (let [(chmod (fileChmod clang 493))]
                (mt chmod
                  ((err _) (do (pathRemove tmp) false))
                  ((ok _) (let [(warmed (ev/warmNativeSelf! root))
                                (kw (mapSet (mapSet (mapEmpty) "nativeTestCache" cache) "nativeTestClang" clang))
                                (result (ev/evalStep! root 1 kw (list "1")))
                                (markerText (resultOr (fileReadString marker) ""))
                                (removed (pathRemove tmp))]
                    (mt removed
                      ((err _) false)
                      ((ok _) (do
                        (assert (= (pairSecond warmed) 0)
                                (str "native self warms before the timed call: " (pairFirst warmed)))
                        (assert (and (= (pairSecond result) 0)
                                     (stringContains? (pairFirst result) ":value \"1\""))
                                (str "cold native eval succeeds within its evaluation timeout: "
                                     (pairFirst result) " :exit " (stringFromInt64 (pairSecond result))))
                        (assert (stringContains? markerText "invoked")
                                "the configured slow-build stub was invoked")
                        true)))))))))))))))
