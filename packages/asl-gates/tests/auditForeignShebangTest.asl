(module asl-gates/tests/auditForeignShebangTest
  :x [runTests]
  :i [(asl-gates/auditForeign :a af)])

fn langOf head: String name: String -> String
  (af/langFromHead (stringToBytes head) name)

fn ! runTests -> Bool
  (do
    (assert (= (langOf "#!/usr/bin/env asl\nfn main -> Int64\n  0\n" "greet.asl") "") "an asl script with #!/usr/bin/env asl is not foreign")
    (assert (= (langOf "#!/usr/local/bin/asl\n(module m)\n" "tool") "") "an extensionless asl script with a direct #! asl path is not foreign")
    (assert (= (langOf "#!/usr/bin/env asl\nprint('x')\n" "trick.py") "python") "a #! asl line does not hide a foreign extension")
    (assert (= (langOf "#!/usr/bin/env python3\nprint(1)\n" "gen.asl") "python") "a python interpreter line is foreign even in a .asl file")
    (assert (= (langOf "#!/bin/bash\necho\n" "run") "shell") "a bash interpreter line is shell")
    (assert (= (langOf "#!/usr/bin/env aslx\n" "x.asl") "shebang.aslx") "an unknown interpreter stays foreign")
    true)
