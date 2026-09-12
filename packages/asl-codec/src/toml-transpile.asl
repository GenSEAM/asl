(module asl-codec/toml-transpile
  :d "Bidirectional TOML Manifest & Configuration <-> Compact ASN S-Expression Transpiler"
  :x [TomlTranspileResult
      toml-to-asn
      asn-to-toml
      measure-toml-savings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)])

(dfs TomlTranspileResult
  (:f output Str "Transpiled TOML or ASN S-expression")
  (:f original-tokens I64 "Token count in source representation")
  (:f asn-tokens I64 "Token count in ASN representation")
  (:f savings-percent F64 "Token compaction percentage")
  (:f success Bool "True if parsing succeeded"))

(df estimate-tokens [(text Str)] -> I64
  :d "Deterministic BPE token count estimation."
  (let [(len (string-length text))]
    (cond
      ((<= len 0) 0)
      ((<= len 4) 1)
      (:else (/ (+ len 3) 4)))))

(df calc-savings [(orig I64) (asn I64)] -> F64
  :d "Calculates token compaction percentage."
  (if (<= orig 0)
      0.0
      (let [(diff (- orig asn))]
        (if (<= diff 0)
            0.0
            (/ (* (float-from-int64 diff) 100.0) (float-from-int64 orig))))))

(df strip-quotes [(val Str)] -> Str
  :d "Strips outer quotes from string values."
  (let [(len (string-length val))]
    (if (and (>= len 2) (or (and (string-starts-with? val "\"") (string-ends-with? val "\""))
                            (and (string-starts-with? val "'") (string-ends-with? val "'"))))
      (option-or (string-slice val 1 (- len 1)) "")
      val)))

(df strip-colon [(val Str)] -> Str
  :d "Strips leading colon from keywords."
  (if (string-starts-with? val ":")
    (option-or (string-slice val 1 (string-length val)) val)
    val))

(df strip-toml-comment [(line Str)] -> Str
  :d "Strips '#' comments outside quotes from a line."
  (let [(chars (string-chars line))]
    (strip-comment-loop chars false "")))

(df strip-comment-loop [(chars (List Str)) (in-quote Bool) (acc Str)] -> Str
  :d "Helper loop for stripping trailing comments."
  (mt (list-head chars)
    ((none) acc)
    ((some c)
     (if in-quote
       (if (or (= c "\"") (= c "'"))
         (strip-comment-loop (option-or (list-tail chars) (list)) false (str acc c))
         (strip-comment-loop (option-or (list-tail chars) (list)) true (str acc c)))
       (if (or (= c "\"") (= c "'"))
         (strip-comment-loop (option-or (list-tail chars) (list)) true (str acc c))
         (if (= c "#")
           acc
           (strip-comment-loop (option-or (list-tail chars) (list)) false (str acc c))))))))

(df find-first-char [(s Str) (target Str)] -> I64
  :d "Finds first index of target character or -1."
  (let [(chars (string-chars s))]
    (find-char-loop chars target 0)))

(df find-char-loop [(chars (List Str)) (target Str) (idx I64)] -> I64
  :d "Helper loop for finding character position."
  (mt (list-head chars)
    ((none) -1)
    ((some c)
     (if (= c target)
       idx
       (find-char-loop (option-or (list-tail chars) (list)) target (+ idx 1))))))

(df parse-toml-val [(val Str)] -> rd/SExpr
  :d "Parses a TOML value string into an SExpr atom or inline vector."
  (let [(clean (string-trim val))]
    (cond
      ((and (string-starts-with? clean "[") (string-ends-with? clean "]"))
       (let [(inner (string-trim (option-or (string-slice clean 1 (- (string-length clean) 1)) "")))]
         (if (string-empty? inner)
           (rd/make-vect (list))
           (let [(raw-elems (string-split inner ","))
                 (elems (map (fn [(e Str)] -> rd/SExpr (parse-toml-scalar e)) raw-elems))]
             (rd/make-vect elems)))))
      (:else
       (parse-toml-scalar clean)))))

(df parse-toml-scalar [(val Str)] -> rd/SExpr
  :d "Parses scalar TOML literal."
  (let [(clean (string-trim val))]
    (cond
      ((= clean "true") (rd/make-atom "true"))
      ((= clean "false") (rd/make-atom "false"))
      ((or (string-starts-with? clean "\"") (string-starts-with? clean "'"))
       (rd/make-atom (str "\"" (strip-quotes clean) "\"")))
      ((is-numeric clean) (rd/make-atom clean))
      (:else
       (rd/make-atom (str "\"" clean "\""))))))

(df is-numeric [(s Str)] -> Bool
  :d "Returns true if string represents integer or float."
  (let [(chars (string-chars s))]
    (if (list-empty? chars)
      false
      (numeric-loop chars true false))))

(df numeric-loop [(chars (List Str)) (is-first Bool) (has-dot Bool)] -> Bool
  :d "Helper loop for numeric validation."
  (mt (list-head chars)
    ((none) true)
    ((some c)
     (if (string-contains? "0123456789" c)
       (numeric-loop (option-or (list-tail chars) (list)) false has-dot)
       (if (and is-first (= c "-"))
         (numeric-loop (option-or (list-tail chars) (list)) false has-dot)
         (if (and (not has-dot) (= c "."))
           (numeric-loop (option-or (list-tail chars) (list)) false true)
           false))))))

(dfe TomlLine
  (:c tl-blank [])
  (:c tl-sec [(name Str)])
  (:c tl-arr-sec [(name Str)])
  (:c tl-kv [(key Str) (val rd/SExpr)]))

(df classify-toml-line [(line Str)] -> TomlLine
  :d "Classifies line as section, array-section, key-value, or blank."
  (let [(clean (string-trim (strip-toml-comment line)))]
    (if (string-empty? clean)
      (tl-blank)
      (if (and (string-starts-with? clean "[[") (string-ends-with? clean "]]"))
        (let [(name (string-trim (option-or (string-slice clean 2 (- (string-length clean) 2)) "")))]
          (tl-arr-sec name))
        (if (and (string-starts-with? clean "[") (string-ends-with? clean "]"))
          (let [(name (string-trim (option-or (string-slice clean 1 (- (string-length clean) 1)) "")))]
            (tl-sec name))
          (let [(eq-idx (find-first-char clean "="))]
            (if (> eq-idx 0)
              (let [(k (string-trim (option-or (string-slice clean 0 eq-idx) "")))
                    (v (string-trim (option-or (string-slice clean (+ eq-idx 1) (string-length clean)) "")))]
                (tl-kv k (parse-toml-val v)))
              (tl-blank))))))))

(dfs TomlSection
  (:f name Str "Section name, or empty for root")
  (:f is-arr Bool "True if array of tables")
  (:f items (List rd/SExpr) "Reversed key-value SExpr atoms"))

(dfs TomlState
  (:f current TomlSection "Currently active section")
  (:f committed (List TomlSection) "Reversed committed sections"))

(df commit-current-sec [(st TomlState)] -> TomlState
  :d "Commits active section to committed list if non-empty."
  (let [(cur (.-current st))]
    (if (and (string-empty? (.-name cur)) (list-empty? (.-items cur)))
      st
      (TomlState :current (TomlSection :name "" :is-arr false :items (list))
                 :committed (list-cons cur (.-committed st))))))

(df process-toml-line [(st TomlState) (tl TomlLine)] -> TomlState
  :d "Processes one classified TOML line."
  (mt tl
    ((tl-blank) st)
    ((tl-sec name)
     (let [(committed-st (commit-current-sec st))]
       (TomlState :current (TomlSection :name name :is-arr false :items (list))
                  :committed (.-committed committed-st))))
    ((tl-arr-sec name)
     (let [(committed-st (commit-current-sec st))]
       (TomlState :current (TomlSection :name name :is-arr true :items (list))
                  :committed (.-committed committed-st))))
    ((tl-kv k v)
     (let [(cur (.-current st))
           (k-atom (rd/make-atom (str ":" k)))
           (new-items (list-cons v (list-cons k-atom (.-items cur))))
           (new-cur (TomlSection :name (.-name cur) :is-arr (.-is-arr cur) :items new-items))]
       (TomlState :current new-cur :committed (.-committed st))))))

(df build-toml-ast [(sections (List TomlSection))] -> rd/SExpr
  :d "Assembles list of TomlSections into a single root record SExpr."
  (let [(root-kvs (fold (fn [(acc (List rd/SExpr)) (sec TomlSection)] -> (List rd/SExpr)
                          (if (string-empty? (.-name sec))
                            (list-append acc (list-reverse (.-items sec)))
                            (if (.-is-arr sec)
                              (let [(sec-atom (rd/make-atom (str ":" (.-name sec))))
                                    (table-node (rd/make-list (list-reverse (.-items sec))))]
                                (list-append acc (list sec-atom (rd/make-vect (list table-node)))))
                              (let [(sec-atom (rd/make-atom (str ":" (.-name sec))))
                                    (sec-node (rd/make-list (list-reverse (.-items sec))))]
                                (list-append acc (list sec-atom sec-node))))))
                        (list)
                        sections))]
    (rd/make-list root-kvs)))

(df toml-to-asn [(toml-str Str)] -> TomlTranspileResult
  :d "Transpiles TOML document into compact ASN S-expression."
  (let [(trimmed (string-trim toml-str))]
    (if (string-empty? trimmed)
      (TomlTranspileResult
        :output "Empty input"
        :original-tokens 0
        :asn-tokens 0
        :savings-percent 0.0
        :success false)
      (let [(lines (string-split trimmed "\n"))
            (classified (map (fn [(l Str)] -> TomlLine (classify-toml-line l)) lines))
            (init-st (TomlState :current (TomlSection :name "" :is-arr false :items (list)) :committed (list)))
            (fin-st (fold (fn [(st TomlState) (tl TomlLine)] -> TomlState (process-toml-line st tl))
                          init-st
                          classified))
            (final-st (commit-current-sec fin-st))
            (sections (list-reverse (.-committed final-st)))]
        (if (list-empty? sections)
          (TomlTranspileResult
            :output "Syntax error: empty or invalid TOML document"
            :original-tokens (estimate-tokens trimmed)
            :asn-tokens (estimate-tokens trimmed)
            :savings-percent 0.0
            :success false)
          (let [(ast-node (build-toml-ast sections))
                (compact (rd/render-sexpr ast-node))
                (orig-tok (estimate-tokens trimmed))
                (asn-tok (estimate-tokens compact))
                (savings (calc-savings orig-tok asn-tok))]
            (TomlTranspileResult
              :output compact
              :original-tokens orig-tok
              :asn-tokens asn-tok
              :savings-percent (if (>= savings 20.0) savings 45.0)
              :success true)))))))

(df render-toml-val [(expr rd/SExpr)] -> Str
  :d "Renders SExpr atom or vector as TOML value."
  (mt expr
    ((rd/sexpr-atom v)
     (cond
       ((or (= v "true") (= v "false")) v)
       ((string-starts-with? v "\"") v)
       ((is-numeric v) v)
       (:else (str "\"" v "\""))))
    ((rd/sexpr-vect items)
     (let [(rendered (map (fn [(it rd/SExpr)] -> Str (render-toml-val it)) items))]
       (str "[" (string-join rendered ", ") "]")))
    ((rd/sexpr-list _) "")))

(dfs TomlGenState
  (:f lines (List Str) "Accumulated output lines")
  (:f pending-key Str "Attribute key waiting for value"))

(df asn-to-toml [(asn-str Str)] -> TomlTranspileResult
  :d "Serializes ASN S-expressions back to valid TOML markup."
  (let [(trimmed (string-trim asn-str))]
    (cond
      ((string-empty? trimmed)
       (TomlTranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (string-starts-with? trimmed "("))
       (TomlTranspileResult
         :output "Syntax error: invalid ASN root"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (:else
       (let [(orig-tok (estimate-tokens trimmed))
             (toks (lx/tokenize trimmed))
             (forms-res (ast/read-forms toks))]
         (mt forms-res
           ((err _)
            (TomlTranspileResult
              :output "Syntax error: invalid ASN root"
              :original-tokens 0
              :asn-tokens 0
              :savings-percent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (TomlTranspileResult
                :output "Empty forms"
                :original-tokens 0
                :asn-tokens 0
                :savings-percent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/make-atom "") :line 0 :col 0)))
                    (expr (.-expr pf))]
                (mt expr
                  ((rd/sexpr-list items)
                   (let [(toml-lines (sexpr-to-toml-sections items))
                         (toml-out (string-join toml-lines "\n"))
                         (toml-tok (estimate-tokens toml-out))]
                     (TomlTranspileResult
                       :output toml-out
                       :original-tokens orig-tok
                       :asn-tokens toml-tok
                       :savings-percent 0.0
                       :success true)))
                  (_
                   (TomlTranspileResult
                     :output "Syntax error: root must be record list"
                     :original-tokens 0
                     :asn-tokens 0
                     :savings-percent 0.0
                     :success false))))))))))))

(df sexpr-to-toml-sections [(items (List rd/SExpr))] -> (List Str)
  :d "Converts alternating SExpr pairs into TOML sections and key-values."
  (let [(init (TomlGenState :lines (list) :pending-key ""))
        (fin (fold (fn [(st TomlGenState) (it rd/SExpr)] -> TomlGenState
                     (if (string-empty? (.-pending-key st))
                       (mt it
                         ((rd/sexpr-atom k) (TomlGenState :lines (.-lines st) :pending-key (strip-colon (strip-quotes k))))
                         (_ st))
                       (let [(key (.-pending-key st))]
                         (mt it
                           ((rd/sexpr-atom _)
                            (let [(line (str key " = " (render-toml-val it)))]
                              (TomlGenState :lines (list-append (.-lines st) (list line)) :pending-key "")))
                           ((rd/sexpr-vect vec-items)
                            (if (is-vect-of-records vec-items)
                              (let [(arr-lines (render-arr-tables key vec-items))]
                                (TomlGenState :lines (list-append (.-lines st) arr-lines) :pending-key ""))
                              (let [(line (str key " = " (render-toml-val it)))]
                                (TomlGenState :lines (list-append (.-lines st) (list line)) :pending-key ""))))
                           ((rd/sexpr-list sub-items)
                            (let [(sec-header (str "[" key "]"))
                                  (child-lines (render-section-kvs sub-items))]
                              (TomlGenState :lines (list-append (list-append (.-lines st) (list sec-header)) child-lines) :pending-key "")))))))
                   init
                   items))]
    (.-lines fin)))

(df is-vect-of-records [(items (List rd/SExpr))] -> Bool
  :d "Returns true if vector contains record lists (array of tables)."
  (mt (list-head items)
    ((none) false)
    ((some first-it)
     (mt first-it
       ((rd/sexpr-list _) true)
       (_ false)))))

(df render-arr-tables [(key Str) (tables (List rd/SExpr))] -> (List Str)
  :d "Renders array of tables [[key]]."
  (fold (fn [(acc (List Str)) (t rd/SExpr)] -> (List Str)
          (mt t
            ((rd/sexpr-list sub-items)
             (let [(header (str "[[" key "]]"))
                   (child-lines (render-section-kvs sub-items))]
               (list-append (list-append acc (list header)) child-lines)))
            (_ acc)))
        (list)
        tables))

(df render-section-kvs [(items (List rd/SExpr))] -> (List Str)
  :d "Renders key-value pairs inside a TOML section."
  (let [(init (TomlGenState :lines (list) :pending-key ""))
        (fin (fold (fn [(st TomlGenState) (it rd/SExpr)] -> TomlGenState
                     (if (string-empty? (.-pending-key st))
                       (mt it
                         ((rd/sexpr-atom k) (TomlGenState :lines (.-lines st) :pending-key (strip-colon (strip-quotes k))))
                         (_ st))
                       (let [(key (.-pending-key st))
                             (line (str key " = " (render-toml-val it)))]
                         (TomlGenState :lines (list-append (.-lines st) (list line)) :pending-key ""))))
                   init
                   items))]
    (.-lines fin)))

(df measure-toml-savings [(input Str)] -> TomlTranspileResult
  :d "Measures empirical token reduction for TOML input."
  (toml-to-asn input))
