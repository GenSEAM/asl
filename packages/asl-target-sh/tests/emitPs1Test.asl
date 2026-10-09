(module asl-target-sh/tests/emitPs1Test
  :x [runTests]
  :i [(asl-target-sh/ast :a ast) (asl-target-sh/emitPs1 :a ps1)])

fn testEscapingAndMangle -> Bool
  (let [(s1 (ps1/escapePs1SingleQuotes "Don't stop"))
        (s2 (ps1/escapePs1DoubleQuotes "Value `$var` \"quoted\""))
        (ident (ps1/manglePs1Ident "my-var-name"))]
    (assert (= s1 "Don''t stop") "Single quote in PowerShell must be doubled")
    (assert (stringContains? s2 "`\"") "Double quotes must be backtick escaped")
    (assert (= ident "my_var_name") "Hyphens must be converted to underscores")
    true)

fn testPs1StatementsAndScript -> Bool
  (let [(assignStmt (ast/makeShAssign "install_dir" (ast/makeShLitStr "C:\\asl\\bin") false false))
        (assignCode (ps1/formatPs1Stmt assignStmt 1))
        (callStmt (ast/makeShCall "Write-Host" (list (ast/makeShLitStr "Installed")) (list)))
        (fnDef (ast/makeShFunction "Install-Asl" (list assignStmt callStmt)))
        (scriptCode (ps1/formatPs1Script (list "Windows Installation Script") (list fnDef) (list (ast/makeShCall "Install-Asl" (list) (list)))))]
    (assert (stringContains? assignCode "$install_dir = 'C:\\asl\\bin'") "PowerShell assignment must format correctly")
    (assert (stringContains? scriptCode "function Install_Asl {") "PowerShell function must use function keyword")
    (assert (stringContains? scriptCode "$ErrorActionPreference = \"Stop\"") "Script must enable strict error preference")
    (assert (stringContains? scriptCode "# Windows Installation Script") "Header comments must format with hash")
    (refute (stringContains? scriptCode "#!/bin/sh") "PowerShell script must not contain bash shebang")
    true)

fn runTests -> Bool
  (let [(t1 (testEscapingAndMangle))
        (t2 (testPs1StatementsAndScript))]
    (and t1 t2))
