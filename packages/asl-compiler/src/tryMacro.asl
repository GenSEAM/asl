(module asl-compiler/tryMacro
  :x [hasTryForm? expandTryMacro expandTryInSource makeTryExpansion findMatchingCloseParen]
  :i [])

fn hasTryForm? exprStr: String -> Bool
  (or (stringStartsWith? exprStr "(try ")
      (stringContains? exprStr " (try "))

fn makeTryExpansion innerExpr: String errVar: String -> String
  (str "(mt " innerExpr " ((ok __try_val) __try_val) ((err " errVar ") (err " errVar ")))")

fn expandTryMacro innerExpr: String -> String
  (makeTryExpansion innerExpr "__try_err")

fn findMatchingCloseParen text: String idx: Int64 depth: Int64 -> Int64
  (if (>= idx (stringLength text))
    idx
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))
          (newDepth (if (= ch "(") (+ depth 1) (if (= ch ")") (- depth 1) depth)))]
      (if (<= newDepth 0)
        idx
        (findMatchingCloseParen text (+ idx 1) newDepth))))

fn expandTryInSource src: String -> String
  (let [(prefix "(try ")]
    (mt (stringIndexOf src prefix)
      ((none) src)
      ((some idx)
        (let [(before (optionOr (stringSlice src 0 idx) ""))
              (afterPrefix (optionOr (stringSlice src (+ idx (stringLength prefix)) (stringLength src)) ""))
              (closeIdx (findMatchingCloseParen afterPrefix 0 1))]
          (if (>= closeIdx (stringLength afterPrefix))
            src
            (let [(inner (optionOr (stringSlice afterPrefix 0 closeIdx) ""))
                  (rest (optionOr (stringSlice afterPrefix (+ closeIdx 1) (stringLength afterPrefix)) ""))
                  (expanded (expandTryMacro inner))]
              (str before expanded (expandTryInSource rest))))))))
