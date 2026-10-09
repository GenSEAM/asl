(module asl-mesh/scanner :x [scanAstDefects checkVacuousTests astVisitor defectEmitter] :i [(asl-parser/reader :a rd)])

fn countVisits node: rd/SExpr visitorFn: Any -> Int64
  (let [(ownVisits (listLength (visitorFn node)))
        (childVisits (mt node
          ((rd/sexprAtom _) 0)
          ((rd/sexprList items)
            (fold (fn [(acc Int64) (child rd/SExpr)] -> Int64
                    (+ acc (countVisits child visitorFn))) 0 items))
          ((rd/sexprVect items)
            (fold (fn [(acc Int64) (child rd/SExpr)] -> Int64
                    (+ acc (countVisits child visitorFn))) 0 items))))]
    (+ ownVisits childVisits))

fn astVisitor node: Any visitorFn: Any -> Map
  (let [(visited (countVisits node visitorFn))]
    {:visited visited :node node})

fn defectEmitter defectId: Any path: Any lineNum: Any kind: Any severity: Any blameSym: Any rationale: Any -> Map
  (do {:defectId defectId :path path :lineNumber lineNum :kind kind :severity severity :blameSymbol blameSym :rationale rationale})

fn checkVacuousTests src: Any path: Any -> List
  (if (stringContains? src "(assert (= 1 1)") (list (defectEmitter "def-vacuous-1" path 1 :tautologicalAssertion :critical "assert" "Tautological assertion (= 1 1) detected")) (if (not (stringContains? src "assert")) (list (defectEmitter "def-vacuous-0" path 1 :tautologicalAssertion :high "assert" "Zero assertions declared in test suite")) (list)))

fn scanAstDefects src: Any path: Any -> List
  (let [(vacuous (checkVacuousTests src path))] vacuous)
