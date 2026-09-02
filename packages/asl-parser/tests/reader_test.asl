(module asl-parser/reader-test
  :d "Execution driver for the self-hosted reader: parse and render modules."
  :x [proj-parse proj-heads render-all]
  :i [(ast :a a) (reader :a rd)])

(df tail-forms [(xs (List a/TopForm))] -> (List a/TopForm)
  :d "Drop the head of a top-form list."
  (mt (list-tail xs)
    ((some r) r)
    ((none)   (list))))

(df proj-parse [(src String)] -> String
  :d "Project the module header and every declaration to flat text."
  (let [(forms (a/parse src))]
    (str (mt (list-head forms)
           ((some t) (proj-form t))
           ((none)   "none"))
         (proj-rest (tail-forms forms)))))

(df proj-rest [(forms (List a/TopForm))] -> String
  :d "Project remaining forms, each joined with a leading pipe."
  (mt (list-head forms)
    ((some t)
     (let [(rest (tail-forms forms))]
       (if (list-empty? rest)
         (str "|" (proj-form t))
         (str "|" (proj-form t) (proj-rest rest)))))
    ((none) "")))

(df proj-form [(t a/TopForm)] -> String
  :d "One form's projection line."
  (mt t
    ((a/top-module m) (proj-module m))
    ((a/top-schema s) (proj-schema s))
    ((a/top-enum e)   (proj-enum e))
    ((a/top-defun d)  (proj-defun d))))

(df proj-module [(m a/ModuleNode)] -> String
  :d "Module header projection: doc, counts."
  (str "module|" (.-docstring m) "|"
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
  (let [(forms (a/parse src))
        (m (mt (list-head forms)
             ((some t) (mt t
                         ((a/top-module mn) (some mn))
                         ((a/top-schema _)  (none))
                         ((a/top-enum _)    (none))
                         ((a/top-defun _)   (none))))
             ((none) (none))))]
    (str (mt m
           ((some mn)
            (str (.-docstring mn) "|"
                 (string-join (.-exported mn) ",") "|"
                 (string-join (map (fn [(p (Pair String String))] -> String
                                     (str (.-first p) ":" (.-second p)))
                                   (.-imports mn))
                              ",")))
           ((none) ""))
         (head-decls (tail-forms forms)))))

(df head-decls [(forms (List a/TopForm))] -> String
  :d "Per-declaration head projections joined by a pipe."
  (mt (list-head forms)
    ((some t) (str "|" (head-decl t) (head-decls (tail-forms forms))))
    ((none) "")))

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

(df render-all [(src String)] -> String
  :d "Parse and render every top form, joined by newlines."
  (string-join (map (fn [(t a/TopForm)] -> String (a/render-node t))
                    (a/parse src))
               "\n"))
