(module asl-checker/shadowBuiltinTest
  :x [runTests]
  :i [])

; (:m :ref MAC-FENCE-UNSUPPORTED :do "a module's own enum constructor or function shadows a low-level builtin of the same name: fence and bitCount are builtin names in lowLevelSigs.asl, here they are a constructor and a function, and the module checks and builds native")
enum Mark
  (fence start: Int64 end: Int64 content: String)
  (plain)

fn bitCount n: Int64 -> Int64
  (+ n 1)

fn mark -> Mark
  (fence 1 5 "body")

fn ! runTests -> Bool
  (do (assert (= (match (mark) ((fence a b c) (+ a b)) ((plain) 0)) 6) "the constructor fence builds and matches as the module's own")
      (assert (= (bitCount 41) 42) "a module function named bitCount is an ordinary call")
      true)
