(module aslHarness/tests/normalizerTest :x [testNormalizeIdentifier testCanonicalizeKeywords testCanonicalizeTypes testBalanceDelimiters testRepairHallucinations runTests] :i [(normalizer :a norm) (asl-parser/balance :a bal)])

fn testNormalizeIdentifier -> Bool
  (let [(case1 (norm/normalizeIdentifier "read_file_content")) (case2 (norm/normalizeIdentifier "execute command")) (case3 (norm/normalizeIdentifier "get-ast-node")) (nr (norm/NormalizerReport :clean true :issues 0))] (assert (= case1 "read-file-content") "snake_case must convert to kebab-case") (assert (= case2 "execute-command") "spaces must convert to kebab-case") (assert (= case3 "get-ast-node") "kebab-case must remain unchanged") (assert nr.clean "NormalizerReport is clean") (refute (not nr.clean) "Refute not clean NormalizerReport") true)

fn testCanonicalizeKeywords -> Bool
  (let [(kwDef (norm/canonicalizeKeyword "def")) (kwDefun (norm/canonicalizeKeyword "defun")) (kwDefn (norm/canonicalizeKeyword "defn")) (kwFn (norm/canonicalizeKeyword "fn*")) (kwStruct (norm/canonicalizeKeyword "struct")) (kwEnum (norm/canonicalizeKeyword "defenum")) (kwMatch (norm/canonicalizeKeyword "match")) (kwCond (norm/canonicalizeKeyword "cond*"))] (assert (= kwDef "fn") "def -> fn") (assert (= kwDefun "fn") "defun -> fn") (assert (= kwDefn "fn") "defn -> fn") (assert (= kwFn "fn") "fn* -> fn") (assert (= kwStruct "schema") "struct -> schema") (assert (= kwEnum "enum") "defenum -> enum") (assert (= kwMatch "mt") "match -> mt") (assert (= kwCond "cond") "cond* -> cond") true)

fn testCanonicalizeTypes -> Bool
  (let [(tStr (norm/canonicalizeType "string")) (tI64 (norm/canonicalizeType "int64")) (tI32 (norm/canonicalizeType "int32")) (tBool (norm/canonicalizeType "boolean")) (tF64 (norm/canonicalizeType "float64")) (tUnit (norm/canonicalizeType "void"))] (assert (= tStr "Str") "string -> Str") (assert (= tI64 "I64") "int64 -> I64") (assert (= tI32 "I32") "int32 -> I32") (assert (= tBool "Bool") "boolean -> Bool") (assert (= tF64 "F64") "float64 -> F64") (assert (= tUnit "Unit") "void -> Unit") true)

fn testBalanceDelimiters -> Bool
  (let [(unclosed "(fn calculate [(x I64)] (+ x 1") (balanced (bal/balanceDelimiters unclosed)) (nested "(let [(a 1) (b 2)] (+ a b") (nestedBalanced (bal/balanceDelimiters nested)) (withStr "(print \"hello ) world\"") (balancedStr (bal/balanceDelimiters withStr))] (assert (stringContains? balanced "))") "Unclosed must append closing parens") (assert (stringContains? nestedBalanced "))") "Nested must append closing parens") (assert (= balancedStr "(print \"hello ) world\")") "Parens in string literal must not cause extra closer") true)

fn testRepairHallucinations -> Bool
  (let [(dirty (str "(" "defun compute [(x String)] -> Int64 x")) (repDirty (norm/repairHallucinations dirty)) (clean "(fn compute [(x Str)] -> I64 x)") (repClean (norm/repairHallucinations clean))] (assert (not repDirty.isClean) "Dirty snippet must not be clean") (assert (= repDirty.repairsCount 1) "Repairs count must be 1") (assert repClean.isClean "Clean snippet must be clean") (assert (= repClean.repairsCount 0) "Clean snippet repairs must be 0") true)

fn runTests -> Bool
  (and (testNormalizeIdentifier) (and (testCanonicalizeKeywords) (and (testCanonicalizeTypes) (and (testBalanceDelimiters) (testRepairHallucinations)))))
