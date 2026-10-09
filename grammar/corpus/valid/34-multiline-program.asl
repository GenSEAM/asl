"The same literal crossing a process boundary, which is the arm no function-mode"

"case reaches. A newline that arrived as two characters, or as a target's own"

"line ending, shows up here as a stdout mismatch between runners rather"

"than as a compile error."

"A top-level note spanning two lines, which the host evaluates at load and
 discards, and which therefore proves the erasure, not the escaping."

(module text/usageProgram :x [helpText main])

fn helpText -> String
  "usage: notes FILE
       notes --help"

fn ! main args: (List String) -> (Result Unit IoError)
  (do (println (helpText)) (ok ()))
