(module asl-codegen/expr
  :d "Expression and pattern lowering to Rust expressions."
  :x [emit-expr
      emit-atom
      emit-pattern
      emit-body-seq
      is-ident?
      clone-if-ident
      resolve-qualified-case
      slice-str-or]
  :i [(reader :a rd) (mangle :a m) (builtins :a b) (rtypes :a cg-ty)])

(df slice-str-or [(s String) (start Int64) (end Int64) (def String)] -> String
  :d "Safe string slice."
  (option-or (string-slice s start end) def))

(df is-ident? [(s String)] -> Bool
  :d "True if string represents a simple variable identifier suitable for cloning."
  (let [(s-len (string-length s))]
    (if (<= s-len 0)
        false
        (let [(c0 (slice-str-or s 0 1 ""))]
          (and (not (string-contains? s " "))
               (and (not (string-contains? s "("))
                    (and (not (string-contains? s "{"))
                         (and (not (string-contains? s "["))
                              (and (not (string-contains? s "\""))
                                   (and (not (string-contains? s "."))
                                        (and (not (string-contains? s "::"))
                                             (or (and (>= c0 "a") (<= c0 "z"))
                                                 (or (and (>= c0 "A") (<= c0 "Z"))
                                                     (= c0 "_"))))))))))))))

(df clone-if-ident [(s String)] -> String
  :d "Appends .clone() if string is a bare identifier."
  (if (is-ident? s)
      (str s ".clone()")
      s))

(df any-true? [(flags (List Bool))] -> Bool
  :d "True if any boolean in list is true."
  (fold (fn [(acc Bool) (cur Bool)] (or acc cur)) false flags))

(df sexpr-to-list [(e rd/SExpr)] -> (List rd/SExpr)
  :d "Extracts items list from vect or list SExpr."
  (mt e
    ((rd/sexpr-vect items) items)
    ((rd/sexpr-list items) items)
    ((rd/sexpr-atom _) (list))))

(df case-call [(tgt String) (args (List String))] -> String
  :d "Formats an enum constructor or unit variant."
  (if (> (list-length args) 0)
      (str tgt "(" (string-join args ", ") ")")
      tgt))

(df format-call [(fn-name String) (args (List String))] -> String
  :d "Formats a function call with comma-separated arguments."
  (str fn-name "(" (string-join args ", ") ")"))

(df escape-raw-string [(s String)] -> String
  :d "Escapes raw control characters in string literals."
  (let [(s1 (string-replace s "\n" "\\n"))
        (s2 (string-replace s1 "\r" "\\r"))
        (s3 (string-replace s2 "\t" "\\t"))]
    s3))

(df resolve-enum-alias [(v String) (aliases (Map String String))] -> String
  :d "Resolves an enum variant alias if present or returns mangled identifier."
  (mt (map-get aliases v)
    ((some tgt)
     (if (or (string-starts-with? tgt "crate::")
             (string-contains? tgt "::"))
         tgt
         (m/mangle-ident v)))
    ((none) (m/mangle-ident v))))

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
         ((some mpath)
          (let [(enum-opt (map-get aliases (str mpath "/" member)))]
            (mt enum-opt
              ((some tgt) tgt)
              ((none) (str "crate::" (m/rust-mod-name mpath) "::" (m/mangle-ident member))))))
         ((none)
          (let [(enum-opt (map-get aliases s))]
            (mt enum-opt
              ((some tgt) tgt)
              ((none) (str (m/mangle-ident alias) "::" (m/mangle-ident member)))))))))
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
    (:else (resolve-enum-alias s aliases))))

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

(df resolve-qualified-case [(head String) (aliases (Map String String))] -> String
  :d "Resolves an enum case constructor head to its Rust target path."
  (if (string-contains? head "/")
      (let [(parts (string-split head "/"))
            (alias (option-or (list-get parts 0) ""))
            (member (option-or (list-get parts 1) ""))
            (mod-opt (map-get aliases alias))]
        (mt mod-opt
          ((some mpath)
           (let [(enum-opt (map-get aliases (str mpath "/" member)))]
             (mt enum-opt
               ((some tgt) tgt)
               ((none) (str "crate::" (m/rust-mod-name mpath) "::" (m/pascal-ident member))))))
          ((none)
           (let [(enum-opt (map-get aliases head))]
             (mt enum-opt
               ((some tgt) tgt)
               ((none) (str (m/mangle-ident alias) "::" (m/pascal-ident member))))))))
      (mt (map-get aliases head)
        ((some tgt) tgt)
        ((none) (m/pascal-ident head)))))

(df nth-pattern [(items (List rd/SExpr)) (idx I64) (aliases (Map String String))] -> String
  :d "Extracts and lowers pattern at index."
  (emit-pattern (option-or (list-get items idx) (rd/sexpr-atom "_")) aliases))

(df emit-pattern [(p rd/SExpr) (aliases (Map String String))] -> String
  :d "Lowers a match pattern to Rust match syntax."
  (mt p
    ((rd/sexpr-atom v)
     (cond
       ((= v "_") "_")
       ((= v "none") "None")
       ((= v "true") "true")
       ((= v "false") "false")
       ((string-starts-with? v "\"") (escape-raw-string v))
       (:else (resolve-enum-alias v aliases))))
    ((rd/sexpr-vect items)
     (if (<= (list-length items) 0)
         "[]"
         (str "[" (string-join (map (fn [(it rd/SExpr)] -> String (emit-pattern it aliases)) items) ", ") "]")))
    ((rd/sexpr-list items)
     (if (<= (list-length items) 0)
         "()"
         (let [(head (nth-atom items 0))]
           (cond
             ((= head "ok") (str "Ok(" (nth-pattern items 1 aliases) ")"))
             ((= head "err") (str "Err(" (nth-pattern items 1 aliases) ")"))
             ((= head "some") (str "Some(" (nth-pattern items 1 aliases) ")"))
             ((= head "none") "None")
             ((= head "pair") (str "(" (nth-pattern items 1 aliases) ", " (nth-pattern items 2 aliases) ")"))
             ((= head "list") "[]")
             ((= head "cons") (str "[" (nth-pattern items 1 aliases) ", " (nth-pattern items 2 aliases) " @ ..]"))
             (:else
              (let [(p-head (resolve-qualified-case head aliases))
                    (rest (if (> (list-length items) 1)
                              (list-tail items)
                              (none)))]
                (mt rest
                  ((none) p-head)
                  ((some r-items)
                   (if (<= (list-length r-items) 0)
                       p-head
                       (str p-head "(" (string-join (map (fn [(it rd/SExpr)] -> String (emit-pattern it aliases)) r-items) ", ") ")"))))))))))))

(df emit-body-seq [(body (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Emits a sequence of body expressions."
  (let [(body-len (list-length body))]
    (if (<= body-len 0)
        "()"
        (if (= body-len 1)
            (emit-expr (option-or (list-get body 0) (rd/sexpr-atom "()")) aliases)
            (let [(stmts (map (fn [(e rd/SExpr)] -> String
                                (str (emit-expr e aliases) "; "))
                              body))
                  (last-idx (- body-len 1))
                  (last-expr (emit-expr (option-or (list-get body last-idx) (rd/sexpr-atom "()")) aliases))
                  (prior-stmts (list-slice stmts 0 last-idx))]
              (mt prior-stmts
                ((some ps) (str (string-join ps "") last-expr))
                ((none) last-expr)))))))

(df emit-let [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a let form to Rust block expression."
  (let [(bindings-node (option-or (list-get items 1) (rd/sexpr-vect (list))))
        (body (slice-tail items 2))
        (bind-list (sexpr-to-list bindings-node))
        (let-stmts (map (fn [(b rd/SExpr)] -> String
                          (let [(pair (sexpr-to-list b))]
                            (if (>= (list-length pair) 2)
                                (let [(b-name (m/mangle-ident (nth-atom pair 0)))
                                      (b-val (clone-if-ident (emit-expr (option-or (list-get pair 1) (rd/sexpr-atom "()")) aliases)))]
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

(df is-list-arm? [(arm rd/SExpr)] -> Bool
  :d "True if arm pattern is a list or cons pattern."
  (mt arm
    ((rd/sexpr-list items)
     (if (<= (list-length items) 0)
         false
         (let [(pat (option-or (list-get items 0) (rd/sexpr-atom "")))]
           (mt pat
             ((rd/sexpr-vect _) true)
             ((rd/sexpr-list p-items)
              (let [(p-head (nth-atom p-items 0))]
                (or (= p-head "list") (= p-head "cons"))))
             (_ false)))))
    (_ false)))

(df is-string-arm? [(arm rd/SExpr)] -> Bool
  :d "True if arm pattern matches against a string literal."
  (mt arm
    ((rd/sexpr-list items)
     (if (<= (list-length items) 0)
         false
         (let [(pat (option-or (list-get items 0) (rd/sexpr-atom "")))]
           (mt pat
             ((rd/sexpr-atom v) (string-starts-with? v "\""))
             (_ false)))))
    (_ false)))

(df emit-match [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a match or mt form to Rust match expression."
  (let [(subj (emit-expr (option-or (list-get items 1) (rd/sexpr-atom "()")) aliases))
        (arms (slice-tail items 2))
        (is-slice (any-true? (map is-list-arm? arms)))
        (is-str (any-true? (map is-string-arm? arms)))
        (subj-base (if (is-ident? subj) (str subj ".clone()") subj))
        (subj-arg (cond
                    (is-slice (str subj-base ".as_slice()"))
                    (is-str (str subj-base ".as_str()"))
                    (:else subj-base)))
        (arm-strs (map (fn [(arm rd/SExpr)] -> String
                         (mt arm
                           ((rd/sexpr-list a-items)
                            (let [(pat-node (option-or (list-get a-items 0) (rd/sexpr-atom "_")))
                                  (pat-str (emit-pattern pat-node aliases))
                                  (body (slice-from-1 a-items))
                                  (body-str (emit-body-seq body aliases))
                                  (is-cons? (mt pat-node
                                              ((rd/sexpr-list p-items) (= (nth-atom p-items 0) "cons"))
                                              (_ false)))]
                              (if is-cons?
                                  (let [(p-items (mt pat-node ((rd/sexpr-list pi) pi) (_ (list))))
                                        (h-name (m/mangle-ident (nth-atom p-items 1)))
                                        (t-name (m/mangle-ident (nth-atom p-items 2)))]
                                    (str pat-str " => { let " h-name " = " h-name ".clone(); let " t-name " = " t-name ".to_vec(); " body-str " },"))
                                  (str pat-str " => { " body-str " },"))))
                           ((rd/sexpr-vect a-items)
                            (emit-match (list (rd/sexpr-atom "mt") (option-or (list-get items 1) (rd/sexpr-atom "()")) arm) aliases))
                           ((rd/sexpr-atom _) "")))
                       arms))
        (unreach (if is-slice " _ => unreachable!()," ""))]
    (str "match " subj-arg " { " (string-join arm-strs " ") unreach " }")))

(df emit-try [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a try form to Rust ? propagation."
  (let [(inner (emit-expr (option-or (list-get items 1) (rd/sexpr-atom "()")) aliases))]
    (str "(" inner ")?")))

(df emit-fn [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers an anonymous lambda fn to Rust closure."
  (let [(has-bang? (and (> (list-length items) 1)
                        (= (nth-atom items 1) "!")))
        (p-idx (if has-bang? 2 1))
        (b-idx (if has-bang? 3 2))
        (params-node (option-or (list-get items p-idx) (rd/sexpr-vect (list))))
        (p-list (sexpr-to-list params-node))
        (p-strs (map emit-fn-param p-list))
        (body (if (> (list-length items) b-idx)
                  (let [(tail (slice-tail items b-idx))
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
        (clean-rec (if (string-contains? rec-name "/")
                       (let [(parts (string-split rec-name "/"))
                             (alias (option-or (list-get parts 0) ""))
                             (member (option-or (list-get parts 1) ""))
                             (mod-opt (map-get aliases alias))]
                         (mt mod-opt
                           ((some mpath) (str "crate::" (m/rust-mod-name mpath) "::" (m/pascal-ident member)))
                           ((none) (str (m/mangle-ident alias) "::" (m/pascal-ident member)))))
                       (m/pascal-ident rec-name)))
        (items-len (list-length items))]
    (let [(inits (range 0 (/ (- items-len 1) 2)))
          (field-strs (map (fn [(idx Int64)] -> String
                             (let [(k-pos (+ 1 (* idx 2)))
                                   (v-pos (+ 2 (* idx 2)))
                                   (k-atom (nth-atom items k-pos))
                                   (k-clean (if (string-starts-with? k-atom ":")
                                                (slice-str-or k-atom 1 (string-length k-atom) k-atom)
                                                k-atom))
                                   (v-node (option-or (list-get items v-pos) (rd/sexpr-atom "()")))
                                   (v-val (emit-expr v-node aliases))
                                   (v-cloned (clone-if-ident v-val))]
                               (str (m/mangle-ident k-clean) ": " v-cloned)))
                           inits))]
      (str clean-rec " { " (string-join field-strs ", ") " }"))))

(df is-pascal-head? [(head String)] -> Bool
  :d "True if head appears to be a PascalCase record or case constructor."
  (if (< (string-length head) 1)
      false
      (let [(member (if (string-contains? head "/")
                        (let [(parts (string-split head "/"))]
                          (option-or (list-get parts 1) head))
                        head))
            (c0 (slice-str-or member 0 1 ""))]
        (and (= (string-upper c0) c0)
             (not (= c0 "_"))))))

(df emit-call [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a general call form or builtin."
  (let [(head (nth-atom items 0))
        (raw-args (slice-from-1 items))
        (args (map (fn [(a rd/SExpr)] -> String
                     (clone-if-ident (emit-expr a aliases)))
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
      ((and (>= (string-length head) 2)
            (string-starts-with? head ":"))
       (emit-record-init items aliases))
      ((is-pascal-head? head)
       (if (and (> (list-length items) 1)
                (string-starts-with? (nth-atom items 1) ":"))
           (emit-record-init items aliases)
           (case-call (resolve-qualified-case head aliases) args)))
      ((string-contains? head "/")
       (let [(parts (string-split head "/"))
             (alias (option-or (list-get parts 0) ""))
             (member (option-or (list-get parts 1) ""))
             (mod-opt (map-get aliases alias))]
         (mt mod-opt
           ((some mpath)
            (let [(enum-opt (map-get aliases (str mpath "/" member)))]
              (mt enum-opt
                ((some tgt) (case-call tgt args))
                ((none) (format-call (str "crate::" (m/rust-mod-name mpath) "::" (m/mangle-ident member)) args)))))
           ((none)
            (let [(enum-opt (map-get aliases head))]
              (mt enum-opt
                ((some tgt) (case-call tgt args))
                ((none) (format-call (str (m/mangle-ident alias) "::" (m/mangle-ident member)) args))))))))
      (:else
       (let [(enum-opt (map-get aliases head))]
         (mt enum-opt
           ((some tgt) (case-call tgt args))
           ((none) (format-call (emit-atom head aliases) args))))))))

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
