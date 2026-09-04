(module asl-codegen/expr
  :d "Expression and pattern lowering to Rust expressions."
  :x [emit-expr
      emit-atom
      emit-pattern
      is-ident?
      slice-str-or]
  :i [(reader :a rd) (mangle :a m) (builtins :a b) (rtypes :a cg-ty)])

(df slice-str-or [(s String) (start Int64) (end Int64) (def String)] -> String
  :d "Safe string slice."
  (option-or (string-slice s start end) def))

(df is-ident? [(s String)] -> Bool
  :d "True if string represents a simple variable identifier suitable for cloning."
  (let [(len (string-length s))]
    (if (<= len 0)
        false
        (let [(first (slice-str-or s 0 1 ""))]
          (and (not (= first "\""))
               (and (not (= first "("))
                    (and (not (= first "{"))
                         (and (not (= first "["))
                              (and (not (string-contains? s " "))
                                   (and (not (string-contains? s "."))
                                        (not (string-contains? s "::"))))))))))))

(df escape-raw-string [(s String)] -> String
  :d "Escapes raw control characters in string literals."
  (let [(s1 (string-replace s "\n" "\\n"))
        (s2 (string-replace s1 "\r" "\\r"))
        (s3 (string-replace s2 "\t" "\\t"))]
    s3))

(df emit-atom [(s String) (aliases (Map String String))] -> String
  :d "Emits a terminal atom into a Rust expression."
  (cond
    ((= s "true") "true")
    ((= s "false") "false")
    ((or (= s "nil") (= s "()")) "()")
    ((string-starts-with? s "\"")
     (str (escape-raw-string s) ".to_string()"))
    ((and (string-starts-with? s "-") (> (string-length s) 1))
     (str "(" s ")"))
    ((string-contains? s "/")
     (let [(parts (string-split s "/"))
           (alias (option-or (list-get parts 0) ""))
           (member (option-or (list-get parts 1) ""))
           (mod-opt (map-get aliases alias))]
       (mt mod-opt
         ((some mpath) (str "crate::" (m/rust-mod-name mpath) "::" (m/mangle-ident member)))
         ((none) (str (m/mangle-ident alias) "::" (m/mangle-ident member))))))
    ((= s "none") "None")
    ((= s "ok") "Ok")
    ((= s "err") "Err")
    ((= s "some") "Some")
    ((= s "not-found") "rt::IoError::NotFound")
    ((= s "permission-denied") "rt::IoError::PermissionDenied")
    ((= s "already-exists") "rt::IoError::AlreadyExists")
    ((= s "invalid-path") "rt::IoError::InvalidPath")
    ((= s "interrupted") "rt::IoError::Interrupted")
    ((= s "other") "rt::IoError::Other")
    (:else (m/mangle-ident s))))

(df get-atom-str [(e rd/SExpr)] -> String
  :d "Extracts string value from an atom SExpr or returns empty."
  (mt e
    ((rd/sexpr-atom v) v)
    ((rd/sexpr-list _) "")
    ((rd/sexpr-vect _) "")))

(df nth-atom [(items (List rd/SExpr)) (idx I64)] -> String
  :d "Extracts atom string from items at index or empty string."
  (get-atom-str (option-or (list-get items idx) (rd/sexpr-atom ""))))

(df slice-from-1 [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Slices items starting from index 1."
  (if (> (list-length items) 1)
      (option-or (list-slice items 1 (list-length items)) (list))
      (list)))

(df slice-tail [(items (List rd/SExpr)) (start I64)] -> (List rd/SExpr)
  :d "Slices list from start index or returns empty list."
  (if (> (list-length items) start)
      (option-or (list-slice items start (list-length items)) (list))
      (list)))

(df emit-fn-param [(p rd/SExpr)] -> String
  :d "Emits closure parameter name."
  (mt p
    ((rd/sexpr-vect p-items) (m/mangle-ident (nth-atom p-items 0)))
    ((rd/sexpr-list p-items) (m/mangle-ident (nth-atom p-items 0)))
    ((rd/sexpr-atom v) (m/mangle-ident v))))

(df emit-pattern [(p rd/SExpr)] -> String
  :d "Lowers a match pattern to Rust match syntax."
  (mt p
    ((rd/sexpr-atom v)
     (cond
       ((= v "_") "_")
       ((= v "none") "None")
       ((= v "true") "true")
       ((= v "false") "false")
       ((string-starts-with? v "\"") (escape-raw-string v))
       (:else (m/mangle-ident v))))
    ((rd/sexpr-vect items)
     (if (<= (list-length items) 0)
         "[]"
         (str "[" (string-join (map emit-pattern items) ", ") "]")))
    ((rd/sexpr-list items)
     (if (<= (list-length items) 0)
         "()"
         (let [(head (nth-atom items 0))]
           (cond
             ((= head "ok")
              (str "Ok(" (emit-pattern (option-or (list-get items 1) (rd/sexpr-atom "_"))) ")"))
             ((= head "err")
              (str "Err(" (emit-pattern (option-or (list-get items 1) (rd/sexpr-atom "_"))) ")"))
             ((= head "some")
              (str "Some(" (emit-pattern (option-or (list-get items 1) (rd/sexpr-atom "_"))) ")"))
             ((= head "none") "None")
             ((= head "pair")
              (str "(" (emit-pattern (option-or (list-get items 1) (rd/sexpr-atom "_")))
                   ", " (emit-pattern (option-or (list-get items 2) (rd/sexpr-atom "_"))) ")"))
             ((= head "list") "[]")
             ((= head "cons")
              (str "[" (emit-pattern (option-or (list-get items 1) (rd/sexpr-atom "_")))
                   ", " (emit-pattern (option-or (list-get items 2) (rd/sexpr-atom "_"))) " @ ..]"))
             (:else
              (let [(p-head (m/pascal-ident head))
                    (rest (if (> (list-length items) 1)
                              (list-tail items)
                              (none)))]
                (mt rest
                  ((none) p-head)
                  ((some r-items)
                   (if (<= (list-length r-items) 0)
                       p-head
                       (str p-head "(" (string-join (map emit-pattern r-items) ", ") ")"))))))))))))

(df emit-body-seq [(body (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Emits a sequence of body expressions."
  (let [(len (list-length body))]
    (if (<= len 0)
        "()"
        (if (= len 1)
            (emit-expr (option-or (list-get body 0) (rd/sexpr-atom "()")) aliases)
            (let [(stmts (map (fn [(e rd/SExpr)] -> String
                                (str (emit-expr e aliases) "; "))
                              body))
                  (last-idx (- len 1))
                  (last-expr (emit-expr (option-or (list-get body last-idx) (rd/sexpr-atom "()")) aliases))
                  (prior-stmts (list-slice stmts 0 last-idx))]
              (mt prior-stmts
                ((some ps) (str (string-join ps "") last-expr))
                ((none) last-expr)))))))

(df emit-let [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a let form to Rust block expression."
  (let [(bindings-node (option-or (list-get items 1) (rd/sexpr-vect (list))))
        (body (slice-tail items 2))
        (bind-list (mt bindings-node
                     ((rd/sexpr-vect bs) bs)
                     ((rd/sexpr-list bs) bs)
                     ((rd/sexpr-atom _) (list))))
        (let-stmts (map (fn [(b rd/SExpr)] -> String
                          (let [(pair (mt b
                                        ((rd/sexpr-vect ps) ps)
                                        ((rd/sexpr-list ps) ps)
                                        ((rd/sexpr-atom _) (list))))]
                            (if (>= (list-length pair) 2)
                                (let [(b-name (m/mangle-ident (nth-atom pair 0)))
                                      (b-val (emit-expr (option-or (list-get pair 1) (rd/sexpr-atom "()")) aliases))]
                                  (str "let " b-name " = " b-val "; "))
                                "")))
                        bind-list))
        (body-str (emit-body-seq body aliases))]
    (str "{ " (string-join let-stmts "") body-str " }")))

(df emit-if [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers an if form to Rust if-else expression."
  (let [(c (emit-expr (option-or (list-get items 1) (rd/sexpr-atom "false")) aliases))
        (th (emit-expr (option-or (list-get items 2) (rd/sexpr-atom "()")) aliases))
        (el (emit-expr (option-or (list-get items 3) (rd/sexpr-atom "()")) aliases))]
    (str "if " c " { " th " } else { " el " }")))

(df emit-cond-clause [(c rd/SExpr) (is-first Bool) (aliases (Map String String))] -> String
  :d "Emits a single cond clause."
  (mt c
    ((rd/sexpr-list c-items)
     (let [(head (nth-atom c-items 0))
           (body-tail (slice-from-1 c-items))]
       (if (or (= head ":else") (= head "else"))
           (str "} else { " (emit-body-seq body-tail aliases) " }")
           (let [(cond-expr (emit-expr (option-or (list-get c-items 0) (rd/sexpr-atom "false")) aliases))
                 (prefix (if is-first "if " "} else if "))]
             (str prefix cond-expr " { " (emit-body-seq body-tail aliases) " ")))))
    ((rd/sexpr-vect c-items)
     (emit-cond-clause (rd/sexpr-list c-items) is-first aliases))
    ((rd/sexpr-atom _) "")))

(df emit-cond [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a cond form to Rust if-else if-else expression."
  (let [(clauses (slice-from-1 items))]
    (if (<= (list-length clauses) 0)
        "()"
        (let [(c0 (emit-cond-clause (option-or (list-get clauses 0) (rd/sexpr-atom "")) true aliases))
              (rest-clauses (slice-from-1 clauses))
              (rest-parts (map (fn [(c rd/SExpr)] -> String
                                 (emit-cond-clause c false aliases))
                               rest-clauses))]
          (str c0 (string-join rest-parts " "))))))

(df emit-match [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a match or mt form to Rust match expression."
  (let [(subj (emit-expr (option-or (list-get items 1) (rd/sexpr-atom "()")) aliases))
        (subj-arg (if (is-ident? subj) (str subj ".clone()") subj))
        (arms (slice-tail items 2))
        (arm-strs (map (fn [(arm rd/SExpr)] -> String
                         (mt arm
                           ((rd/sexpr-list a-items)
                            (let [(pat-str (emit-pattern (option-or (list-get a-items 0) (rd/sexpr-atom "_"))))
                                  (body (slice-from-1 a-items))]
                              (str pat-str " => { " (emit-body-seq body aliases) " },")))
                           ((rd/sexpr-vect a-items)
                            (emit-match (list (rd/sexpr-atom "mt") (option-or (list-get items 1) (rd/sexpr-atom "()")) arm) aliases))
                           ((rd/sexpr-atom _) "")))
                       arms))]
    (str "match " subj-arg " { " (string-join arm-strs " ") " }")))

(df emit-try [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a try form to Rust ? propagation."
  (let [(inner (emit-expr (option-or (list-get items 1) (rd/sexpr-atom "()")) aliases))]
    (str "(" inner ")?")))

(df emit-fn [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers an anonymous lambda fn to Rust closure."
  (let [(params-node (option-or (list-get items 1) (rd/sexpr-vect (list))))
        (p-list (mt params-node
                  ((rd/sexpr-vect ps) ps)
                  ((rd/sexpr-list ps) ps)
                  ((rd/sexpr-atom _) (list))))
        (p-strs (map emit-fn-param p-list))
        (body (if (> (list-length items) 2)
                  (let [(tail (slice-tail items 2))
                        (first-head (nth-atom tail 0))]
                    (if (and (= first-head "->") (> (list-length tail) 2))
                        (slice-tail tail 2)
                        tail))
                  (list)))
        (body-str (emit-body-seq body aliases))]
    (str "|" (string-join p-strs ", ") "| { " body-str " }")))

(df emit-record-init [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Emits struct constructor initialization: (Record :f1 v1 :f2 v2 ...)."
  (let [(rec-name (nth-atom items 0))
        (clean-rec (m/pascal-ident rec-name))
        (len (list-length items))]
    (let [(inits (range 0 (/ (- len 1) 2)))
          (field-strs (map (fn [(idx Int64)] -> String
                             (let [(k-pos (+ 1 (* idx 2)))
                                   (v-pos (+ 2 (* idx 2)))
                                   (k-atom (nth-atom items k-pos))
                                   (k-clean (if (string-starts-with? k-atom ":")
                                                (slice-str-or k-atom 1 (string-length k-atom) k-atom)
                                                k-atom))
                                   (v-node (option-or (list-get items v-pos) (rd/sexpr-atom "()")))
                                   (v-val (emit-expr v-node aliases))]
                               (str (m/mangle-ident k-clean) ": " v-val)))
                           inits))]
      (str clean-rec " { " (string-join field-strs ", ") " }"))))

(df emit-call [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a general call form or builtin."
  (let [(head (nth-atom items 0))
        (raw-args (slice-from-1 items))
        (args (map (fn [(a rd/SExpr)] -> String
                     (let [(arg-str (emit-expr a aliases))]
                       (if (is-ident? arg-str)
                           (str arg-str ".clone()")
                           arg-str)))
                   raw-args))]
    (cond
      ((string-starts-with? head ".-")
       (let [(field (slice-str-or head 2 (string-length head) ""))
             (target (option-or (list-get args 0) "()"))]
         (cond
           ((= field "first") (str target ".0.clone()"))
           ((= field "second") (str target ".1.clone()"))
           (:else (str target "." (m/mangle-ident field) ".clone()")))))
      ((is-some? (b/builtin-template head))
       (option-or (b/render-builtin head args) ""))
      ((let [(c0 (slice-str-or head 0 1 ""))]
         (and (>= (string-length head) 2)
              (string-starts-with? head ":")))
       (emit-record-init items aliases))
      ((let [(c0 (slice-str-or head 0 1 ""))]
         (and (>= (string-length head) 1)
              (and (= (string-upper c0) c0)
                   (and (not (= c0 "_"))
                        (not (string-contains? head "/"))))))
       (if (and (> (list-length items) 1)
                (string-starts-with? (nth-atom items 1) ":"))
           (emit-record-init items aliases)
           (str (m/pascal-ident head) "(" (string-join args ", ") ")")))
      (:else
       (let [(h-str (emit-atom head aliases))]
         (str h-str "(" (string-join args ", ") ")"))))))

(df emit-expr [(e rd/SExpr) (aliases (Map String String))] -> String
  :d "Lowers an arbitrary ASL S-Expression into a Rust expression."
  (mt e
    ((rd/sexpr-atom v) (emit-atom v aliases))
    ((rd/sexpr-vect items)
     (str "vec![" (string-join (map (fn [(it rd/SExpr)] -> String (emit-expr it aliases)) items) ", ") "]"))
    ((rd/sexpr-list items)
     (if (<= (list-length items) 0)
         "()"
         (let [(head (nth-atom items 0))]
           (cond
             ((= head "let") (emit-let items aliases))
             ((= head "if") (emit-if items aliases))
             ((= head "cond") (emit-cond items aliases))
             ((or (= head "match") (= head "mt")) (emit-match items aliases))
             ((= head "try") (emit-try items aliases))
             ((= head "fn") (emit-fn items aliases))
             (:else (emit-call items aliases))))))))
