(module asl/examples/fileReadDemo
  :x [lineCount]
  :i [])

fn lineCount path: String -> (Result Int64 String)
  (match (fileReadString path)
    ((ok s) (ok (listLength (stringLines s))))
    ((err _) (err (stringConcat "cannot read " path))))
