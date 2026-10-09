(module asl-target-llvm/tests/fixtures/nativeData/eqAlias
  :x [main isSignalValid]
  :i [])

fn isSignalValid signal: Int64 floor: Int64 -> Bool
  (and (== (mod signal 2) 0) (not (== signal floor)))

fn ! main args: (List String) -> (Result Unit String)
  (do
    (println (str "eq " (isSignalValid 4 0) " " (isSignalValid 3 0) " " (isSignalValid 0 0) " " (== "a" "a") " " (== (list 1 2) (list 1 2)) " " (stringJoin args ",")))
    (ok ()))
