(module asl-checker/ifArmShapeTest :x [runTests] :i [(asl-checker/check :a c)])

fn diagnosticsText ds: (List c/ty/Diagnostic) -> String
  (stringJoin (map (fn [(d c/ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn typeMismatch? ds: (List c/ty/Diagnostic) -> Bool
  (and (stringContains? (diagnosticsText ds) "expected") (stringContains? (diagnosticsText ds) "found Unit"))

fn invalidArm? ds: (List c/ty/Diagnostic) head: String -> Bool
  (and (stringContains? (diagnosticsText ds) "arm") (stringContains? (diagnosticsText ds) head))

fn testOneArmedIfValueRejected -> Bool
  (let [(ret (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (if true 1))" (mapEmpty) "m.asl"))
        (letVal (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [(x (if true 1))] x))" (mapEmpty) "m.asl"))
        (arg (c/checkSource "(module m :x [f g]) (fn g [(x Int64)] -> Int64 x) (fn f [] -> Int64 (g (if true 1)))" (mapEmpty) "m.asl"))
        (scrutinee (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (mt (if true 1) (1 7) (else 0)))" (mapEmpty) "m.asl"))]
    (do (assert (typeMismatch? ret) (str "one-arm if return must report expected Unit: " (diagnosticsText ret)))
        (assert (typeMismatch? letVal) (str "one-arm if let value must report expected Unit: " (diagnosticsText letVal)))
        (assert (typeMismatch? arg) (str "one-arm if call argument must report expected Unit: " (diagnosticsText arg)))
        (assert (typeMismatch? scrutinee) (str "one-arm if mt scrutinee must report expected Unit: " (diagnosticsText scrutinee)))
        true))

fn testMalformedArmRejected -> Bool
  (let [(doDs (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (mt 1 ((do (println \"bad\")) 2) (else 3)))" (mapEmpty) "m.asl"))
        (callDs (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (mt 1 ((println \"bad\") 2) (else 3)))" (mapEmpty) "m.asl"))
        (bareDo (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (mt 1 (1 2) (do 3)))" (mapEmpty) "m.asl"))
        (bareCall (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (mt 1 (1 2) (println 3)))" (mapEmpty) "m.asl"))]
    (do (assert (invalidArm? doDs "do") (str "do-headed arm must be named in a diagnostic: " (diagnosticsText doDs)))
        (assert (invalidArm? callDs "println") (str "call-headed arm must be named in a diagnostic: " (diagnosticsText callDs)))
        (assert (invalidArm? bareDo "do") (str "bare do arm head must be named in a diagnostic: " (diagnosticsText bareDo)))
        (assert (invalidArm? bareCall "println") (str "bare println arm head must be named in a diagnostic: " (diagnosticsText bareCall)))
        true))

fn testLegalShapesAccepted -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (do (if true 7) (mt (some (ok 1)) ((some (ok x)) x) (else 0))))" (mapEmpty) "m.asl"))]
    (assert (listEmpty? ds) (str "statement if and nested constructor patterns remain legal: " (diagnosticsText ds))) true)

fn testSubPatternBindersShadowNames -> Bool
  (let [(builtinName (c/checkSource "(module m :x [f]) (fn f [(o (Option Float64))] -> Float64 (mt o ((some exp) (+ exp 1.0)) ((none) 0.0)))" (mapEmpty) "m.asl"))
        (stringName (c/checkSource "(module m :x [f]) (fn f [(o (Option String))] -> Int64 (mt o ((some str) (stringLength str)) ((none) 0)))" (mapEmpty) "m.asl"))
        (localName (c/checkSource "(module m :x [f helper]) (fn helper [(x Int64)] -> Int64 x) (fn f [(r (Result Int64 String))] -> Int64 (mt r ((ok helper) (+ helper 1)) ((err _) 0)))" (mapEmpty) "m.asl"))
        (formName (c/checkSource "(module m :x [f]) (fn f [(o (Option Bool))] -> Bool (mt o ((some cond) cond) ((none) false)))" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? builtinName) (str "a constructor field may bind a builtin's name: " (diagnosticsText builtinName)))
        (assert (listEmpty? stringName) (str "a constructor field may bind str: " (diagnosticsText stringName)))
        (assert (listEmpty? localName) (str "a constructor field may bind a local function's name: " (diagnosticsText localName)))
        (assert (listEmpty? formName) (str "a constructor field may bind a form keyword's name: " (diagnosticsText formName)))
        true))

fn testPreludeCasePatternsAccepted -> Bool
  (let [(ioCases (c/checkSource "(module m :x [f]) (fn f [(e IoError)] -> Int64 (mt e ((notFound) 1) ((permissionDenied) 2) ((alreadyExists) 3) ((invalidPath) 4) ((interrupted) 5) ((other) 6)))" (mapEmpty) "m.asl"))
        (foreignBinder (c/checkSource "(module m :x [f Shape]) (enum Shape (:c circle [(r Int64)] \"c\") (:c square [(q Int64)] \"s\")) (fn f [(s Shape)] -> Int64 (mt s ((circle r) r) (other 7)))" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? ioCases) (str "IoError cases are constructor patterns: " (diagnosticsText ioCases)))
        (assert (listEmpty? foreignBinder) (str "a bare case name of another union binds the subject: " (diagnosticsText foreignBinder)))
        true))

fn runTests -> Bool
  (do (assert (testOneArmedIfValueRejected) "all one-armed if value contexts reject")
      (assert (testMalformedArmRejected) "malformed mt pattern is rejected")
      (assert (testLegalShapesAccepted) "legal if and pattern forms stay accepted")
      (assert (testSubPatternBindersShadowNames) "constructor field binders may shadow any name")
      (assert (testPreludeCasePatternsAccepted) "prelude cases and foreign bare cases stay legal")
      true)
