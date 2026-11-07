(module asl-forms/tests/searchKeysFileTest
  :x [runTests]
  :i [(asl-forms/delegate :a d)])

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/searchKeysFileTest-" (stringFromInt64 (procSelf))))
        (mk (dirCreate dir))
        (keys (str dir "/keys.env"))
        (w (fileWrite keys "export SERPER_API_KEY=fromFile\nTAVILY_API_KEY=\n"))
        (filled (d/withSearchKeys! (mapEmpty) (list keys)))
        (kept (d/withSearchKeys! (mapSet (mapEmpty) "SERPER_API_KEY" "fromEnv") (list keys)))
        (missing (d/withSearchKeys! (mapEmpty) (list (str dir "/absent.env"))))
        (gone (and (ok? (pathRemove keys)) (ok? (pathRemove dir))))]
    (do
      (assert (and (ok? mk) (ok? w)) "fixture: a key file under the test's own TMPDIR dir")
      (assert (= (mapGet filled "SERPER_API_KEY") (some "fromFile")) "a search key absent from the env is read from the key file")
      (assert (= (mapGet filled "TAVILY_API_KEY") (none)) "an empty value in the key file does not set the key")
      (assert (= (mapGet kept "SERPER_API_KEY") (some "fromEnv")) "a key already in the env wins over the key file")
      (assert (= (mapGet missing "SERPER_API_KEY") (none)) "a missing key file leaves the env unchanged")
      (assert gone "fixture removed")
      true))
