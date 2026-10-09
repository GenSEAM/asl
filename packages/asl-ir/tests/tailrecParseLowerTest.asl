(module asl-ir/tests/tailrecParseLowerTest
  :x [runTests]
  :i [(asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)
      (asl-ir/lower :a low)
      (asl-ir/types :a ty)
      (asl-ir/printer :a prn)])

fn source -> String
  "(module demo/tailrec :x [f]) (fn tailrec f [(n Int64)] -> Int64 (if (= n 0) 0 (f (- n 1))))"

fn diagnosticSource -> String
  "(module demo/diagnostic)\n(fn tailrec bad [] -> Int64 (return 1))"

fn hasFunctionName? forms: (List ast/TopForm) -> Bool
  (mt (listGet forms 1)
    ((some form)
      (mt form
        ((topDefun f) (= f.name "f"))
        (_ false)))
    ((none) false))

fn parsedAsOrdinaryFunction? -> Bool
  (mt (ast/parse (source))
    ((ok forms) (hasFunctionName? forms))
    ((err _) false))

fn parsedModifierIsFlagged? -> Bool
  (mt (ast/readForms (lx/tokenize (source)))
    ((ok forms)
      (mt (listGet forms 1)
        ((some positioned)
          (mt (listGet (ast/sexprItems positioned.expr) 1)
            ((some modifier) (ast/hasTailrec? (some modifier)))
            ((none) false)))
        ((none) false)))
    ((err _) false))

fn lowersAsOrdinaryFunction? -> Bool
  (mt (low/lowerSource (source))
    ((ok ir)
      (stringContains? (prn/printSsa ir) "(fn f "))
    ((err _) false))

fn modifierPreservesDiagnosticName? -> Bool
  (mt (low/lowerSource (diagnosticSource))
    ((ok _) false)
    ((err ds)
      (= (optionOr (listHead ds) (ty/makeIrDiag "" "" "")).locus "bad@2:1")))

fn runTests -> Bool
  (do (assert (parsedAsOrdinaryFunction?) "tailrec modifier must be consumed by parser, leaving function name f")
      (assert (parsedModifierIsFlagged?) "parsed tailrec declaration modifier must be flagged by hasTailrec?")
      (assert (lowersAsOrdinaryFunction?) "tailrec declaration must lower as ordinary function f")
      (assert (modifierPreservesDiagnosticName?) "tailrec modifier must not displace the declared function name in lowering diagnostics")
      true)
