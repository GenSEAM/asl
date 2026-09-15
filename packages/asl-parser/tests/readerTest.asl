(module asl-parser/readerTest
  :d "Execution driver for the self-hosted reader: parse, render and audit modules."
  :x [projParse projHeads renderAll closureHeads ClosureHeads runTests]
  :i [(ast :a a) (reader :a rd)])

(dfs ClosureHeads
  (:f calls (List String) "Call heads appearing in expression position")
  (:f defs (List String) "Local definitions: defun names and enum case names")
  (:f qualified (List String) "Qualified callees, resolved in another module"))

(dfs CState
  (:f work (List rd/SExpr) "Pending expressions to classify, head first")
  (:f calls (List String) "Call heads, kept reversed for cheap cons")
  (:f defs (List String) "Definitions, kept reversed")
  (:f qualified (List String) "Qualified callees, kept reversed"))

(df tailForms [(xs (List a/TopForm))] -> (List a/TopForm)
  :d "Drop the head of a top-form list."
  (option-or (list-tail xs) (list)))

(df errText [(e a/ParseError)] -> String
  :d "A parse error as line:col: message, the shape the CLI reports."
  (str (string-from-int64 (.-line e)) ":" (string-from-int64 (.-col e)) ": "
       (.-msg e)))

(df projParse [(src String)] -> String
  :d "Project the module header and every declaration to flat text."
  (mt (a/parse src)
    ((err e) (errText e))
    ((ok forms)
     (if (list-empty? forms)
       "none"
       (string-join (map (fn [(t a/TopForm)] -> String (projForm t)) forms) "|")))))

(df projForm [(t a/TopForm)] -> String
  :d "One form's projection line."
  (mt t
    ((a/topModule m) (projModule m))
    ((a/topSchema s) (projSchema s))
    ((a/topEnum e)   (projEnum e))
    ((a/topDefun d)  (projDefun d))))

(df projModule [(m a/ModuleNode)] -> String
  :d "Module header projection: path, doc, counts."
  (str "module|" (.-path m) "|" (.-docstring m) "|"
       (string-from-int64 (list-length (.-exported m))) "|"
       (string-from-int64 (list-length (.-imports m))) "|"
       (string-from-int64 (list-length (.-defs m)))))

(df projSchema [(s a/SchemaNode)] -> String
  :d "Schema projection: name, field count, json case."
  (let [(jc (mt (.-jsonCase s)
              ((some v) v)
              ((none)   "none")))]
    (str "schema|" (.-name s) "|"
         (string-from-int64 (list-length (.-fields s))) "|" jc)))

(df projEnum [(e a/EnumNode)] -> String
  :d "Enum projection: name, case count."
  (str "enum|" (.-name e) "|"
       (string-from-int64 (list-length (.-cases e)))))

(df projDefun [(d a/DefunNode)] -> String
  :d "Defun projection: name, effect, params, return, exported."
  (str "defun|" (.-name d) "|"
       (if (.-effect d) "T" "F") "|"
       (string-from-int64 (list-length (.-params d))) "|"
       (.-retType d) "|"
       (if (.-isExported d) "T" "F")))

(df projHeads [(src String)] -> String
  :d "Project the dialect-sensitive fields for head-equality."
  (mt (a/parse src)
    ((err e) (errText e))
    ((ok forms)
     (str (mt (list-head forms)
            ((some t) (mt t
                        ((a/topModule mn) (projModuleHeads mn))
                        ((a/topSchema _)  "")
                        ((a/topEnum _)    "")
                        ((a/topDefun _)   "")))
            ((none) ""))
          (headDecls (tailForms forms))))))

(df projModuleHeads [(mn a/ModuleNode)] -> String
  :d "The module header's dialect-sensitive projection."
  (str (.-docstring mn) "|"
       (string-join (.-exported mn) ",") "|"
       (string-join (map (fn [(p (Pair String String))] -> String
                           (str (.-first p) ":" (.-second p)))
                         (.-imports mn))
                    ",")))

(df headDecls [(forms (List a/TopForm))] -> String
  :d "Per-declaration head projections, each with a leading pipe."
  (if (list-empty? forms)
    ""
    (str "|" (string-join (map (fn [(t a/TopForm)] -> String (headDecl t)) forms)
                          "|"))))

(df headDecl [(t a/TopForm)] -> String
  :d "One declaration's dialect-sensitive projection."
  (mt t
    ((a/topModule _) "module")
    ((a/topSchema s)
     (str "schema|" (.-name s) "|"
          (string-join (map (fn [(f a/AstField)] -> String
                                (str (.-name f) ":" (.-type f) ":" (.-docstring f)))
                            (.-fields s))
                       ",")
          "|" (mt (.-jsonCase s)
                ((some v) v)
                ((none)   "none"))))
    ((a/topEnum e)
     (str "enum|" (.-name e) "|"
          (string-join (map (fn [(c a/EnumCase)] -> String
                                (str (.-name c) ":" (.-docstring c)))
                            (.-cases e))
                       ",")))
    ((a/topDefun d)
     (str "defun|" (.-name d) "|"
          (if (.-effect d) "T" "F") "|"
          (string-from-int64 (list-length (.-params d))) "|"
          (.-retType d) "|" (.-docstring d) "|"
          (string-join (map (fn [(b rd/SExpr)] -> String (rd/renderSexpr b))
                            (.-body d))
                       " ")))))

(df renderAll [(src String)] -> (Result String a/ParseError)
  :d "Parse and render every top form, joined by newlines."
  (let [(forms (try (a/parse src)))]
    (ok (string-join (map (fn [(t a/TopForm)] -> String (a/renderNode t)) forms)
                     "\n"))))

"Closure walker: classification mirrors the grammar's `call` rule, so only a
head the query could capture is bucketed, and only expression positions are
ever walked; patterns and binders contribute nothing."

(df tailExprs [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "The SExpr list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df sexprItems [(s rd/SExpr)] -> (List rd/SExpr)
  :d "The elements of a list or vector SExpr; empty for an atom."
  (mt s
    ((rd/sexprList items) items)
    ((rd/sexprVect items) items)
    ((rd/sexprAtom _)     (list))))

(df nthExpr [(items (List rd/SExpr)) (i Int64)] -> rd/SExpr
  :d "The i-th element of an SExpr list, or an empty atom."
  (mt (list-get items i)
    ((some s) s)
    ((none)   (rd/makeAtom ""))))

(df firstItem [(items (List rd/SExpr))] -> rd/SExpr
  :d "The head element, or an empty atom."
  (mt (list-head items)
    ((some s) s)
    ((none)   (rd/makeAtom ""))))

(df firstChar [(s String)] -> String
  :d "The first character of a string, or the empty string."
  (mt (string-slice s 0 1)
    ((some c) c)
    ((none)   "")))

(df charsIn? [(allowed String) (s String)] -> Bool
  :d "True when every character of s appears in allowed."
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (string-contains? allowed c)))
        true
        (string-chars s)))

(df dropMarker [(s String)] -> String
  :d "The ident without a trailing ? or ! marker."
  (let [(n (string-length s))]
    (cond
      ((<= n 0) s)
      ((or (string-ends-with? s "?") (string-ends-with? s "!"))
       (option-or (string-slice s 0 (- n 1)) ""))
      (:else s))))

(df kebabIdent? [(s String)] -> Bool
  :d "True for the grammar's ident shape: lowercase, digits, hyphens, markers."
  (let [(core (dropMarker s))]
    (and (not (string-empty? core))
         (and (string-contains? "abcdefghijklmnopqrstuvwxyz" (firstChar core))
              (charsIn? "abcdefghijklmnopqrstuvwxyz0123456789-" core)))))

(df kwHead? [(h String)] -> Bool
  :d "True for a keyword-headed item: ctor keys, :else and the like."
  (= (firstChar h) ":"))

(df dotHead? [(h String)] -> Bool
  :d "True for a field access head like .-x."
  (= (firstChar h) "."))

(df upperTail? [(h String)] -> Bool
  :d "True when the final slash segment starts uppercase: the qualified_type shape."
  (let [(s (lastOf (string-split h "/")))]
    (and (not (string-empty? s))
         (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (firstChar s)))))

(df slashHead? [(h String)] -> Bool
  :d "True for a qualified spelling: an alias and member, both non-empty.

  The division operator alone is `/` with nothing before the slash, so it is
  an operator head, never a qualified name."
  (let [(segs (string-split h "/"))]
    (and (> (list-length segs) 1)
         (not (string-empty? (lastOf segs))))))

(df lastOf [(xs (List String))] -> String
  :d "The final element of a list, or the empty string."
  (mt (list-head (list-reverse xs))
    ((some s) s)
    ((none)   "")))

(df pascalHead? [(h String)] -> Bool
  :d "True for a record-ctor head: the type_name shape."
  (and (not (string-empty? h))
       (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (firstChar h))))

(df opHead? [(h String)] -> Bool
  :d "True for the operator set the grammar's call rule admits."
  (or (= h "=") (or (= h "+") (or (= h "-") (or (= h "*") (or (= h "/")
      (or (= h "<") (or (= h ">") (or (= h "<=") (or (= h ">=") (= h "!=")))))))))))

(df ctorHead? [(h String)] -> Bool
  :d "True for the constructor_call heads, which the query never captures."
  (or (= h "ok") (or (= h "err") (or (= h "some") (or (= h "none")
      (or (= h "pair") (= h "list")))))))

(df cCall [(st CState) (h String)] -> CState
  :d "Record a call head."
  (CState :work (.-work st) :calls (list-cons h (.-calls st))
          :defs (.-defs st) :qualified (.-qualified st)))

(df cQual [(st CState) (h String)] -> CState
  :d "Record a qualified callee, owned by the checker's rule 9."
  (CState :work (.-work st) :calls (.-calls st)
          :defs (.-defs st) :qualified (list-cons h (.-qualified st))))

(df c-def [(st CState) (h String)] -> CState
  :d "Record a local definition."
  (CState :work (.-work st) :calls (.-calls st)
          :defs (list-cons h (.-defs st)) :qualified (.-qualified st)))

(df cEnqueueMany [(st CState) (xs (List rd/SExpr))] -> CState
  :d "Push SExprs onto the work list to be classified as expressions."
  (CState :work (list-append xs (.-work st)) :calls (.-calls st)
          :defs (.-defs st) :qualified (.-qualified st)))

(df cWalkTails [(st CState) (items (List rd/SExpr))] -> CState
  :d "Walk one expr list's argument tails; the head is never walked."
  (cEnqueueMany st (tailExprs items)))

(df cWalkArms [(st CState) (arms (List rd/SExpr))] -> CState
  :d "Walk every match arm's body, skipping the pattern in each."
  (fold (fn [(acc CState) (arm rd/SExpr)] -> CState
          (cEnqueueMany acc (tailExprs (sexprItems arm))))
        st
        arms))

(df cWalkClauses [(st CState) (cls (List rd/SExpr))] -> CState
  :d "Walk every cond clause element; a keyword head is a no-op atom."
  (fold (fn [(acc CState) (cl rd/SExpr)] -> CState
          (cEnqueueMany acc (sexprItems cl)))
        st
        cls))

(df cWalkBindings [(st CState) (v rd/SExpr)] -> CState
  :d "Walk every let binding's value, skipping the binder name."
  (fold (fn [(acc CState) (b rd/SExpr)] -> CState
          (cEnqueueMany acc (tailExprs (sexprItems b))))
        st
        (sexprItems v)))

(df fnBody [(rest (List rd/SExpr))] -> (List rd/SExpr)
  :d "The body of a fn form: past the optional !, params vector and -> type."
  (let [(r1 (if (isHeadText rest "!") (tailExprs rest) rest))
        (r2 (if (rd/isVect? (firstItem r1)) (tailExprs r1) r1))
        (r3 (if (isHeadText r2 "->") (tailExprs (tailExprs r2)) r2))]
    r3))

(df isHeadText [(items (List rd/SExpr)) (t String)] -> Bool
  :d "True when an SExpr list's head atom is exactly t."
  (= (rd/sexprHead (firstItem items)) t))

(df cMatch [(st CState) (items (List rd/SExpr))] -> CState
  :d "match: walk the subject and each arm body; arm patterns are never walked."
  (cWalkArms (cEnqueueMany st (list (nthExpr items 1)))
               (tailExprs (tailExprs items))))

(df cCond [(st CState) (items (List rd/SExpr))] -> CState
  :d "cond: walk every clause element; conditions are expressions too."
  (cWalkClauses st (tailExprs items)))

(df cLet [(st CState) (items (List rd/SExpr))] -> CState
  :d "let: walk binding values and the body; binder names are never walked."
  (cEnqueueMany (cWalkBindings st (nthExpr items 1))
                  (tailExprs (tailExprs items))))

(df cFn [(st CState) (items (List rd/SExpr))] -> CState
  :d "fn: walk the body only; params and return type are never expressions."
  (cEnqueueMany st (fnBody (tailExprs items))))

(df cAtomicHead [(st CState) (h String) (items (List rd/SExpr))] -> CState
  :d "Classify one atom-headed expr list under the grammar's productions."
  (cond
    ((kwHead? h)         st)
    ((= h "match")        (cMatch st items))
    ((= h "cond")         (cCond st items))
    ((= h "let")          (cLet st items))
    ((= h "fn")           (cFn st items))
    ((or (= h "try") (= h "if")) (cWalkTails st items))
    ((ctorHead? h)       (cWalkTails st items))
    ((dotHead? h)        (cWalkTails st items))
    ((slashHead? h)      (if (upperTail? h)
                            (cWalkTails st items)
                            (cWalkTails (cQual st h) items)))
    ((pascalHead? h)     (cWalkTails st items))
    ((or (or (kebabIdent? h) (opHead? h)) (= h "cons")) (cWalkTails (cCall st h) items))
    (:else                (cWalkTails st items))))

(df cList [(st CState) (items (List rd/SExpr))] -> CState
  :d "Classify one expr list; a list-headed list walks head and args as exprs."
  (if (list-empty? items)
    st
    (let [(h0 (rd/sexprHead (firstItem items)))]
      (if (or (rd/isList? (firstItem items)) (rd/isVect? (firstItem items)))
        (cWalkTails (cEnqueueMany st (list (firstItem items))) items)
        (cAtomicHead st h0 items)))))

(df cClassify [(st CState) (s rd/SExpr)] -> CState
  :d "One work item: atoms and vectors are no-ops; a list is classified."
  (mt s
    ((rd/sexprAtom _) st)
    ((rd/sexprVect _) st)
    ((rd/sexprList items) (cList st items))))

(df cPop [(st CState)] -> CState
  :d "The state with the head work item removed."
  (CState :work (tailExprs (.-work st)) :calls (.-calls st)
          :defs (.-defs st) :qualified (.-qualified st)))

(df cTick [(st CState) (n Int64)] -> CState
  :d "One work-list step: classify the head item and enqueue its children."
  (mt (list-head (.-work st))
    ((some item) (cClassify (cPop st) item))
    ((none)      st)))

(df cRun [(st CState) (budget Int64)] -> CState
  :d "Run classification in doubling batches until the work list drains.

  The batch size doubles because a tree's node count is not known in advance and
  recursion is then O(log n) in the total rather than O(depth) per node."
  (if (list-empty? (.-work st))
    st
    (let [(batch (range 0 budget))
          (stepped (fold cTick st batch))]
      (mt (list-empty? (.-work stepped))
        (true stepped)
        (false (cRun stepped (+ budget budget)))))))

(df cTop [(st CState) (t a/TopForm)] -> CState
  :d "One top form: defun bodies are walked, enum case names are definitions."
  (mt t
    ((a/topModule _) st)
    ((a/topSchema _) st)
    ((a/topEnum e)
     (fold (fn [(acc CState) (c a/EnumCase)] -> CState (c-def acc (.-name c)))
           st
           (.-cases e)))
    ((a/topDefun d)
     (cEnqueueMany (c-def st (.-name d)) (.-body d)))))

(df closureHeads [(src String)] -> (Result ClosureHeads a/ParseError)
  :d "Classify call heads, local definitions and qualified heads in a source."
  (mt (a/parse src)
    ((err e) (err e))
    ((ok forms)
     (let [(done (cRun (fold cTop
                              (CState :work (list) :calls (list)
                                      :defs (list) :qualified (list))
                              forms)
                        64))]
       (ok (ClosureHeads :calls (list-reverse (.-calls done))
                         :defs (list-reverse (.-defs done))
                         :qualified (list-reverse (.-qualified done))))))))

(df runTests [] -> Bool
  :d "Runs reader projection and closure tests"
  (let [(parsed (projParse "(module m :doc \"doc\") (df f [] -> Int64 1)"))
        (heads (projHeads "(module m :doc \"doc\") (df f [] -> Int64 1)"))
        (closed (closureHeads "(module m :doc \"doc\") (df f [] -> Int64 1)"))]
    (assert (string-contains? parsed "module|m|\"doc\"") "module projection")
    (assert (string-contains? parsed "defun|f|F|0|Int64|F") "defun projection")
    (assert (string-contains? heads "doc") "heads projection")
    (assert (mt closed ((ok _) true) ((err _) false)) "closure heads ok")
    true))
