(module asl-tools/fleet/model
  :x [parseForms atomText itemsOf kvGet unquote stripColon atomsOf textOf intOf fleetPath load loadText entityNames entity entityFields entityRequired toolRows toolNamed toolOps toolStatus checklist exportsOf entityRefs asnQuote asnStrings requiredEntities validate makeEmpty]
  :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-tools/testImpact :a ti)])

fn parseForms src: String -> (Result (List rd/SExpr) String)
  (match (ast/readForms (lx/tokenize src))
    ((err e) (err e.msg))
    ((ok pfs) (ok (map (fn [(pf ast/PosForm)] -> rd/SExpr pf.expr) pfs))))

fn atomText s: rd/SExpr -> String
  (match s ((rd/sexprAtom v) v) (_ ""))

fn itemsOf s: rd/SExpr -> (List rd/SExpr)
  (match s ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) (_ (list)))

fn kvGet items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead items)
    ((none) (none))
    ((some it)
      (let [(rest (optionOr (listTail items) (list)))]
        (if (= (atomText it) key) (listHead rest) (kvGet rest key)))))

fn unquote v: String -> String
  (if (and (stringStartsWith? v "\"") (and (stringEndsWith? v "\"") (>= (stringLength v) 2)))
    (stringReplace (stringReplace (optionOr (stringSlice v 1 (- (stringLength v) 1)) v) "\\\"" "\"") "\\\\" "\\")
    v)

fn stripColon v: String -> String
  (if (stringStartsWith? v ":") (optionOr (stringSlice v 1 (stringLength v)) v) v)

fn textOf s: rd/SExpr -> String
  (stripColon (unquote (atomText s)))

fn atomsOf s: rd/SExpr -> (List String)
  (map textOf (itemsOf s))

fn intOf s: (Option rd/SExpr) -> (Option Int64)
  (match s ((none) (none)) ((some v) (stringToInt64 (atomText v))))

fn asnQuote s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn asnStrings xs: (List String) -> String
  (str "(" (stringJoin (map asnQuote xs) " ") ")")

fn ! fleetPath -> String
  (str (optionOr (envGet "ASL_ROOT") ".") "/asl/grammar/fleet.asn")

fn loadText text: String -> (Result (List rd/SExpr) String)
  (match (parseForms text)
    ((err e) (err (str "fleet.asn does not read: " e)))
    ((ok forms)
      (match (listHead forms)
        ((none) (err "fleet.asn is empty"))
        ((some top)
          (if (= (atomText (optionOr (listHead (itemsOf top)) (rd/makeAtom ""))) ":fleet")
            (ok (itemsOf top))
            (err "fleet.asn is not a (:fleet ...) form"))))))

fn ! load path: String -> (Result (List rd/SExpr) String)
  (match (fileReadString path)
    ((err e) (err (str "fleet.asn " path ": " e)))
    ((ok text) (loadText text)))

fn rowsOf fleet: (List rd/SExpr) key: String -> (List rd/SExpr)
  (itemsOf (optionOr (kvGet fleet key) (rd/makeList (list))))

fn rowName row: rd/SExpr -> String
  (textOf (optionOr (listGet (itemsOf row) 1) (rd/makeAtom "")))

fn entityNames fleet: (List rd/SExpr) -> (List String)
  (map rowName (rowsOf fleet ":entities"))

fn entity fleet: (List rd/SExpr) name: String -> (Option rd/SExpr)
  (listHead (filter (fn [(row rd/SExpr)] -> Bool (= (rowName row) name)) (rowsOf fleet ":entities")))

fn entityList fleet: (List rd/SExpr) name: String key: String -> (List String)
  (match (entity fleet name)
    ((none) (list))
    ((some row) (atomsOf (optionOr (kvGet (itemsOf row) key) (rd/makeList (list))))))

fn entityFields fleet: (List rd/SExpr) name: String -> (List String)
  (entityList fleet name ":fields")

fn entityRequired fleet: (List rd/SExpr) name: String -> (List String)
  (entityList fleet name ":required")

fn toolRows fleet: (List rd/SExpr) -> (List rd/SExpr)
  (rowsOf fleet ":tools")

fn toolNamed fleet: (List rd/SExpr) name: String -> (Option rd/SExpr)
  (listHead (filter (fn [(row rd/SExpr)] -> Bool (= (rowName row) name)) (toolRows fleet)))

fn toolOps row: rd/SExpr -> (List String)
  (atomsOf (optionOr (kvGet (itemsOf row) ":ops") (rd/makeList (list))))

fn toolStatus row: rd/SExpr -> String
  (textOf (optionOr (kvGet (itemsOf row) ":status") (rd/makeAtom "")))

fn checklist fleet: (List rd/SExpr) -> (List rd/SExpr)
  (rowsOf fleet ":checklist")

fn exportsOf source: String -> (List String)
  (match (parseForms (ti/headerOf source))
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some header) (let [(items (itemsOf header))] (atomsOf (optionOr (kvGet items ":export") (optionOr (kvGet items ":x") (rd/makeList (list))))))))))

fn entityRefs source: String -> (List String)
  (map (fn [(chunk String)] -> String
         (let [(afterModel (optionOr (listGet (stringSplit chunk "\"") 1) ""))]
           afterModel))
       (optionOr (listTail (stringSplit source "(fm/entity ")) (list)))

fn requiredEntities -> (List String)
  (list "Unit" "Track" "Owns" "Base" "Worktree" "Gate" "Claim" "Receipt" "RedBefore" "Mutant" "Integration" "Comparison" "Audit" "Defect" "Round" "Channel" "Metric")

fn rowProblems fleet: (List rd/SExpr) row: rd/SExpr -> (List String)
  (let [(items (itemsOf row))
        (cls (textOf (optionOr (kvGet items ":class") (rd/makeAtom ""))))
        (toolName (textOf (optionOr (kvGet items ":tool") (rd/makeAtom ""))))
        (op (textOf (optionOr (kvGet items ":op") (rd/makeAtom ""))))]
    (match (toolNamed fleet toolName)
      ((none) (list (str "checklist " cls ": tool " toolName " is not in :tools")))
      ((some tool) (if (listContains? (toolOps tool) op) (list)
                     (list (str "checklist " cls ": op " op " is not an op of tool " toolName))))))

fn namesAt items: (List rd/SExpr) key: String -> (List String)
  (match (kvGet items key)
    ((none) (list))
    ((some v) (if (rd/isAtom? v) (list (textOf v)) (atomsOf v))))

fn ! toolProblems fleet: (List rd/SExpr) root: String tool: rd/SExpr -> (List String)
  (let [(items (itemsOf tool))
        (name (rowName tool))
        (path (textOf (optionOr (kvGet items ":file") (rd/makeAtom ""))))
        (declared (listAppend (namesAt items ":emits") (namesAt items ":reads")))
        (names (entityNames fleet))
        (badDeclared (map (fn [(e String)] -> String (str "tool " name ": entity " e " is not in :entities"))
                          (filter (fn [(e String)] -> Bool (not (listContains? names e))) declared)))]
    (if (!= (toolStatus tool) "works") badDeclared
      (match (fileReadString (str root "/" path))
        ((err _) (listAppend badDeclared (list (str "tool " name ": file " path " is missing"))))
        ((ok source)
          (let [(exported (exportsOf source))
                (missingOps (filter (fn [(op String)] -> Bool (not (listContains? exported op))) (toolOps tool)))
                (badRefs (filter (fn [(e String)] -> Bool (not (listContains? names e))) (entityRefs source)))]
            (listAppend badDeclared
              (listAppend (map (fn [(op String)] -> String (str "tool " name ": op " op " is not exported by " path)) missingOps)
                          (map (fn [(e String)] -> String (str "tool " name ": " path " references entity " e " not in :entities")) badRefs))))))))

fn ! validate fleet: (List rd/SExpr) root: String -> (List String)
  (let [(names (entityNames fleet))
        (missing (map (fn [(e String)] -> String (str "entity " e " is missing"))
                      (filter (fn [(e String)] -> Bool (not (listContains? names e))) (requiredEntities))))
        (rows (checklist fleet))
        (rowIssues (if (listEmpty? rows) (list "checklist is empty")
                     (fold (fn [(acc (List String)) (row rd/SExpr)] -> (List String) (listAppend acc (rowProblems fleet row))) (list) rows)))
        (toolIssues (fold (fn [(acc (List String)) (tool rd/SExpr)] -> (List String) (listAppend acc (toolProblems fleet root tool))) (list) (toolRows fleet)))]
    (listAppend missing (listAppend rowIssues toolIssues)))

fn makeEmpty -> rd/SExpr
  (rd/makeList (list))
