(module asl-lint/incongruity
  :d "AgentScript monorepo forensic scanner validating zero sigils, zero foreign files, crutch eradication, 1-to-2 token compliance, and AST CFG dead-code eradication (d41, d46, d48)."
  :x [IncongruityReport
      scanMonorepoIncongruities
      detectCrutches
      detectLingeringSigils
      detectDeadCondBranches
      detectPostTerminalExpressions
      makeIncongruityReport]
  :i [(asl-lint/tokens :a tok)
      (asl-parser/ast :a a)
      (asl-parser/reader :a rd)])

(dfs IncongruityReport
  (:f totalScanned I64 "Total items, files, or symbols scanned")
  (:f sigilViolations I64 "Count of lingering sigils discovered")
  (:f foreignViolations I64 "Count of foreign files or illegal markdown memory ledgers")
  (:f tokenViolations I64 "Count of symbols exceeding the 2-token ceiling")
  (:f crutchViolations I64 "Count of temporary crutches or scaffolding patterns")
  (:f deadCodeViolations I64 "Count of dead condition branches and post-terminal expressions")
  (:f passed Bool "True if all invariant checks pass with zero violations"))

(df makeIncongruityReport [(scanned I64) (sigils I64) (foreign I64) (tokens I64) (crutches I64) (deadCode I64)] -> IncongruityReport
  :d "Constructs an IncongruityReport and evaluates pass/fail status based on zero violations."
  (let [(ok? (and (= sigils 0)
                  (and (= foreign 0)
                       (and (= tokens 0)
                            (and (= crutches 0)
                                 (= deadCode 0))))))]
    (IncongruityReport
      :totalScanned scanned
      :sigilViolations sigils
      :foreignViolations foreign
      :tokenViolations tokens
      :crutchViolations crutches
      :deadCodeViolations deadCode
      :passed ok?)))

(df hasSigil? [(text Str)] -> Bool
  :d "Checks if a string contains prohibited sigils per c5 and d48."
  (or (string-contains? text "@")
      (string-contains? text "#")))

(df detectLingeringSigils [(items (List Str))] -> I64
  :d "Counts occurrences of prohibited sigils across a list of text strings."
  (fold (fn [(acc I64) (item Str)] -> I64
          (if (hasSigil? item)
            (+ acc 1)
            acc))
        0
        items))

(df isCrutchToken? [(text Str)] -> Bool
  :d "Checks if a string contains known temporary scaffolding or crutch markers."
  (or (string-contains? text "TODO")
      (or (string-contains? text "todo")
          (or (string-contains? text "FIXME")
              (or (string-contains? text "HACK")
                  (or (string-contains? text "STUB")
                      (or (string-contains? text "stub")
                          (or (string-contains? text "MOCK")
                              (or (string-contains? text "mock")
                                  (or (string-contains? text "SWALLOW")
                                      (or (string-contains? text "swallow")
                                          (or (string-contains? text "crutch")
                                              (string-contains? text "temporary-scaffolding")))))))))))))

(df detectCrutches [(items (List Str))] -> I64
  :d "Counts instances of temporary crutches and scaffolding markers across a list of items."
  (fold (fn [(acc I64) (item Str)] -> I64
          (if (isCrutchToken? item)
            (+ acc 1)
            acc))
        0
        items))

(df isForeignFile? [(path Str)] -> Bool
  :d "Checks if a path violates pure AgentScript rules."
  (or (string-ends-with? path ".py")
      (or (string-ends-with? path ".js")
          (or (string-ends-with? path ".ts")
              (or (string-ends-with? path ".rs")
                  (and (string-contains? path ".asl/mem/")
                       (string-ends-with? path ".md")))))))

(df detectForeignFiles [(paths (List Str))] -> I64
  :d "Counts foreign files and illegal markdown memory ledgers."
  (fold (fn [(acc I64) (path Str)] -> I64
          (if (isForeignFile? path)
            (+ acc 1)
            acc))
        0
        paths))

(df isTokenCompliant? [(sym Str)] -> Bool
  :d "Checks whether an identifier complies with 1-to-2 token ceiling."
  (<= (tok/estimateIdentifierTokens sym) 2))

(df detectTokenViolations [(symbols (List Str))] -> I64
  :d "Counts identifiers exceeding the 2-token ceiling."
  (fold (fn [(acc I64) (sym Str)] -> I64
          (if (isTokenCompliant? sym)
            acc
            (+ acc 1)))
        0
        symbols))

(df safeTail [(l (List T))] -> (List T)
  :d "Returns tail of a list, or empty list if input has length 0 or 1."
  (if (list-empty? l)
    (list)
    (mt (list-tail l 1)
      ((some r) r)
      ((none) (list)))))

(df countDeadInCondClauses [(clauses (List rd/SExpr))] -> I64
  :d "Counts cond clauses occurring after an unconditional :else clause."
  (let [(res (fold (fn [(acc (Pair Bool I64)) (clause rd/SExpr)] -> (Pair Bool I64)
                     (let [(afterElse (.-first acc))
                           (deadCount (.-second acc))]
                       (if afterElse
                         (pair true (+ deadCount 1))
                         (mt clause
                           ((rd/sexprList cparts)
                            (mt (list-head cparts)
                              ((some ch)
                               (if (= (rd/sexprHead ch) ":else")
                                 (pair true deadCount)
                                 (pair false deadCount)))
                              ((none) (pair false deadCount))))
                           (_ (pair false deadCount))))))
                   (pair false 0)
                   clauses))]
    (.-second res)))

(df detectDeadCondInSexpr [(s rd/SExpr)] -> I64
  :d "Recursively counts dead cond clauses within an S-expression."
  (mt s
    ((rd/sexprAtom _) 0)
    ((rd/sexprVect items)
     (fold (fn [(acc I64) (item rd/SExpr)] -> I64
             (+ acc (detectDeadCondInSexpr item)))
           0
           items))
    ((rd/sexprList items)
     (mt (list-head items)
       ((none) 0)
       ((some h)
        (let [(headTok (rd/sexprHead h))
              (subDead (fold (fn [(acc I64) (item rd/SExpr)] -> I64
                               (+ acc (detectDeadCondInSexpr item)))
                             0
                             items))]
          (if (= headTok "cond")
            (let [(clauses (safeTail items))
                  (thisDead (countDeadInCondClauses clauses))]
              (+ thisDead subDead))
            subDead)))))))

(df detectDeadCondBranches [(forms (List a/TopForm))] -> I64
  :d "Traverses AST to inspect cond expressions, flagging any clause occurring after an unconditional :else clause as unreachable dead code."
  (fold (fn [(acc I64) (form a/TopForm)] -> I64
          (mt form
            ((a/topDefun d)
             (fold (fn [(iacc I64) (e rd/SExpr)] -> I64
                     (+ iacc (detectDeadCondInSexpr e)))
                   acc
                   (.-body d)))
            ((a/topModule _) acc)
            (_ acc)))
        0
        forms))

(df isTerminalHead? [(h String)] -> Bool
  :d "Returns true if head token represents an unconditional terminal control flow."
  (or (= h "err")
      (or (= h "return")
          (or (= h "panic")
              (= h "exit")))))

(df isTerminalExpr? [(s rd/SExpr)] -> Bool
  :d "Returns true if expression is an unconditional terminal invocation."
  (mt s
    ((rd/sexprList items)
     (mt (list-head items)
       ((some h) (isTerminalHead? (rd/sexprHead h)))
       ((none) false)))
    (_ false)))

(df countDeadInSeq [(seq (List rd/SExpr))] -> I64
  :d "Counts expressions placed after an unconditional terminal expression in a block."
  (let [(res (fold (fn [(acc (Pair Bool I64)) (e rd/SExpr)] -> (Pair Bool I64)
                     (let [(afterTerm (.-first acc))
                           (deadCount (.-second acc))]
                       (if afterTerm
                         (pair true (+ deadCount 1))
                         (if (isTerminalExpr? e)
                           (pair true deadCount)
                           (pair false deadCount)))))
                   (pair false 0)
                   seq))]
    (.-second res)))

(df detectPostTerminalInSexpr [(s rd/SExpr)] -> I64
  :d "Recursively inspects S-expression for post-terminal expressions in nested blocks."
  (mt s
    ((rd/sexprAtom _) 0)
    ((rd/sexprVect items)
     (fold (fn [(acc I64) (item rd/SExpr)] -> I64
             (+ acc (detectPostTerminalInSexpr item)))
           0
           items))
    ((rd/sexprList items)
     (mt (list-head items)
       ((none) 0)
       ((some h)
        (let [(headTok (rd/sexprHead h))
              (subDead (fold (fn [(acc I64) (item rd/SExpr)] -> I64
                               (+ acc (detectPostTerminalInSexpr item)))
                             0
                             items))]
          (if (= headTok "do")
            (let [(seq (safeTail items))
                  (thisDead (countDeadInSeq seq))]
              (+ thisDead subDead))
            subDead)))))))

(df detectPostTerminalExpressions [(forms (List a/TopForm))] -> I64
  :d "Traverses sequential blocks and flags expressions placed after an unconditional terminal return or (err ...) form."
  (fold (fn [(acc I64) (form a/TopForm)] -> I64
          (mt form
            ((a/topDefun d)
             (let [(bodyForms (.-body d))
                   (bodyDead (countDeadInSeq bodyForms))
                   (innerDead (fold (fn [(iacc I64) (e rd/SExpr)] -> I64
                                      (+ iacc (detectPostTerminalInSexpr e)))
                                    0
                                    bodyForms))]
               (+ acc (+ bodyDead innerDead))))
            ((a/topModule _) acc)
            (_ acc)))
        0
        forms))

(df scanMonorepoIncongruities [(paths (List Str)) (symbols (List Str)) (snippets (List Str))] -> IncongruityReport
  :d "Performs forensic monorepo scan aggregating sigils, foreign files, token ceiling, and crutch violations."
  (let [(sigils (+ (detectLingeringSigils paths)
                   (+ (detectLingeringSigils symbols)
                      (detectLingeringSigils snippets))))
        (foreign (detectForeignFiles paths))
        (tokens (detectTokenViolations symbols))
        (crutches (detectCrutches snippets))
        (total (+ (list-length paths)
                  (+ (list-length symbols)
                     (list-length snippets))))]
    (makeIncongruityReport total sigils foreign tokens crutches 0)))
