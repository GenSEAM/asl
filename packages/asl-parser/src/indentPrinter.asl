(module asl-parser/indentPrinter :x [formatIndented formatSexpr isDotAccess? formatDotAccess isListForm? formatListForm printIndented formatSchemaForm formatEnumForm isMatchForm? extractDocstring] :i [(reader :a rd)])

fn indentPrefix level: Int64 -> String
  (stringRepeat "  " level)

fn isDotAccess? s: rd/SExpr -> Bool
  (mt s ((sexprList items) (mt (listHead items) ((some h) (mt h ((sexprAtom v) (stringStartsWith? v ".-")) (_ false))) ((none) false))) (_ false))

fn formatDotAccess s: rd/SExpr -> String
  (mt s ((sexprList items) (let [(headSym (rd/sexprHead s)) (propName (if (stringStartsWith? headSym ".-") (stringSlice headSym 2 (stringLength headSym)) (some headSym))) (prop (optionOr propName headSym)) (tailItems (optionOr (listTail items) (list)))] (mt (listHead tailItems) ((some target) (if (isDotAccess? target) (str (formatDotAccess target) "." prop) (str (formatSexpr target 0) "." prop))) ((none) prop)))) ((sexprAtom v) v) (_ ""))

fn isListForm? s: rd/SExpr -> Bool
  (mt s ((sexprList items) (mt (listHead items) ((some h) (mt h ((sexprAtom v) (= v "list")) (_ false))) ((none) false))) (_ false))

fn formatListForm s: rd/SExpr indent: Int64 -> String
  (mt s ((sexprList items) (let [(args (optionOr (listTail items) (list)))] (if (<= (listLength args) 5) (str "[" (stringJoin (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) args) " ") "]") (let [(lines (map (fn [(x rd/SExpr)] -> String (str (indentPrefix (+ indent 1)) "- " (formatCallBody x))) args))] (str "\n" (stringJoin lines "\n")))))) (_ "[]"))

fn formatParamsVector v: rd/SExpr -> String
  (let [(items (rd/sexprToList v))] (let [(paramStrs (map (fn [(p rd/SExpr)] -> String (mt p ((sexprList pItems) (let [(pName (rd/sexprHead p)) (restItems (optionOr (listTail pItems) (list))) (pTypeSexpr (optionOr (listHead restItems) (rd/makeAtom "Any"))) (pType (formatSexpr pTypeSexpr 0))] (str pName ": " pType))) (_ ""))) items))] (stringJoin paramStrs " ")))

fn formatCallBody s: rd/SExpr -> String
  (mt s ((sexprAtom v) v) ((sexprVect items) (str "[" (stringJoin (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items) " ") "]")) ((sexprList items) (cond ((isDotAccess? s) (formatDotAccess s)) ((isListForm? s) (formatListForm s 0)) (else (let [(renderedArgs (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items))] (stringJoin renderedArgs " "))))))

fn isMatchForm? s: rd/SExpr -> Bool
  (mt s ((sexprList items) (mt (listHead items) ((some h) (mt h ((sexprAtom v) (= v "match")) (_ false))) ((none) false))) (_ false))

fn formatMatchArm arm: rd/SExpr indent: Int64 -> String
  (mt arm ((sexprList items) (let [(firstItem (optionOr (listGet items 0) (rd/makeAtom "_"))) (secondItem (optionOr (listGet items 1) (rd/makeAtom "()")))] (let [(pat (mt firstItem ((sexprList pItems) (stringJoin (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) pItems) " ")) (_ (formatSexpr firstItem 0))))] (if (isMatchForm? secondItem) (str (indentPrefix indent) pat " ->\n" (formatMatchForm secondItem (+ indent 1))) (let [(bod (formatCallBody secondItem))] (str (indentPrefix indent) pat " -> " bod)))))) (_ ""))

fn formatMatchForm s: rd/SExpr indent: Int64 -> String
  (mt s ((sexprList items) (let [(targetSexpr (optionOr (listGet items 1) (rd/makeAtom "_"))) (renderedTarget (formatSexpr targetSexpr 0)) (armsList (if (> (listLength items) 3) (optionOr (listSlice items 2 (listLength items)) (list)) (let [(c (optionOr (listGet items 2) (rd/makeList (list))))] (mt c ((sexprList cItems) (mt (listHead cItems) ((some firstEl) (if (rd/isList? firstEl) cItems (list c))) ((none) (list)))) (_ (list c)))))) (armLines (map (fn [(a rd/SExpr)] -> String (formatMatchArm a (+ indent 1))) armsList))] (str (indentPrefix indent) "match " renderedTarget "\n" (stringJoin armLines "\n")))) (_ ""))

fn extractDocstring items: (List rd/SExpr) -> (Pair (Option String) (List rd/SExpr))
  (mt (listHead items) ((some h) (let [(hVal (rd/sexprHead h)) (tailItems (optionOr (listTail items) (list)))] (if (or (= hVal ":d") (= hVal ":doc")) (mt (listHead tailItems) ((some docAtom) (pair (some (rd/sexprHead docAtom)) (optionOr (listTail tailItems) (list)))) ((none) (pair (none) tailItems))) (pair (none) items)))) ((none) (pair (none) (list))))

fn stripInlineDoc items: (List rd/SExpr) -> (List rd/SExpr)
  (pairSecond (extractDocstring items))

fn formatDefunForm s: rd/SExpr indent: Int64 -> String
  (mt s ((sexprList items) (let [(fnName (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom "anonymous")))) (item2 (optionOr (listGet items 2) (rd/makeList (list)))) (hasEffect (and (rd/isAtom? item2) (= (rd/sexprHead item2) "!"))) (paramsVect (if hasEffect (optionOr (listGet items 3) (rd/makeList (list))) item2)) (arrowSym (if hasEffect (rd/sexprHead (optionOr (listGet items 4) (rd/makeAtom "->"))) (rd/sexprHead (optionOr (listGet items 3) (rd/makeAtom "->"))))) (retType (if hasEffect (optionOr (listGet items 5) (rd/makeAtom "Unit")) (optionOr (listGet items 4) (rd/makeAtom "Unit")))) (rawBodyForms (if hasEffect (if (> (listLength items) 6) (optionOr (listSlice items 6 (listLength items)) (list)) (list)) (if (> (listLength items) 5) (optionOr (listSlice items 5 (listLength items)) (list)) (list)))) (docRes (extractDocstring rawBodyForms)) (docOpt (pairFirst docRes)) (bodyForms (pairSecond docRes)) (sigText (formatParamsVector paramsVect)) (retText (formatSexpr retType 0)) (effStr (if hasEffect "! " "")) (header (if (stringEmpty? sigText) (str (indentPrefix indent) "fn " fnName (if hasEffect " ! -> " " -> ") retText) (str (indentPrefix indent) "fn " fnName " " effStr sigText " -> " retText))) (docLine (mt docOpt ((some d) (list (str (indentPrefix (+ indent 1)) ":d " d))) ((none) (list)))) (bodyLines (map (fn [(b rd/SExpr)] -> String (formatSexpr b (+ indent 1))) bodyForms)) (allLines (listAppend docLine bodyLines))] (if (listEmpty? allLines) header (str header "\n" (stringJoin allLines "\n"))))) (_ ""))

fn formatSchemaField f: rd/SExpr indent: Int64 -> String
  (mt f ((sexprList items) (let [(fName (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom "")))) (fType (formatSexpr (optionOr (listGet items 2) (rd/makeAtom "Any")) 0)) (docOpt (listGet items 3))] (mt docOpt ((some docAtom) (let [(docStr (rd/sexprHead docAtom))] (if (or (= docStr "") (= docStr "\"\"")) (str (indentPrefix indent) fName ": " fType) (str (indentPrefix indent) fName ": " fType " " docStr)))) ((none) (str (indentPrefix indent) fName ": " fType))))) (_ ""))

fn formatSchemaForm s: rd/SExpr indent: Int64 -> String
  (mt s ((sexprList items) (let [(name (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom "Anonymous")))) (fieldForms (if (> (listLength items) 2) (optionOr (listSlice items 2 (listLength items)) (list)) (list))) (header (str (indentPrefix indent) "schema " name))] (if (listEmpty? fieldForms) header (let [(fieldLines (map (fn [(f rd/SExpr)] -> String (formatSchemaField f (+ indent 1))) fieldForms))] (str header "\n" (stringJoin fieldLines "\n")))))) (_ ""))

fn formatEnumCase c: rd/SExpr indent: Int64 -> String
  (mt c ((sexprList items) (let [(caseName (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom ""))))] (str (indentPrefix indent) caseName))) ((sexprAtom v) (str (indentPrefix indent) v)) (_ ""))

fn formatEnumForm s: rd/SExpr indent: Int64 -> String
  (mt s ((sexprList items) (let [(name (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom "Anonymous")))) (caseForms (if (> (listLength items) 2) (optionOr (listSlice items 2 (listLength items)) (list)) (list))) (header (str (indentPrefix indent) "enum " name))] (if (listEmpty? caseForms) header (let [(caseLines (map (fn [(c rd/SExpr)] -> String (formatEnumCase c (+ indent 1))) caseForms))] (str header "\n" (stringJoin caseLines "\n")))))) (_ ""))

fn formatSexpr s: rd/SExpr indent: Int64 -> String
  (mt s ((sexprAtom v) v) ((sexprVect items) (str "[" (stringJoin (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items) " ") "]")) ((sexprList items) (if (listEmpty? items) "()" (let [(headSym (rd/sexprHead s))] (cond ((or (= headSym "df") (= headSym "fn")) (formatDefunForm s indent)) ((= headSym "match") (formatMatchForm s indent)) ((or (= headSym "schema") (= headSym "dfs")) (formatSchemaForm s indent)) ((or (= headSym "enum") (= headSym "dfe")) (formatEnumForm s indent)) ((isDotAccess? s) (formatDotAccess s)) ((isListForm? s) (formatListForm s indent)) (else (let [(renderedArgs (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items))] (if (> indent 0) (str (indentPrefix indent) (stringJoin renderedArgs " ")) (str "(" (stringJoin renderedArgs " ") ")")))))))))

fn formatIndented s: rd/SExpr -> String
  (mt s ((sexprList items) (if (listEmpty? items) "()" (let [(headSym (rd/sexprHead s))] (cond ((or (= headSym "df") (= headSym "fn")) (formatDefunForm s 0)) ((= headSym "match") (formatMatchForm s 0)) ((= headSym "module") (formatSexpr s 0)) ((or (= headSym "schema") (= headSym "dfs")) (formatSchemaForm s 0)) ((or (= headSym "enum") (= headSym "dfe")) (formatEnumForm s 0)) ((isDotAccess? s) (formatDotAccess s)) ((isListForm? s) (formatListForm s 0)) (else (formatCallBody s)))))) (_ (formatSexpr s 0)))

fn formatTopForm s: rd/SExpr -> String
  (mt s ((sexprList items) (if (listEmpty? items) "()" (let [(headSym (rd/sexprHead s))] (cond ((or (= headSym "df") (= headSym "fn")) (formatDefunForm s 0)) ((= headSym "match") (formatMatchForm s 0)) ((= headSym "module") (formatSexpr s 0)) ((or (= headSym "schema") (= headSym "dfs")) (formatSchemaForm s 0)) ((or (= headSym "enum") (= headSym "dfe")) (formatEnumForm s 0)) (else (formatIndented s)))))) (_ (formatSexpr s 0)))

fn printIndented forms: (List rd/SExpr) -> String
  (if (listEmpty? forms) "" (let [(strs (map (fn [(s rd/SExpr)] -> String (formatTopForm s)) forms))] (stringJoin strs "\n\n")))
