(module asl-coord/tests/claimsSymbolTest
  :x [runTests]
  :i [(asl-coord/claims :a cl)])

; (:m :ref OWNS-SYMBOL-CLAIMS :do "a lease owns entry f.asl#sym is the file f.asl for the path checks: pathUnderOwns? lets the writer edit f.asl, pathsOverlap? sees f.asl against f.asl#B and keeps unrelated files apart")
fn ! runTests -> Bool
  (do (assert (cl/pathsOverlap? "f.asl" "f.asl#B") "a whole-file claim overlaps a symbol claim of that file")
      (assert (cl/pathsOverlap? "f.asl#A" "f.asl") "and the other way")
      (assert (not (cl/pathsOverlap? "f.asl#A" "g.asl")) "another file does not overlap")
      (assert (cl/pathsOverlap? "dir/f.asl#A" "dir") "a directory claim overlaps a symbol of a file below it")
      (assert (cl/pathWithin? "f.asl" "f.asl#sym") "a file is within its own symbol entry")
      (assert (not (cl/pathWithin? "g.asl" "f.asl#sym")) "another file is not")
      (assert (cl/pathWithin? "d/f.asl" "d") "directory entries are unchanged")
      true)
