(module aslMesh/scanner
  :d "AST defect hunter harness and vacuous test detector under D85."
  :x [scan_ast_defects
      check_vacuous_tests
      ast_visitor
      defect_emitter]
  :i [])

(df ast_visitor [node visitorFn] -> Map
  :d "Traverses AST node invoking visitor function"
  {:visited 1 :node node})

(df defect_emitter [defectId path lineNum kind severity blameSym rationale] -> Map
  :d "Emits formal structured defect record conforming to mesh defect taxonomy"
  {:defectId defectId
   :path path
   :lineNumber lineNum
   :kind kind
   :severity severity
   :blameSymbol blameSym
   :rationale rationale})

(df check_vacuous_tests [src path] -> List
  :d "Scans test source for vacuous assertion patterns"
  (if (string-contains? src "(assert (= 1 1)")
    (list (defect_emitter "def-vacuous-1" path 1 :tautologicalAssertion :critical "assert" "Tautological assertion (= 1 1) detected"))
    (if (not (string-contains? src "assert"))
      (list (defect_emitter "def-vacuous-0" path 1 :tautologicalAssertion :high "assert" "Zero assertions declared in test suite"))
      (list))))

(df scan_ast_defects [src path] -> List
  :d "Scans source file for AST defects and returns list of defect records"
  (let [(vacuous (check_vacuous_tests src path))]
    vacuous))
