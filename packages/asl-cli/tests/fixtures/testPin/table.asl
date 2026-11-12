(module testPinFixture/table
  :x [dispatchByName]
  :i [(asl/packages/asl-cli/tests/fixtures/testPin/valueOnly :a vo) (asl/packages/asl-cli/tests/fixtures/testPin/lambdaOnly :a lo)])

; (:m :ref PERF-CLI-REBUILD :do "a string-keyed dispatch table: vo/viaValue is never called here, only stored as a value in a map, and lo/inLambda is only called inside a lambda kept in a list; both must be reached")
fn handlers -> (Map String (fn [Int64] -> Int64))
  (mapSet (mapEmpty) "double" vo/viaValue)

fn lambdas -> (List (fn [Int64] -> Int64))
  (list (fn [(x Int64)] -> Int64 (lo/inLambda x)))

fn dispatchByName name: String n: Int64 -> Int64
  (+ (match (mapGet (handlers) name) ((some f) (f n)) ((none) 0))
     (fold (fn [(acc Int64) (g (fn [Int64] -> Int64))] -> Int64 (+ acc (g n))) 0 (lambdas)))
