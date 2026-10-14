(module asl-html/asnCss
  :x [rulesOf asnToCss]
  :i [(asl-parser/reader :a rd) (asl-html/css :a c) (asl-html/asn :a a)])

fn propertyName name: String -> String
  (if (stringStartsWith? name "--") name (a/kebab name))

fn propertyChar? ch: String -> Bool
  (or (and (>= ch "a") (<= ch "z")) (or (and (>= ch "0") (<= ch "9")) (= ch "-")))

fn wellFormed? name: String -> Bool
  (and (not (stringEmpty? name)) (listAll? propertyChar? (stringChars name)))

fn declsOf where: String items: (List rd/SExpr) -> (Result (List c/Decl) (List String))
  (mt (listHead items)
    ((none) (ok []))
    ((some item)
      (mt (a/atomOf item)
        ((none) (err [(str where ": expected :property value pairs, found a nested form")]))
        ((some k)
          (if (not (a/keywordAtom? k))
            (err [(str where ": expected a :property, found " k)])
            (let [(name (propertyName (a/bare k)))]
              (mt (mt (listGet items 1) ((some x) (a/atomOf x)) ((none) (none)))
                ((none) (err [(str where ": property :" (a/bare k) " needs a single value")]))
                ((some v)
                  (if (not (wellFormed? name))
                    (err [(str where ": malformed property name :" (a/bare k))])
                    (mt (declsOf where (listDrop items 2))
                      ((err es) (err es))
                      ((ok more) (ok (cons (c/decl name (a/valueText v)) more)))))))))))))

fn stringsOf items: (List rd/SExpr) -> (List String)
  (map (fn [(x rd/SExpr)] -> String (a/valueText (optionOr (a/atomOf x) ""))) items)

fn frameOf where: String e: rd/SExpr -> (Result (Pair String (List c/Decl)) (List String))
  (mt e
    ((rd/sexprList items)
      (if (= (a/headOf e) "at")
        (mt (declsOf where (listDrop items 2))
          ((ok ds) (ok (pair (a/valueText (optionOr (a/atomOf (optionOr (listGet items 1) (rd/makeAtom ""))) "")) ds)))
          ((err es) (err es)))
        (err [(str where ": keyframes take (:at \"from\" :prop value) stops")])))
    (_ (err [(str where ": keyframes take (:at ...) stops")])))

fn collect results: (List (Result c/Rule (List String))) -> (Result (List c/Rule) (List String))
  (let [(errors (fold (fn [(acc (List String)) (r (Result c/Rule (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] results))]
    (if (listEmpty? errors) (ok (map (fn [(r (Result c/Rule (List String)))] -> c/Rule (mt r ((ok x) x) ((err _) (c/rule "" [])))) results)) (err errors)))

fn ruleOf parent: String index: Int64 e: rd/SExpr -> (Result c/Rule (List String))
  (let [(head (a/headOf e))
        (where (str parent head "[" (stringFromInt64 index) "]"))
        (items (mt e ((rd/sexprList xs) (listDrop xs 1)) (_ [])))
        (first (a/valueText (optionOr (a/atomOf (optionOr (listHead items) (rd/makeAtom ""))) "")))
        (nested (fn [(name String)] -> (Result c/Rule (List String)) (mt (rulesOf (str where " > ") (listDrop items 1)) ((ok rs) (ok (c/atRule name first rs))) ((err es) (err es)))))]
    (cond
      ((= head "rule") (mt (declsOf where (listDrop items 1)) ((ok ds) (ok (c/rule first ds))) ((err es) (err es))))
      ((listContains? ["media" "supports" "layer" "container"] head) (nested head))
      ((= head "keyframes")
        (let [(frames (map (fn [(f rd/SExpr)] -> (Result (Pair String (List c/Decl)) (List String)) (frameOf where f)) (listDrop items 1)))
              (bad (fold (fn [(acc (List String)) (r (Result (Pair String (List c/Decl)) (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] frames))]
          (if (listEmpty? bad) (ok (c/keyframes first (map (fn [(r (Result (Pair String (List c/Decl)) (List String)))] -> (Pair String (List c/Decl)) (mt r ((ok p) p) ((err _) (pair "" [])))) frames))) (err bad))))
      ((= head "fontFace") (mt (declsOf where items) ((ok ds) (ok (c/fontFace ds))) ((err es) (err es))))
      ((= head "import") (ok (c/importUrl first)))
      ((= head "layerOrder") (ok (c/layerOrder (stringsOf items))))
      (else (err [(str where ": unknown rule :" head "; known: rule media supports layer container keyframes fontFace import layerOrder")]))))

fn rulesOf parent: String items: (List rd/SExpr) -> (Result (List c/Rule) (List String))
  (collect (map (fn [(p (Pair Int64 rd/SExpr))] -> (Result c/Rule (List String)) (ruleOf parent (pairFirst p) (pairSecond p))) (enumerate items)))

fn asnToCss source: String -> (Result String (List String))
  (let [(root (rd/parseSexpr source))]
    (if (not (= (a/headOf root) "css"))
      (err ["a stylesheet must be one (:css ...) form"])
      (mt (rulesOf "css > " (mt root ((rd/sexprList xs) (listDrop xs 1)) (_ [])))
        ((ok rules) (ok (str (c/renderSheet rules) "\n")))
        ((err es) (err es)))))
