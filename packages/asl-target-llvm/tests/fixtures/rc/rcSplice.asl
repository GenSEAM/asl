(module rcSplice
  :x [main]
  :i [(asl-target-llvm/rc :a rc)])

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (rc/gcConsCall))
      (println (rc/arenaCallText))
      (println (rc/appendCallText))
      (println (str (listLength (listAppend (list "a") (list "b" "c")))))
      (ok 0))
