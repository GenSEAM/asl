(module asl-target-sh/tests/emitShTest
  :x [runTests]
  :i [(asl-target-sh/ast :a ast) (asl-target-sh/emitSh :a em)])

fn testSingleQuoteEscapingAndInjectionDefense -> Bool
  (let [(s1 (em/formatShExpr (ast/makeShLitStr "it's safe")))
        (s2 (em/formatShExpr (ast/makeShLitStr "$(rm -rf /)")))
        (s3 (em/formatShExpr (ast/makeShLitStr "`cat /etc/passwd`")))
        (s4 (em/formatShExpr (ast/makeShLitStr "foo * bar ? [baz]")))
        (v1 (em/formatShExpr (ast/makeShVar "user_input")))
        (vReserved (em/formatShExpr (ast/makeShVar "echo")))]
    (assert (= s1 "'it'\\''s safe'") "Single quote inside string must be safely escaped")
    (assert (= s2 "'$(rm -rf /)'") "Command substitution payload must be quarantined in single quotes")
    (assert (= s3 "'`cat /etc/passwd`'") "Backticks payload must be quarantined in single quotes")
    (assert (= s4 "'foo * bar ? [baz]'") "Globbing characters must be quarantined in single quotes")
    (assert (= v1 "\"${user_input:-}\"") "Variable reference must be double-quoted with defensive default")
    (assert (= vReserved "\"${sh_echo:-}\"") "Reserved shell keyword 'echo' must be mangled to 'sh_echo'")
    (refute (stringContains? s2 "\"") "Quarantined command substitution must not use double quotes")
    true)

fn testStatementAndScriptEmission -> Bool
  (let [(assignStmt (ast/makeShAssign "dir" (ast/makeShLitStr "/tmp") true false))
        (assignCode (em/formatShStmt assignStmt 1))
        (testNode (ast/makeShTestExpr "-d" (ast/makeShVar "dir") (ast/makeShLitStr "")))
        (callStmt (ast/makeShCall "printf" (list (ast/makeShLitStr "OK\\n")) (list)))
        (ifStmt (ast/makeShIf testNode (list callStmt) (list)))
        (ifCode (em/formatShStmt ifStmt 1))
        (fnDef (ast/makeShFunction "check_dir" (list assignStmt ifStmt)))
        (script (ast/makeShScript "#!/bin/sh" (list "Test Script") (list fnDef) (list (ast/makeShCall "check_dir" (list) (list)))))
        (scriptCode (em/formatShScript script))]
    (assert (stringContains? assignCode "local dir='/tmp'") "Assignment must format with local and single quotes")
    (assert (stringContains? ifCode "if [ -d \"${dir:-}\" ]; then") "If statement must format standard test bracket")
    (assert (stringContains? ifCode "fi\n") "If statement must close with fi")
    (assert (stringStartsWith? scriptCode "#!/bin/sh\n") "Script must start with shebang")
    (assert (stringContains? scriptCode "set -eu\n") "Script must enable set -eu for fail-fast execution")
    (assert (stringContains? scriptCode "check_dir() {\n") "Script must define function check_dir")
    true)

fn runTests -> Bool
  (let [(t1 (testSingleQuoteEscapingAndInjectionDefense))
        (t2 (testStatementAndScriptEmission))]
    (and t1 t2))
