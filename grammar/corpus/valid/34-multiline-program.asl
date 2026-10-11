(module text/usageProgram :x [helpText main])

fn helpText -> String
  "usage: notes FILE
       notes --help"

fn ! main args: (List String) -> (Result Unit IoError)
  (do (println (helpText)) (ok ()))
