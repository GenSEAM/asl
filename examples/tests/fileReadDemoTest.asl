(module asl/examples/tests/fileReadDemoTest
  :x [runTests]
  :i [(asl/examples/fileReadDemo :a fileReadDemo)])

fn runTests -> Bool
  (do
    (assert (match (fileReadDemo/lineCount "asl/examples/fileReadDemo.asl")
              ((ok n) (> n 0))
              ((err _) false))
            "lineCount ok on existing file")
    (assert (= (fileReadDemo/lineCount "asl/examples/absent.txt")
               (err "cannot read asl/examples/absent.txt"))
            "lineCount err on missing file")
    true)
