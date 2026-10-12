(module asl-checker/lint
  :x [LintHit lintModule quadraticListGetHit?]
  :i [(asl-parser/ast :a a) (asl-parser/reader :a rd) (asl-checker/resolve :a r)])

(schema LintHit (:f code String) (:f fnName String) (:f message String) (:f line Int64) (:f col Int64) (:f path String))

fn containsHeadMatch? name: String node: rd/SExpr -> Bool
  (mt node
    ((rd/sexprAtom _) false)
    ((rd/sexprList items) (or (= (rd/sexprHead node) name) (listAny? (fn [(it rd/SExpr)] -> Bool (containsHeadMatch? name it)) items)))
    ((rd/sexprVect items) (listAny? (fn [(it rd/SExpr)] -> Bool (containsHeadMatch? name it)) items)))

fn intParamNames params: (List a/Param) -> (List String)
  (map (fn [(p a/Param)] -> String p.name) (filter (fn [(p a/Param)] -> Bool (stringContains? p.type "Int")) params))

fn isListGetByCounter? counterNames: (List String) node: rd/SExpr -> Bool
  (mt node
    ((rd/sexprList items)
      (and (= (rd/sexprHead node) "listGet")
           (mt (listGet items 2)
             ((some idxNode) (and (rd/isAtom? idxNode) (listContains? counterNames (rd/sexprHead idxNode))))
             ((none) false))))
    (_ false))

fn anyListGetByCounter? counterNames: (List String) node: rd/SExpr -> Bool
  (or (isListGetByCounter? counterNames node)
      (mt node
        ((rd/sexprList items) (listAny? (fn [(it rd/SExpr)] -> Bool (anyListGetByCounter? counterNames it)) items))
        ((rd/sexprVect items) (listAny? (fn [(it rd/SExpr)] -> Bool (anyListGetByCounter? counterNames it)) items))
        ((rd/sexprAtom _) false)))

fn hasListAppendAccum? node: rd/SExpr -> Bool
  (mt node
    ((rd/sexprList items)
      (or (and (= (rd/sexprHead node) "listAppend") (mt (listGet items 2) ((some arg2) (= (rd/sexprHead arg2) "list")) ((none) false)))
          (listAny? (fn [(it rd/SExpr)] -> Bool (hasListAppendAccum? it)) items)))
    ((rd/sexprVect items) (listAny? (fn [(it rd/SExpr)] -> Bool (hasListAppendAccum? it)) items))
    ((rd/sexprAtom _) false))

fn quadraticListGetHit? d: a/DefunNode -> Bool
  (let [(counters (intParamNames d.params))]
    (and (not (listEmpty? counters))
         (listAny? (fn [(e rd/SExpr)] -> Bool (containsHeadMatch? d.name e)) d.body)
         (listAny? (fn [(e rd/SExpr)] -> Bool (anyListGetByCounter? counters e)) d.body)))

fn appendAccumNote d: a/DefunNode -> String
  (if (listAny? hasListAppendAccum? d.body) " (also accumulates with listAppend acc (list x) each step: another O(n) cost per iteration)" "")

fn suggestRewrite d: a/DefunNode -> String
  (str "rewrite " d.name " to walk the list by its own head/tail (listHead/listTail), or via fold/map over the list directly, instead of listGet by an incrementing Int counter")

fn lintHitFor d: a/DefunNode path: String -> LintHit
  (let [(pos (r/bodyPosAt d 0))
        (msg (str "fn " d.name " indexes a list with listGet by an Int counter on every recursive step, which is O(n) per call and O(n^2) over the walk" (appendAccumNote d) "; " (suggestRewrite d)))]
    (LintHit :code "LINT_QUADRATIC_LISTGET" :fnName d.name :message msg :line (pairFirst pos) :col (pairSecond pos) :path path))

fn lintModuleStep forms: (List a/TopForm) path: String acc: (List LintHit) -> (List LintHit)
  (fold (fn [(a (List LintHit)) (form a/TopForm)] -> (List LintHit)
          (mt form
            ((a/topDefun d) (if (quadraticListGetHit? d) (cons (lintHitFor d path) a) a))
            (_ a)))
        acc forms)

fn lintModule forms: (List a/TopForm) path: String -> (List LintHit)
  (listReverse (lintModuleStep forms path (list)))
