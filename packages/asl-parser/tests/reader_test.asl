(module asl-parser/reader-test
  :d "Execution driver for the self-hosted reader: parse, render and audit modules."
  :x [proj-parse proj-heads render-all closure-heads ClosureHeads]
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

(df tail-forms [(xs (List a/TopForm))] -> (List a/TopForm)
  :d "Drop the head of a top-form list."
  (option-or (list-tail xs) (list)))

(df err-text [(e a/ParseError)] -> String
  :d "A parse error as line:col: message, the shape the CLI reports."
  (str (string-from-int64 (.-line e)) ":" (string-from-int64 (.-col e)) ": "
       (.-msg e)))

(df proj-parse [(src String)] -> String
  :d "Project the module header and every declaration to flat text."
  (mt (a/parse src)
    ((err e) (err-text e))
    ((ok forms)
     (if (list-empty? forms)
       "none"
       (string-join (map (fn [(t a/TopForm)] -> String (proj-form t)) forms) "|")))))

(df proj-form [(t a/TopForm)] -> String
  :d "One form's projection line."
  (mt t
    ((a/top-module m) (proj-module m))
    ((a/top-schema s) (proj-schema s))
    ((a/top-enum e)   (proj-enum e))
    ((a/top-defun d)  (proj-defun d))))

(df proj-module [(m a/ModuleNode)] -> String
  :d "Module header projection: path, doc, counts."
  (str "module|" (.-path m) "|" (.-docstring m) "|"
       (string-from-int64 (list-length (.-exported m))) "|"
       (string-from-int64 (list-length (.-imports m))) "|"
       (string-from-int64 (list-length (.-defs m)))))

(df proj-schema [(s a/SchemaNode)] -> String
  :d "Schema projection: name, field count, json case."
  (let [(jc (mt (.-json-case s)
              ((some v) v)
              ((none)   "none")))]
    (str "schema|" (.-name s) "|"
         (string-from-int64 (list-length (.-fields s))) "|" jc)))

(df proj-enum [(e a/EnumNode)] -> String
  :d "Enum projection: name, case count."
  (str "enum|" (.-name e) "|"
       (string-from-int64 (list-length (.-cases e)))))

(df proj-defun [(d a/DefunNode)] -> String
  :d "Defun projection: name, effect, params, return, exported."
  (str "defun|" (.-name d) "|"
       (if (.-effect d) "T" "F") "|"
       (string-from-int64 (list-length (.-params d))) "|"
       (.-ret-type d) "|"
       (if (.-is-exported d) "T" "F")))

(df proj-heads [(src String)] -> String
  :d "Project the dialect-sensitive fields for head-equality."
  (mt (a/parse src)
    ((err e) (err-text e))
    ((ok forms)
     (str (mt (list-head forms)
            ((some t) (mt t
                        ((a/top-module mn) (proj-module-heads mn))
                        ((a/top-schema _)  "")
                        ((a/top-enum _)    "")
                        ((a/top-defun _)   "")))
            ((none) ""))
          (head-decls (tail-forms forms))))))

(df proj-module-heads [(mn a/ModuleNode)] -> String
  :d "The module header's dialect-sensitive projection."
  (str (.-docstring mn) "|"
       (string-join (.-exported mn) ",") "|"
       (string-join (map (fn [(p (Pair String String))] -> String
                           (str (.-first p) ":" (.-second p)))
                         (.-imports mn))
                    ",")))

(df head-decls [(forms (List a/TopForm))] -> String
  :d "Per-declaration head projections, each with a leading pipe."
  (if (list-empty? forms)
    ""
    (str "|" (string-join (map (fn [(t a/TopForm)] -> String (head-decl t)) forms)
                          "|"))))

(df head-decl [(t a/TopForm)] -> String
  :d "One declaration's dialect-sensitive projection."
  (mt t
    ((a/top-module _) "module")
    ((a/top-schema s)
     (str "schema|" (.-name s) "|"
          (string-join (map (fn [(f a/AstField)] -> String
                                (str (.-name f) ":" (.-type f) ":" (.-docstring f)))
                            (.-fields s))
                       ",")
          "|" (mt (.-json-case s)
                ((some v) v)
                ((none)   "none"))))
    ((a/top-enum e)
     (str "enum|" (.-name e) "|"
          (string-join (map (fn [(c a/EnumCase)] -> String
                                (str (.-name c) ":" (.-docstring c)))
                            (.-cases e))
                       ",")))
    ((a/top-defun d)
     (str "defun|" (.-name d) "|"
          (if (.-effect d) "T" "F") "|"
          (string-from-int64 (list-length (.-params d))) "|"
          (.-ret-type d) "|" (.-docstring d) "|"
          (string-join (map (fn [(b rd/SExpr)] -> String (rd/render-sexpr b))
                            (.-body d))
                       " ")))))

(df render-all [(src String)] -> (Result String a/ParseError)
  :d "Parse and render every top form, joined by newlines."
  (let [(forms (try (a/parse src)))]
    (ok (string-join (map (fn [(t a/TopForm)] -> String (a/render-node t)) forms)
                     "\n"))))

"Closure walker: classification mirrors the grammar's `call` rule, so only a
head the query could capture is bucketed, and only expression positions are
ever walked; patterns and binders contribute nothing."

(df tail-exprs [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "The SExpr list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df sexpr-items [(s rd/SExpr)] -> (List rd/SExpr)
  :d "The elements of a list or vector SExpr; empty for an atom."
  (mt s
    ((rd/sexpr-list items) items)
    ((rd/sexpr-vect items) items)
    ((rd/sexpr-atom _)     (list))))

(df nth-expr [(items (List rd/SExpr)) (i Int64)] -> rd/SExpr
  :d "The i-th element of an SExpr list, or an empty atom."
  (mt (list-get items i)
    ((some s) s)
    ((none)   (rd/make-atom ""))))

(df first-item [(items (List rd/SExpr))] -> rd/SExpr
  :d "The head element, or an empty atom."
  (mt (list-head items)
    ((some s) s)
    ((none)   (rd/make-atom ""))))

(df first-char [(s String)] -> String
  :d "The first character of a string, or the empty string."
  (mt (string-slice s 0 1)
    ((some c) c)
    ((none)   "")))

(df chars-in? [(allowed String) (s String)] -> Bool
  :d "True when every character of s appears in allowed."
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (string-contains? allowed c)))
        true
        (string-chars s)))

(df drop-marker [(s String)] -> String
  :d "The ident without a trailing ? or ! marker."
  (let [(n (string-length s))]
    (cond
      ((<= n 0) s)
      ((or (string-ends-with? s "?") (string-ends-with? s "!"))
       (option-or (string-slice s 0 (- n 1)) ""))
      (:else s))))

(df kebab-ident? [(s String)] -> Bool
  :d "True for the grammar's ident shape: lowercase, digits, hyphens, markers."
  (let [(core (drop-marker s))]
    (and (not (string-empty? core))
         (and (string-contains? "abcdefghijklmnopqrstuvwxyz" (first-char core))
              (chars-in? "abcdefghijklmnopqrstuvwxyz0123456789-" core)))))

(df kw-head? [(h String)] -> Bool
  :d "True for a keyword-headed item: ctor keys, :else and the like."
  (= (first-char h) ":"))

(df dot-head? [(h String)] -> Bool
  :d "True for a field access head like .-x."
  (= (first-char h) "."))

(df upper-tail? [(h String)] -> Bool
  :d "True when the final slash segment starts uppercase: the qualified_type shape."
  (let [(s (last-of (string-split h "/")))]
    (and (not (string-empty? s))
         (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (first-char s)))))

(df slash-head? [(h String)] -> Bool
  :d "True for a qualified spelling: an alias and member, both non-empty.

  The division operator alone is `/` with nothing before the slash, so it is
  an operator head, never a qualified name."
  (let [(segs (string-split h "/"))]
    (and (> (list-length segs) 1)
         (not (string-empty? (last-of segs))))))

(df last-of [(xs (List String))] -> String
  :d "The final element of a list, or the empty string."
  (mt (list-head (list-reverse xs))
    ((some s) s)
    ((none)   "")))

(df pascal-head? [(h String)] -> Bool
  :d "True for a record-ctor head: the type_name shape."
  (and (not (string-empty? h))
       (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (first-char h))))

(df op-head? [(h String)] -> Bool
  :d "True for the operator set the grammar's call rule admits."
  (or (= h "=") (or (= h "+") (or (= h "-") (or (= h "*") (or (= h "/")
      (or (= h "<") (or (= h ">") (or (= h "<=") (or (= h ">=") (= h "!=")))))))))))

(df ctor-head? [(h String)] -> Bool
  :d "True for the constructor_call heads, which the query never captures."
  (or (= h "ok") (or (= h "err") (or (= h "some") (or (= h "none")
      (or (= h "pair") (= h "list")))))))

(df c-call [(st CState) (h String)] -> CState
  :d "Record a call head."
  (CState :work (.-work st) :calls (list-cons h (.-calls st))
          :defs (.-defs st) :qualified (.-qualified st)))

(df c-qual [(st CState) (h String)] -> CState
  :d "Record a qualified callee, owned by the checker's rule 9."
  (CState :work (.-work st) :calls (.-calls st)
          :defs (.-defs st) :qualified (list-cons h (.-qualified st))))

(df c-def [(st CState) (h String)] -> CState
  :d "Record a local definition."
  (CState :work (.-work st) :calls (.-calls st)
          :defs (list-cons h (.-defs st)) :qualified (.-qualified st)))

(df c-enqueue-many [(st CState) (xs (List rd/SExpr))] -> CState
  :d "Push SExprs onto the work list to be classified as expressions."
  (CState :work (list-append xs (.-work st)) :calls (.-calls st)
          :defs (.-defs st) :qualified (.-qualified st)))

(df c-walk-tails [(st CState) (items (List rd/SExpr))] -> CState
  :d "Walk one expr list's argument tails; the head is never walked."
  (c-enqueue-many st (tail-exprs items)))

(df c-walk-arms [(st CState) (arms (List rd/SExpr))] -> CState
  :d "Walk every match arm's body, skipping the pattern in each."
  (fold (fn [(acc CState) (arm rd/SExpr)] -> CState
          (c-enqueue-many acc (tail-exprs (sexpr-items arm))))
        st
        arms))

(df c-walk-clauses [(st CState) (cls (List rd/SExpr))] -> CState
  :d "Walk every cond clause element; a keyword head is a no-op atom."
  (fold (fn [(acc CState) (cl rd/SExpr)] -> CState
          (c-enqueue-many acc (sexpr-items cl)))
        st
        cls))

(df c-walk-bindings [(st CState) (v rd/SExpr)] -> CState
  :d "Walk every let binding's value, skipping the binder name."
  (fold (fn [(acc CState) (b rd/SExpr)] -> CState
          (c-enqueue-many acc (tail-exprs (sexpr-items b))))
        st
        (sexpr-items v)))

(df fn-body [(rest (List rd/SExpr))] -> (List rd/SExpr)
  :d "The body of a fn form: past the optional !, params vector and -> type."
  (let [(r1 (if (is-head-text rest "!") (tail-exprs rest) rest))
        (r2 (if (rd/is-vect? (first-item r1)) (tail-exprs r1) r1))
        (r3 (if (is-head-text r2 "->") (tail-exprs (tail-exprs r2)) r2))]
    r3))

(df is-head-text [(items (List rd/SExpr)) (t String)] -> Bool
  :d "True when an SExpr list's head atom is exactly t."
  (= (rd/sexpr-head (first-item items)) t))

(df c-match [(st CState) (items (List rd/SExpr))] -> CState
  :d "match: walk the subject and each arm body; arm patterns are never walked."
  (c-walk-arms (c-enqueue-many st (list (nth-expr items 1)))
               (tail-exprs (tail-exprs items))))

(df c-cond [(st CState) (items (List rd/SExpr))] -> CState
  :d "cond: walk every clause element; conditions are expressions too."
  (c-walk-clauses st (tail-exprs items)))

(df c-let [(st CState) (items (List rd/SExpr))] -> CState
  :d "let: walk binding values and the body; binder names are never walked."
  (c-enqueue-many (c-walk-bindings st (nth-expr items 1))
                  (tail-exprs (tail-exprs items))))

(df c-fn [(st CState) (items (List rd/SExpr))] -> CState
  :d "fn: walk the body only; params and return type are never expressions."
  (c-enqueue-many st (fn-body (tail-exprs items))))

(df c-atomic-head [(st CState) (h String) (items (List rd/SExpr))] -> CState
  :d "Classify one atom-headed expr list under the grammar's productions."
  (cond
    ((kw-head? h)         st)
    ((= h "match")        (c-match st items))
    ((= h "cond")         (c-cond st items))
    ((= h "let")          (c-let st items))
    ((= h "fn")           (c-fn st items))
    ((or (= h "try") (= h "if")) (c-walk-tails st items))
    ((ctor-head? h)       (c-walk-tails st items))
    ((dot-head? h)        (c-walk-tails st items))
    ((slash-head? h)      (if (upper-tail? h)
                            (c-walk-tails st items)
                            (c-walk-tails (c-qual st h) items)))
    ((pascal-head? h)     (c-walk-tails st items))
    ((or (or (kebab-ident? h) (op-head? h)) (= h "cons")) (c-walk-tails (c-call st h) items))
    (:else                (c-walk-tails st items))))

(df c-list [(st CState) (items (List rd/SExpr))] -> CState
  :d "Classify one expr list; a list-headed list walks head and args as exprs."
  (if (list-empty? items)
    st
    (let [(h0 (rd/sexpr-head (first-item items)))]
      (if (or (rd/is-list? (first-item items)) (rd/is-vect? (first-item items)))
        (c-walk-tails (c-enqueue-many st (list (first-item items))) items)
        (c-atomic-head st h0 items)))))

(df c-classify [(st CState) (s rd/SExpr)] -> CState
  :d "One work item: atoms and vectors are no-ops; a list is classified."
  (mt s
    ((rd/sexpr-atom _) st)
    ((rd/sexpr-vect _) st)
    ((rd/sexpr-list items) (c-list st items))))

(df c-pop [(st CState)] -> CState
  :d "The state with the head work item removed."
  (CState :work (tail-exprs (.-work st)) :calls (.-calls st)
          :defs (.-defs st) :qualified (.-qualified st)))

(df c-tick [(st CState) (n Int64)] -> CState
  :d "One work-list step: classify the head item and enqueue its children."
  (mt (list-head (.-work st))
    ((some item) (c-classify (c-pop st) item))
    ((none)      st)))

(df c-run [(st CState) (budget Int64)] -> CState
  :d "Run classification in doubling batches until the work list drains.

  The batch size doubles because a tree's node count is not known in advance and
  recursion is then O(log n) in the total rather than O(depth) per node."
  (if (list-empty? (.-work st))
    st
    (let [(batch (range 0 budget))
          (stepped (fold c-tick st batch))]
      (mt (list-empty? (.-work stepped))
        (true stepped)
        (false (c-run stepped (+ budget budget)))))))

(df c-top [(st CState) (t a/TopForm)] -> CState
  :d "One top form: defun bodies are walked, enum case names are definitions."
  (mt t
    ((a/top-module _) st)
    ((a/top-schema _) st)
    ((a/top-enum e)
     (fold (fn [(acc CState) (c a/EnumCase)] -> CState (c-def acc (.-name c)))
           st
           (.-cases e)))
    ((a/top-defun d)
     (c-enqueue-many (c-def st (.-name d)) (.-body d)))))

(df closure-heads [(src String)] -> (Result ClosureHeads a/ParseError)
  :d "Classify call heads, local definitions and qualified heads in a source."
  (mt (a/parse src)
    ((err e) (err e))
    ((ok forms)
     (let [(done (c-run (fold c-top
                              (CState :work (list) :calls (list)
                                      :defs (list) :qualified (list))
                              forms)
                        64))]
       (ok (ClosureHeads :calls (list-reverse (.-calls done))
                         :defs (list-reverse (.-defs done))
                         :qualified (list-reverse (.-qualified done))))))))
