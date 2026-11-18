(module asl-know/tests/returnTypeCoverTest
  :x [runTests]
  :i [(asl-know/scan :a ks)])

fn ! runTests -> Bool
  (do
    (assert (= (ks/returnType "f x: Int64 -> String") "String") "the text after the first arrow is returned")
    (assert (= (ks/returnType "f x: Int64 ->  String ") "String") "the returned type is trimmed")
    (assert (= (ks/returnType "f") "") "a signature without an arrow returns the empty string")
    true)
