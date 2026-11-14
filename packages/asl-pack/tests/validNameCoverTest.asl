(module asl-pack/tests/validNameCoverTest
  :x [runTests]
  :i [(pkgIndex :a pk)])

fn ! runTests -> Bool
  (do
    (assert (pk/validName? "asl-json") "a lowercase dashed name is valid")
    (assert (not (pk/validName? "")) "the empty name is refused")
    (assert (not (pk/validName? "-x")) "a leading dash is refused")
    (assert (not (pk/validName? "Asl")) "uppercase is refused")
    true)
