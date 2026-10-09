(module asl-compiler/threadMacro
  :x [hasThreadForm? threadFirstStep threadLastStep expandThreadMacro expandThreadInSource findMatchingCloseParen parseThreadForms]
  :i [])

fn hasThreadForm? exprStr: String -> Bool
  (or (stringStartsWith? exprStr "(-> ")
      (or (stringContains? exprStr " (-> ")
          (or (stringStartsWith? exprStr "(->> ")
              (stringContains? exprStr " (->> "))))

fn findMatchingCloseParen text: String idx: Int64 depth: Int64 -> Int64
  (if (>= idx (stringLength text))
    idx
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))
          (newDepth (if (= ch "(") (+ depth 1) (if (= ch ")") (- depth 1) depth)))]
      (if (<= newDepth 0)
        idx
        (findMatchingCloseParen text (+ idx 1) newDepth))))

fn threadFirstStep acc: String step: String -> String
  (let [(clean (stringTrim step))]
    (if (and (stringStartsWith? clean "(") (stringEndsWith? clean ")"))
      (let [(inner (optionOr (stringSlice clean 1 (- (stringLength clean) 1)) ""))
            (spaceIdx (stringIndexOf inner " "))]
        (mt spaceIdx
          ((none) (str "(" inner " " acc ")"))
          ((some idx)
            (let [(head (optionOr (stringSlice inner 0 idx) ""))
                  (args (optionOr (stringSlice inner idx (stringLength inner)) ""))]
              (str "(" head " " acc args ")")))))
      (str "(" clean " " acc ")")))

fn threadLastStep acc: String step: String -> String
  (let [(clean (stringTrim step))]
    (if (and (stringStartsWith? clean "(") (stringEndsWith? clean ")"))
      (let [(inner (optionOr (stringSlice clean 1 (- (stringLength clean) 1)) ""))]
        (str "(" inner " " acc ")"))
      (str "(" clean " " acc ")")))

fn findNextTokenEnd text: String idx: Int64 depth: Int64 inStr: Bool -> Int64
  (if (>= idx (stringLength text))
    idx
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if inStr
        (if (= ch "\"")
          (findNextTokenEnd text (+ idx 1) depth false)
          (findNextTokenEnd text (+ idx 1) depth true))
        (if (= ch "\"")
          (findNextTokenEnd text (+ idx 1) depth true)
          (if (= ch "(")
            (findNextTokenEnd text (+ idx 1) (+ depth 1) false)
            (if (= ch ")")
              (if (<= depth 1)
                idx
                (findNextTokenEnd text (+ idx 1) (- depth 1) false))
              (if (and (= depth 0) (or (= ch " ") (or (= ch "\t") (or (= ch "\n") (= ch "\r")))))
                idx
                (findNextTokenEnd text (+ idx 1) depth false))))))))

fn skipWhitespace text: String idx: Int64 -> Int64
  (if (>= idx (stringLength text))
    idx
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if (or (= ch " ") (or (= ch "\t") (or (= ch "\n") (= ch "\r"))))
        (skipWhitespace text (+ idx 1))
        idx)))

fn parseThreadFormsHelper text: String idx: Int64 acc: (List String) -> (List String)
  (let [(start (skipWhitespace text idx))]
    (if (>= start (stringLength text))
      acc
      (let [(firstCh (optionOr (stringSlice text start (+ start 1)) ""))]
        (if (= firstCh "(")
          (let [(endParen (findMatchingCloseParen text (+ start 1) 1))
                (token (optionOr (stringSlice text start (+ endParen 1)) ""))]
            (parseThreadFormsHelper text (+ endParen 1) (listAppend acc (list token))))
          (let [(endTok (findNextTokenEnd text start 0 false))
                (token (optionOr (stringSlice text start endTok) ""))]
            (parseThreadFormsHelper text endTok (listAppend acc (list token))))))))

fn parseThreadForms text: String -> (List String)
  (parseThreadFormsHelper text 0 (list))

fn foldThreadFirst initial: String steps: (List String) idx: Int64 len: Int64 -> String
  (if (>= idx len)
    initial
    (let [(step (optionOr (listGet steps idx) ""))
          (next (threadFirstStep initial step))]
      (foldThreadFirst next steps (+ idx 1) len)))

fn foldThreadLast initial: String steps: (List String) idx: Int64 len: Int64 -> String
  (if (>= idx len)
    initial
    (let [(step (optionOr (listGet steps idx) ""))
          (next (threadLastStep initial step))]
      (foldThreadLast next steps (+ idx 1) len)))

fn expandThreadMacro innerExpr: String -> String
  (let [(trimmed (stringTrim innerExpr))
        (isThreadLast (stringStartsWith? trimmed "> "))
        (restExpr (if isThreadLast (stringTrim (optionOr (stringSlice trimmed 2 (stringLength trimmed)) "")) trimmed))
        (forms (parseThreadForms restExpr))]
    (if (< (listLength forms) 2)
      restExpr
      (let [(initial (optionOr (listGet forms 0) ""))
            (stepCount (- (listLength forms) 1))
            (steps (optionOr (listSlice forms 1 (listLength forms)) (list)))]
        (if isThreadLast
          (foldThreadLast initial steps 0 (listLength steps))
          (foldThreadFirst initial steps 0 (listLength steps))))))

fn expandThreadInSourceHelper src: String prefix: String -> String
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
                (macroPayload (if (= prefix "(->> ") (str "> " inner) inner))
                (expanded (expandThreadMacro macroPayload))]
            (str before expanded (expandThreadInSource rest)))))))

fn expandThreadInSource src: String -> String
  (let [(step1 (expandThreadInSourceHelper src "(->> "))]
    (expandThreadInSourceHelper step1 "(-> "))
