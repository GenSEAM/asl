(module asl-compiler/macro
  :x [expandLetPair expandIfLet expandWhenLet expandCond expandCase expandLetStar expandPipe]
  :i [])

fn expandLetPair k: Str v: Str pairExpr: Str bodyExpr: Str -> Str
  (str "(let [(__pair " pairExpr ")\n"
       "      (" k " (pairFirst __pair))\n"
       "      (" v " (pairSecond __pair))]\n"
       "  " bodyExpr ")")

fn expandIfLet bindingVar: Str optExpr: Str thenExpr: Str elseExpr: Str -> Str
  (str "(mt " optExpr "\n"
       "  ((some " bindingVar ") " thenExpr ")\n"
       "  ((none) " elseExpr "))")

fn expandWhenLet bindingVar: Str optExpr: Str bodyExpr: Str -> Str
  (expandIfLet bindingVar optExpr bodyExpr "(none)")

fn expandCondStep clauses: (List (Pair Str Str)) defaultExpr: Str -> Str
  (if (listEmpty? clauses)
    defaultExpr
    (let [(firstPair (optionOr (listHead clauses) (pair "" "")))
          (rest (optionOr (listTail clauses) (list)))
          (testExpr (pairFirst firstPair))
          (bodyExpr (pairSecond firstPair))]
      (str "(if " testExpr " " bodyExpr " " (expandCondStep rest defaultExpr) ")")))

fn expandCond clauses: (List (Pair Str Str)) defaultExpr: Str -> Str
  (expandCondStep clauses defaultExpr)

fn expandCaseStep varName: Str arms: (List (Pair Str Str)) defaultExpr: Str -> Str
  (if (listEmpty? arms)
    defaultExpr
    (let [(firstArm (optionOr (listHead arms) (pair "" "")))
          (rest (optionOr (listTail arms) (list)))
          (pattern (pairFirst firstArm))
          (armBody (pairSecond firstArm))]
      (str "(if (= " varName " " pattern ") " armBody " " (expandCaseStep varName rest defaultExpr) ")")))

fn expandCase valExpr: Str arms: (List (Pair Str Str)) defaultExpr: Str -> Str
  (str "(let [(__case_target " valExpr ")] " (expandCaseStep "__case_target" arms defaultExpr) ")")

fn expandLetStar bindings: (List (Pair Str Str)) bodyExpr: Str -> Str
  (if (listEmpty? bindings)
    bodyExpr
    (let [(firstPair (optionOr (listHead bindings) (pair "" "")))
          (rest (optionOr (listTail bindings) (list)))
          (varName (pairFirst firstPair))
          (valExpr (pairSecond firstPair))]
      (str "(let [(" varName " " valExpr ")] " (expandLetStar rest bodyExpr) ")")))

fn pipeThreadSingle acc: Str form: Str -> Str
  (let [(trimmed (stringTrim form))]
    (if (and (stringStartsWith? trimmed "(") (stringEndsWith? trimmed ")"))
      (let [(len (stringLength trimmed))
            (inner (stringTrim (optionOr (stringSlice trimmed 1 (- len 1)) "")))]
        (if (stringContains? inner " ")
          (let [(parts (stringSplit inner " "))
                (op (optionOr (listHead parts) ""))
                (restParts (optionOr (listTail parts) (list)))
                (restArgs (stringJoin restParts " "))]
            (str "(" op " " acc " " restArgs ")"))
          (str "(" inner " " acc ")")))
      (str "(" trimmed " " acc ")")))

fn expandPipeStep acc: Str forms: (List Str) -> Str
  (if (listEmpty? forms)
    acc
    (let [(firstForm (optionOr (listHead forms) ""))
          (rest (optionOr (listTail forms) (list)))
          (nextAcc (pipeThreadSingle acc firstForm))]
      (expandPipeStep nextAcc rest)))

fn expandPipe initialExpr: Str forms: (List Str) -> Str
  (expandPipeStep initialExpr forms)
