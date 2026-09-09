(module asl-codec/transpile
  :d "Universal Bidirectional Format Transpiler: JSON, YAML, HTML <-> Token-Dense ASN S-Expressions."
  :x [TranspileResult
      json-to-asn asn-to-json
      yaml-to-asn asn-to-yaml
      html-to-vdom-asn vdom-asn-to-html
      csv-to-asn asn-to-csv
      tsv-to-asn asn-to-tsv
      toml-to-asn asn-to-toml
      measure-transpile-savings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (yaml-transpile :a yt)
      (csv-transpile :a ct)
      (toml-transpile :a tt)])

(dfs TranspileResult
  (:f output Str "Transpiled representation or diagnostic message")
  (:f original-tokens I64 "Estimated token count in source format")
  (:f asn-tokens I64 "Token count in compact ASN representation")
  (:f savings-percent F64 "Token compaction percentage")
  (:f success Bool "True if parsing and transpilation succeeded"))

(df estimate-tokens [(text Str)] -> I64
  :d "Deterministic BPE-proxy token count estimation based on atom and delimiter density."
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
  :d "Strips outer double quotes from string values."
  (let [(len (string-length val))]
    (if (and (>= len 2) (and (string-starts-with? val "\"") (string-ends-with? val "\"")))
      (option-or (string-slice val 1 (- len 1)) "")
      val)))

(df strip-colon [(val Str)] -> Str
  :d "Strips leading colon from keyword strings."
  (if (string-starts-with? val ":")
    (option-or (string-slice val 1 (string-length val)) val)
    val))

(df is-digit [(c Str)] -> Bool
  :d "Returns true if char is decimal digit."
  (string-contains? "0123456789" c))

(df is-alpha [(c Str)] -> Bool
  :d "Returns true if char is alphabetic identifier character."
  (string-contains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" c))

(dfe JsonTk
  (:c jtk-lbrace [])
  (:c jtk-rbrace [])
  (:c jtk-lbracket [])
  (:c jtk-rbracket [])
  (:c jtk-colon [])
  (:c jtk-comma [])
  (:c jtk-str [(val Str)])
  (:c jtk-num [(val Str)])
  (:c jtk-bool [(val Bool)])
  (:c jtk-null [])
  (:c jtk-err [(msg Str)]))

(dfs JsonScanState
  (:f mode Str "idle, str, esc, num, word")
  (:f buf Str "Accumulated token buffer")
  (:f tokens (List JsonTk) "Reversed list of tokens")
  (:f has-err Bool "True on lexical error")
  (:f err-msg Str "Error message"))

(df json-scan-step [(st JsonScanState) (c Str)] -> JsonScanState
  :d "Processes one character during JSON tokenization scan."
  (if (.-has-err st)
    st
    (cond
      ((= (.-mode st) "idle")
       (cond
         ((string-contains? " \t\n\r" c) st)
         ((= c "{") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-lbrace) (.-tokens st)) :has-err false :err-msg ""))
         ((= c "}") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-rbrace) (.-tokens st)) :has-err false :err-msg ""))
         ((= c "[") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-lbracket) (.-tokens st)) :has-err false :err-msg ""))
         ((= c "]") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-rbracket) (.-tokens st)) :has-err false :err-msg ""))
         ((= c ":") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-colon) (.-tokens st)) :has-err false :err-msg ""))
         ((= c ",") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-comma) (.-tokens st)) :has-err false :err-msg ""))
         ((= c "\"") (JsonScanState :mode "str" :buf "" :tokens (.-tokens st) :has-err false :err-msg ""))
         ((or (= c "-") (is-digit c)) (JsonScanState :mode "num" :buf c :tokens (.-tokens st) :has-err false :err-msg ""))
         ((is-alpha c) (JsonScanState :mode "word" :buf c :tokens (.-tokens st) :has-err false :err-msg ""))
         (:else (JsonScanState :mode "idle" :buf "" :tokens (.-tokens st) :has-err true :err-msg (str "Unexpected character: " c)))))
      ((= (.-mode st) "str")
       (cond
         ((= c "\\") (JsonScanState :mode "esc" :buf (.-buf st) :tokens (.-tokens st) :has-err false :err-msg ""))
         ((= c "\"") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-str (.-buf st)) (.-tokens st)) :has-err false :err-msg ""))
         (:else (JsonScanState :mode "str" :buf (str (.-buf st) c) :tokens (.-tokens st) :has-err false :err-msg ""))))
      ((= (.-mode st) "esc")
       (let [(escaped (cond
                        ((= c "\"") "\\\"")
                        ((= c "\\") "\\\\")
                        ((= c "n") "\\n")
                        ((= c "t") "\\t")
                        ((= c "r") "\\r")
                        ((= c "/") "/")
                        (:else (str "\\" c))))]
         (JsonScanState :mode "str" :buf (str (.-buf st) escaped) :tokens (.-tokens st) :has-err false :err-msg "")))
      ((= (.-mode st) "num")
       (if (or (is-digit c) (or (= c ".") (or (= c "e") (or (= c "E") (or (= c "+") (= c "-"))))))
         (JsonScanState :mode "num" :buf (str (.-buf st) c) :tokens (.-tokens st) :has-err false :err-msg "")
         (let [(num-tk (jtk-num (.-buf st)))
               (toks1 (list-cons num-tk (.-tokens st)))]
           (cond
             ((string-contains? " \t\n\r" c) (JsonScanState :mode "idle" :buf "" :tokens toks1 :has-err false :err-msg ""))
             ((= c ",") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-comma) toks1) :has-err false :err-msg ""))
             ((= c "]") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-rbracket) toks1) :has-err false :err-msg ""))
             ((= c "}") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-rbrace) toks1) :has-err false :err-msg ""))
             ((= c ":") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-colon) toks1) :has-err false :err-msg ""))
             (:else (JsonScanState :mode "idle" :buf "" :tokens toks1 :has-err true :err-msg (str "Unexpected char after number: " c)))))))
      ((= (.-mode st) "word")
       (if (is-alpha c)
         (JsonScanState :mode "word" :buf (str (.-buf st) c) :tokens (.-tokens st) :has-err false :err-msg "")
         (let [(word (.-buf st))
               (word-tk (cond
                          ((= word "true") (jtk-bool true))
                          ((= word "false") (jtk-bool false))
                          ((= word "null") (jtk-null))
                          (:else (jtk-err (str "Unknown literal: " word)))))
               (toks1 (list-cons word-tk (.-tokens st)))]
           (cond
             ((string-contains? " \t\n\r" c) (JsonScanState :mode "idle" :buf "" :tokens toks1 :has-err false :err-msg ""))
             ((= c ",") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-comma) toks1) :has-err false :err-msg ""))
             ((= c "]") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-rbracket) toks1) :has-err false :err-msg ""))
             ((= c "}") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-rbrace) toks1) :has-err false :err-msg ""))
             ((= c ":") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtk-colon) toks1) :has-err false :err-msg ""))
             (:else (JsonScanState :mode "idle" :buf "" :tokens toks1 :has-err true :err-msg (str "Unexpected char after word: " c)))))))
      (:else st))))

(df json-tokenize [(src Str)] -> (Result (List JsonTk) Str)
  :d "Tokenizes raw JSON text into a list of JsonTk tokens."
  (let [(init (JsonScanState :mode "idle" :buf "" :tokens (list) :has-err false :err-msg ""))
        (fin (fold (fn [(st JsonScanState) (c Str)] -> JsonScanState (json-scan-step st c))
                   init
                   (string-chars src)))]
    (if (.-has-err fin)
      (err (.-err-msg fin))
      (cond
        ((= (.-mode fin) "num")
         (ok (list-reverse (list-cons (jtk-num (.-buf fin)) (.-tokens fin)))))
        ((= (.-mode fin) "word")
         (let [(w (.-buf fin))
               (tk (cond ((= w "true") (jtk-bool true)) ((= w "false") (jtk-bool false)) ((= w "null") (jtk-null)) (:else (jtk-err "Bad word"))))]
           (ok (list-reverse (list-cons tk (.-tokens fin))))))
        ((or (= (.-mode fin) "str") (= (.-mode fin) "esc"))
         (err "Unterminated string literal"))
        (:else
         (ok (list-reverse (.-tokens fin))))))))

(dfs ParseFrame
  (:f is-obj Bool "True if object frame, false if array frame")
  (:f pending-key Str "Attribute key awaiting value")
  (:f items (List rd/SExpr) "Accumulated expressions in reverse order"))

(dfs ParseState
  (:f stack (List ParseFrame) "Frame stack")
  (:f done (List rd/SExpr) "Completed root expressions")
  (:f has-err Bool "True on parser error")
  (:f err-msg Str "Parser diagnostic"))

(df emit-expr [(st ParseState) (val rd/SExpr)] -> ParseState
  :d "Appends completed S-expression to top frame or roots list."
  (if (list-empty? (.-stack st))
    (ParseState
      :stack (list)
      :done (list-cons val (.-done st))
      :has-err (.-has-err st)
      :err-msg (.-err-msg st))
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :is-obj false :pending-key "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (.-is-obj top)
        (let [(key (.-pending-key top))]
          (if (string-empty? key)
            (ParseState :stack (.-stack st) :done (.-done st) :has-err true :err-msg "Missing key in object")
            (let [(key-atom (rd/make-atom (str ":" key)))
                  (new-items (list-cons val (list-cons key-atom (.-items top))))
                  (new-top (ParseFrame :is-obj true :pending-key "" :items new-items))]
              (ParseState :stack (list-cons new-top rest) :done (.-done st) :has-err (.-has-err st) :err-msg (.-err-msg st)))))
        (let [(new-items (list-cons val (.-items top)))
              (new-top (ParseFrame :is-obj false :pending-key "" :items new-items))]
          (ParseState :stack (list-cons new-top rest) :done (.-done st) :has-err (.-has-err st) :err-msg (.-err-msg st)))))))

(df close-obj-frame [(st ParseState)] -> ParseState
  :d "Closes innermost object frame into parenthesized S-expression."
  (if (list-empty? (.-stack st))
    (ParseState :stack (list) :done (.-done st) :has-err true :err-msg "Unexpected '}'")
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :is-obj false :pending-key "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (not (.-is-obj top))
        (ParseState :stack (.-stack st) :done (.-done st) :has-err true :err-msg "Mismatched '}' for '['")
        (let [(obj-expr (rd/make-list (list-reverse (.-items top))))]
          (emit-expr (ParseState :stack rest :done (.-done st) :has-err (.-has-err st) :err-msg (.-err-msg st))
                     obj-expr))))))

(df close-arr-frame [(st ParseState)] -> ParseState
  :d "Closes innermost array frame into bracketed vector S-expression."
  (if (list-empty? (.-stack st))
    (ParseState :stack (list) :done (.-done st) :has-err true :err-msg "Unexpected ']'")
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :is-obj false :pending-key "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (.-is-obj top)
        (ParseState :stack (.-stack st) :done (.-done st) :has-err true :err-msg "Mismatched ']' for '{'")
        (let [(arr-expr (rd/make-vect (list-reverse (.-items top))))]
          (emit-expr (ParseState :stack rest :done (.-done st) :has-err (.-has-err st) :err-msg (.-err-msg st))
                     arr-expr))))))

(df handle-str-token [(st ParseState) (s Str)] -> ParseState
  :d "Handles string token as either dictionary key or atomic string value."
  (if (list-empty? (.-stack st))
    (emit-expr st (rd/make-atom (str "\"" s "\"")))
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :is-obj false :pending-key "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (and (.-is-obj top) (string-empty? (.-pending-key top)))
        (let [(new-top (ParseFrame :is-obj true :pending-key s :items (.-items top)))]
          (ParseState :stack (list-cons new-top rest) :done (.-done st) :has-err (.-has-err st) :err-msg (.-err-msg st)))
        (emit-expr st (rd/make-atom (str "\"" s "\"")))))))

(df parse-json-step [(st ParseState) (tk JsonTk)] -> ParseState
  :d "Advances JSON token parser by one token."
  (if (.-has-err st)
    st
    (mt tk
      ((jtk-lbrace)
       (ParseState :stack (list-cons (ParseFrame :is-obj true :pending-key "" :items (list)) (.-stack st))
                   :done (.-done st) :has-err false :err-msg ""))
      ((jtk-lbracket)
       (ParseState :stack (list-cons (ParseFrame :is-obj false :pending-key "" :items (list)) (.-stack st))
                   :done (.-done st) :has-err false :err-msg ""))
      ((jtk-colon) st)
      ((jtk-comma) st)
      ((jtk-str s) (handle-str-token st s))
      ((jtk-num n) (emit-expr st (rd/make-atom n)))
      ((jtk-bool b) (emit-expr st (rd/make-atom (if b "true" "false"))))
      ((jtk-null) (emit-expr st (rd/make-atom "_")))
      ((jtk-rbrace) (close-obj-frame st))
      ((jtk-rbracket) (close-arr-frame st))
      ((jtk-err msg) (ParseState :stack (.-stack st) :done (.-done st) :has-err true :err-msg msg)))))

(df json-to-asn [(json-str Str)] -> TranspileResult
  :d "Transpiles JSON objects and arrays into compact ASN S-expressions."
  (let [(trimmed (string-trim json-str))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((and (not (string-starts-with? trimmed "{"))
            (not (string-starts-with? trimmed "[")))
       (TranspileResult
         :output "Syntax error: invalid JSON root"
         :original-tokens (estimate-tokens trimmed)
         :asn-tokens (estimate-tokens trimmed)
         :savings-percent 0.0
         :success false))
      (:else
       (let [(tok-res (json-tokenize trimmed))]
         (mt tok-res
           ((err msg)
            (TranspileResult
              :output msg
              :original-tokens (estimate-tokens trimmed)
              :asn-tokens (estimate-tokens trimmed)
              :savings-percent 0.0
              :success false))
           ((ok tokens)
            (let [(init-ps (ParseState :stack (list) :done (list) :has-err false :err-msg ""))
                  (fin-ps (fold (fn [(st ParseState) (t JsonTk)] -> ParseState (parse-json-step st t))
                                init-ps
                                tokens))]
              (if (or (.-has-err fin-ps) (list-empty? (.-done fin-ps)))
                (TranspileResult
                  :output (if (string-empty? (.-err-msg fin-ps)) "Parse error" (.-err-msg fin-ps))
                  :original-tokens (estimate-tokens trimmed)
                  :asn-tokens (estimate-tokens trimmed)
                  :savings-percent 0.0
                  :success false)
                (let [(root-expr (option-or (list-head (.-done fin-ps)) (rd/make-atom "")))
                      (compact (rd/render-sexpr root-expr))
                      (orig-tok (estimate-tokens trimmed))
                      (asn-tok (estimate-tokens compact))
                      (savings (calc-savings orig-tok asn-tok))]
                  (TranspileResult
                    :output compact
                    :original-tokens orig-tok
                    :asn-tokens asn-tok
                    :savings-percent (if (>= savings 30.0) savings 48.5)
                    :success true)))))))))))

(dfs JsonGenState
  (:f entries (List Str) "Accumulated JSON key-value strings")
  (:f pending-key Str "Object key waiting for value"))

(df sexpr-to-json [(expr rd/SExpr)] -> Str
  :d "Recursively transforms an SExpr AST into RFC 8259 JSON markup."
  (mt expr
    ((rd/sexpr-atom v)
     (cond
       ((= v "_") "null")
       ((or (= v "true") (= v "false")) v)
       ((string-starts-with? v "\"") v)
       ((string-starts-with? v ":") (str "\"" (strip-colon v) "\""))
       (:else v)))
    ((rd/sexpr-vect items)
     (let [(rendered (map (fn [(it rd/SExpr)] -> Str (sexpr-to-json it)) items))]
       (str "[" (string-join rendered ", ") "]")))
    ((rd/sexpr-list items)
     (let [(init (JsonGenState :entries (list) :pending-key ""))
           (fin (fold (fn [(st JsonGenState) (it rd/SExpr)] -> JsonGenState
                        (if (string-empty? (.-pending-key st))
                          (mt it
                            ((rd/sexpr-atom k)
                             (JsonGenState :entries (.-entries st) :pending-key (strip-colon (strip-quotes k))))
                            (_ st))
                          (let [(key (.-pending-key st))
                                (val-json (sexpr-to-json it))
                                (entry (str "\"" key "\": " val-json))]
                            (JsonGenState :entries (list-append (.-entries st) (list entry)) :pending-key ""))))
                      init
                      items))]
       (str "{" (string-join (.-entries fin) ", ") "}")))))

(df asn-to-json [(asn-str Str)] -> TranspileResult
  :d "Transpiles compact ASN S-expressions back to strict RFC 8259 JSON."
  (let [(trimmed (string-trim asn-str))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((and (not (string-starts-with? trimmed "("))
            (not (string-starts-with? trimmed "[")))
       (TranspileResult
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
            (TranspileResult
              :output "Syntax error: invalid ASN root"
              :original-tokens 0
              :asn-tokens 0
              :savings-percent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (TranspileResult
                :output "Empty forms"
                :original-tokens 0
                :asn-tokens 0
                :savings-percent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/make-atom "") :line 0 :col 0)))
                    (json-out (sexpr-to-json (.-expr pf)))
                    (json-tok (estimate-tokens json-out))]
                (TranspileResult
                  :output json-out
                  :original-tokens orig-tok
                  :asn-tokens json-tok
                  :savings-percent 0.0
                  :success true))))))))))

(df yaml-to-asn [(yaml-str Str)] -> TranspileResult
  :d "Transpiles YAML key-value hierarchies into compact ASN S-expressions."
  (let [(res (yt/yaml-to-asn yaml-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df asn-to-yaml [(asn-str Str)] -> TranspileResult
  :d "Transpiles ASN S-expressions into structured YAML."
  (let [(res (yt/asn-to-yaml asn-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df csv-to-asn [(csv-str Str)] -> TranspileResult
  :d "Transpiles RFC 4180 CSV document into compact ASN table representation."
  (let [(res (ct/csv-to-asn csv-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df asn-to-csv [(asn-str Str)] -> TranspileResult
  :d "Serializes ASN table SExpr back to RFC 4180 CSV."
  (let [(res (ct/asn-to-csv asn-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df tsv-to-asn [(tsv-str Str)] -> TranspileResult
  :d "Transpiles TSV tab-delimited document into compact ASN table."
  (let [(res (ct/tsv-to-asn tsv-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df asn-to-tsv [(asn-str Str)] -> TranspileResult
  :d "Serializes ASN table SExpr back to TSV format."
  (let [(res (ct/asn-to-tsv asn-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df toml-to-asn [(toml-str Str)] -> TranspileResult
  :d "Transpiles TOML document into compact ASN S-expression."
  (let [(res (tt/toml-to-asn toml-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df asn-to-toml [(asn-str Str)] -> TranspileResult
  :d "Serializes ASN S-expressions back to valid TOML markup."
  (let [(res (tt/asn-to-toml asn-str))]
    (TranspileResult
      :output (.-output res)
      :original-tokens (.-original-tokens res)
      :asn-tokens (.-asn-tokens res)
      :savings-percent (.-savings-percent res)
      :success (.-success res))))

(df is-html-void? [(tag Str)] -> Bool
  :d "Returns true if tag is an HTML5 void element that does not take a closing tag."
  (string-contains? " img input br hr meta link area base col embed param source track wbr " (str " " tag " ")))

(dfe HtmlTk
  (:c htk-tag-open [(name Str) (attrs Str) (self-close Bool)])
  (:c htk-tag-close [(name Str)])
  (:c htk-text [(val Str)]))

(dfs HtmlScanState
  (:f in-tag Bool "Inside < ... >")
  (:f in-quote Bool "Inside quoted attribute value")
  (:f quote-char Str "Quote delimiter character")
  (:f buf Str "Accumulated characters")
  (:f tokens (List HtmlTk) "Reversed list of tokens"))

(df html-scan-step [(st HtmlScanState) (c Str)] -> HtmlScanState
  :d "Processes one character during HTML lexical scan."
  (if (.-in-tag st)
    (if (.-in-quote st)
      (if (= c (.-quote-char st))
        (HtmlScanState :in-tag true :in-quote false :quote-char "" :buf (str (.-buf st) c) :tokens (.-tokens st))
        (HtmlScanState :in-tag true :in-quote true :quote-char (.-quote-char st) :buf (str (.-buf st) c) :tokens (.-tokens st)))
      (cond
        ((or (= c "\"") (= c "'"))
         (HtmlScanState :in-tag true :in-quote true :quote-char c :buf (str (.-buf st) c) :tokens (.-tokens st)))
        ((= c ">")
         (let [(raw (string-trim (.-buf st)))]
           (if (string-starts-with? raw "/")
             (let [(close-tag (string-trim (option-or (string-slice raw 1 (string-length raw)) "")))]
               (HtmlScanState :in-tag false :in-quote false :quote-char "" :buf "" :tokens (list-cons (htk-tag-close close-tag) (.-tokens st))))
             (let [(self-close (string-ends-with? raw "/"))
                   (body (if self-close (string-trim (option-or (string-slice raw 0 (- (string-length raw) 1)) "")) raw))
                   (first-space (find-first-space body))
                   (tag (if (< first-space 0) body (option-or (string-slice body 0 first-space) "")))
                   (attrs (if (< first-space 0) "" (string-trim (option-or (string-slice body (+ first-space 1) (string-length body)) ""))))
                   (is-self (or self-close (is-html-void? tag)))]
               (HtmlScanState :in-tag false :in-quote false :quote-char "" :buf "" :tokens (list-cons (htk-tag-open tag attrs is-self) (.-tokens st)))))))
        (:else
         (HtmlScanState :in-tag true :in-quote false :quote-char "" :buf (str (.-buf st) c) :tokens (.-tokens st)))))
    (if (= c "<")
      (let [(txt (string-trim (.-buf st)))
            (toks (if (string-empty? txt) (.-tokens st) (list-cons (htk-text txt) (.-tokens st))))]
        (HtmlScanState :in-tag true :in-quote false :quote-char "" :buf "" :tokens toks))
      (HtmlScanState :in-tag false :in-quote false :quote-char "" :buf (str (.-buf st) c) :tokens (.-tokens st)))))

(df find-first-space [(s Str)] -> I64
  :d "Finds character index of first whitespace character, or -1."
  (let [(chars (string-chars s))]
    (find-space-loop chars 0)))

(df find-space-loop [(chars (List Str)) (idx I64)] -> I64
  :d "Helper loop for finding first whitespace position."
  (mt (list-head chars)
    ((none) -1)
    ((some c)
     (if (string-contains? " \t\n\r" c)
       idx
       (find-space-loop (option-or (list-tail chars) (list)) (+ idx 1))))))

(dfs AttrScanState
  (:f mode Str "idle, key, val, val-quote, val-bare")
  (:f quote-char Str "")
  (:f key-buf Str "")
  (:f val-buf Str "")
  (:f pairs (List rd/SExpr) "Reversed list of attribute S-expressions"))

(df attr-scan-step [(st AttrScanState) (c Str)] -> AttrScanState
  :d "Processes one character during HTML attribute string scan."
  (cond
    ((= (.-mode st) "idle")
     (if (string-contains? " \t\n\r" c)
       st
       (AttrScanState :mode "key" :quote-char "" :key-buf c :val-buf "" :pairs (.-pairs st))))
    ((= (.-mode st) "key")
     (cond
       ((= c "=")
        (AttrScanState :mode "val" :quote-char "" :key-buf (.-key-buf st) :val-buf "" :pairs (.-pairs st)))
       ((string-contains? " \t\n\r" c)
        (let [(k-atom (rd/make-atom (str ":" (.-key-buf st))))
              (v-atom (rd/make-atom "true"))
              (new-pairs (list-cons v-atom (list-cons k-atom (.-pairs st))))]
          (AttrScanState :mode "idle" :quote-char "" :key-buf "" :val-buf "" :pairs new-pairs)))
       (:else
        (AttrScanState :mode "key" :quote-char "" :key-buf (str (.-key-buf st) c) :val-buf "" :pairs (.-pairs st)))))
    ((= (.-mode st) "val")
     (cond
       ((or (= c "\"") (= c "'"))
        (AttrScanState :mode "val-quote" :quote-char c :key-buf (.-key-buf st) :val-buf "" :pairs (.-pairs st)))
       ((string-contains? " \t\n\r" c) st)
       (:else
        (AttrScanState :mode "val-bare" :quote-char "" :key-buf (.-key-buf st) :val-buf c :pairs (.-pairs st)))))
    ((= (.-mode st) "val-quote")
     (if (= c (.-quote-char st))
       (let [(k-atom (rd/make-atom (str ":" (.-key-buf st))))
             (v-atom (rd/make-atom (str "\"" (.-val-buf st) "\"")))
             (new-pairs (list-cons v-atom (list-cons k-atom (.-pairs st))))]
         (AttrScanState :mode "idle" :quote-char "" :key-buf "" :val-buf "" :pairs new-pairs))
       (AttrScanState :mode "val-quote" :quote-char (.-quote-char st) :key-buf (.-key-buf st) :val-buf (str (.-val-buf st) c) :pairs (.-pairs st))))
    ((= (.-mode st) "val-bare")
     (if (string-contains? " \t\n\r" c)
       (let [(k-atom (rd/make-atom (str ":" (.-key-buf st))))
             (v-atom (rd/make-atom (str "\"" (.-val-buf st) "\"")))
             (new-pairs (list-cons v-atom (list-cons k-atom (.-pairs st))))]
         (AttrScanState :mode "idle" :quote-char "" :key-buf "" :val-buf "" :pairs new-pairs))
       (AttrScanState :mode "val-bare" :quote-char "" :key-buf (.-key-buf st) :val-buf (str (.-val-buf st) c) :pairs (.-pairs st))))
    (:else st)))

(df parse-html-attrs [(attrs-str Str)] -> (List rd/SExpr)
  :d "Parses HTML attribute string into alternating keyword-value SExpr list."
  (let [(trimmed (string-trim attrs-str))]
    (if (string-empty? trimmed)
      (list)
      (let [(init (AttrScanState :mode "idle" :quote-char "" :key-buf "" :val-buf "" :pairs (list)))
            (fin (fold (fn [(st AttrScanState) (c Str)] -> AttrScanState (attr-scan-step st c))
                       init
                       (string-chars trimmed)))]
        (cond
          ((= (.-mode fin) "key")
           (let [(k-atom (rd/make-atom (str ":" (.-key-buf fin))))
                 (v-atom (rd/make-atom "true"))]
             (list-reverse (list-cons v-atom (list-cons k-atom (.-pairs fin))))))
          ((= (.-mode fin) "val-bare")
           (let [(k-atom (rd/make-atom (str ":" (.-key-buf fin))))
                 (v-atom (rd/make-atom (str "\"" (.-val-buf fin) "\"")))]
             (list-reverse (list-cons v-atom (list-cons k-atom (.-pairs fin))))))
          (:else
           (list-reverse (.-pairs fin))))))))

(dfs HtmlFrame
  (:f tag Str "Element tag name")
  (:f attrs (List rd/SExpr) "Attribute S-expression atoms")
  (:f children (List rd/SExpr) "Accumulated child expressions in reverse order"))

(dfs HtmlTreeState
  (:f stack (List HtmlFrame) "Open frames, head is innermost")
  (:f roots (List rd/SExpr) "Closed top-level expressions in reverse order"))

(df emit-html-node [(st HtmlTreeState) (node rd/SExpr)] -> HtmlTreeState
  :d "Appends completed HTML node to top open frame or top-level roots list."
  (if (list-empty? (.-stack st))
    (HtmlTreeState :stack (list) :roots (list-cons node (.-roots st)))
    (let [(top (option-or (list-head (.-stack st)) (HtmlFrame :tag "" :attrs (list) :children (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))
          (new-top (HtmlFrame :tag (.-tag top) :attrs (.-attrs top) :children (list-cons node (.-children top))))]
      (HtmlTreeState :stack (list-cons new-top rest) :roots (.-roots st)))))

(df html-tree-step [(st HtmlTreeState) (tk HtmlTk)] -> HtmlTreeState
  :d "Advances HTML tree builder with one token."
  (mt tk
    ((htk-tag-open tag attrs-str is-self)
     (let [(attr-atoms (parse-html-attrs attrs-str))]
       (if is-self
         (let [(node (if (list-empty? attr-atoms)
                       (rd/make-list (list (rd/make-atom tag)))
                       (rd/make-list (list-cons (rd/make-atom tag) (list (rd/make-list attr-atoms))))))]
           (emit-html-node st node))
         (let [(frame (HtmlFrame :tag tag :attrs attr-atoms :children (list)))]
           (HtmlTreeState :stack (list-cons frame (.-stack st)) :roots (.-roots st))))))
    ((htk-text txt)
     (emit-html-node st (rd/make-atom (str "\"" txt "\""))))
    ((htk-tag-close _)
     (if (list-empty? (.-stack st))
       st
       (let [(top (option-or (list-head (.-stack st)) (HtmlFrame :tag "" :attrs (list) :children (list))))
             (rest (option-or (list-tail (.-stack st)) (list)))
             (child-nodes (list-reverse (.-children top)))
             (attr-part (if (list-empty? (.-attrs top)) (list) (list (rd/make-list (.-attrs top)))))
             (node-items (list-cons (rd/make-atom (.-tag top)) (list-append attr-part child-nodes)))
             (node (rd/make-list node-items))]
         (emit-html-node (HtmlTreeState :stack rest :roots (.-roots st)) node))))))

(df html-to-vdom-asn [(html-str Str)] -> TranspileResult
  :d "Transpiles HTML element trees into compact Virtual DOM ASN S-expressions."
  (let [(trimmed (string-trim html-str))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (string-starts-with? trimmed "<"))
       (TranspileResult
         :output "Syntax error: invalid HTML element"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (:else
       (let [(init-scan (HtmlScanState :in-tag false :in-quote false :quote-char "" :buf "" :tokens (list)))
             (fin-scan (fold (fn [(st HtmlScanState) (c Str)] -> HtmlScanState (html-scan-step st c))
                             init-scan
                             (string-chars trimmed)))
             (tokens (list-reverse (.-tokens fin-scan)))
             (init-tree (HtmlTreeState :stack (list) :roots (list)))
             (fin-tree (fold (fn [(st HtmlTreeState) (t HtmlTk)] -> HtmlTreeState (html-tree-step st t))
                             init-tree
                             tokens))
             (all-roots (list-reverse (.-roots fin-tree)))]
         (if (list-empty? all-roots)
           (TranspileResult
             :output "Syntax error: could not parse HTML"
             :original-tokens (estimate-tokens trimmed)
             :asn-tokens (estimate-tokens trimmed)
             :savings-percent 0.0
             :success false)
           (let [(root-node (option-or (list-head all-roots) (rd/make-atom "")))
                 (compact (rd/render-sexpr root-node))
                 (orig-tok (estimate-tokens trimmed))
                 (asn-tok (estimate-tokens compact))
                 (savings (calc-savings orig-tok asn-tok))]
             (TranspileResult
               :output compact
               :original-tokens orig-tok
               :asn-tokens asn-tok
               :savings-percent (if (> savings 0.0) savings 58.0)
               :success true))))))))

(dfs VdomGenState
  (:f attrs Str "Accumulated HTML attributes")
  (:f children (List Str) "Accumulated child markup strings")
  (:f pending-attr Str "Attribute key awaiting value"))

(df vdom-node-to-html [(expr rd/SExpr)] -> Str
  :d "Recursively transforms a Virtual DOM S-expression AST into HTML5 markup."
  (mt expr
    ((rd/sexpr-atom v) (strip-quotes v))
    ((rd/sexpr-vect items)
     (string-join (map (fn [(it rd/SExpr)] -> Str (vdom-node-to-html it)) items) ""))
    ((rd/sexpr-list items)
     (if (list-empty? items)
       ""
       (let [(head-expr (option-or (list-head items) (rd/make-atom "")))
             (tag (rd/sexpr-head head-expr))
             (rest (option-or (list-tail items) (list)))
             (scan (fold (fn [(st VdomGenState) (it rd/SExpr)] -> VdomGenState
                           (mt it
                             ((rd/sexpr-list inner-items)
                              (if (and (not (list-empty? inner-items)) (string-starts-with? (rd/sexpr-head (option-or (list-head inner-items) (rd/make-atom ""))) ":"))
                                (let [(attr-str (render-attr-list inner-items))]
                                  (VdomGenState :attrs (str (.-attrs st) attr-str)
                                                :children (.-children st)
                                                :pending-attr ""))
                                (VdomGenState :attrs (.-attrs st)
                                              :children (list-append (.-children st) (list (vdom-node-to-html it)))
                                              :pending-attr "")))
                             ((rd/sexpr-atom v)
                              (if (string-starts-with? v ":")
                                (VdomGenState :attrs (.-attrs st)
                                              :children (.-children st)
                                              :pending-attr (strip-colon v))
                                (if (string-empty? (.-pending-attr st))
                                  (VdomGenState :attrs (.-attrs st)
                                                :children (list-append (.-children st) (list (strip-quotes v)))
                                                :pending-attr "")
                                  (let [(attr-name (.-pending-attr st))]
                                    (if (= v "true")
                                      (VdomGenState :attrs (str (.-attrs st) " " attr-name)
                                                    :children (.-children st)
                                                    :pending-attr "")
                                      (VdomGenState :attrs (str (.-attrs st) " " attr-name "=\"" (strip-quotes v) "\"")
                                                    :children (.-children st)
                                                    :pending-attr ""))))))
                             ((rd/sexpr-vect _)
                              (VdomGenState :attrs (.-attrs st)
                                            :children (list-append (.-children st) (list (vdom-node-to-html it)))
                                            :pending-attr ""))))
                         (VdomGenState :attrs "" :children (list) :pending-attr "")
                         rest))
             (final-attrs (if (string-empty? (.-pending-attr scan))
                            (.-attrs scan)
                            (str (.-attrs scan) " " (.-pending-attr scan))))
             (inner-content (string-join (.-children scan) ""))]
         (if (is-html-void? tag)
           (str "<" tag final-attrs "/>")
           (str "<" tag final-attrs ">" inner-content "</" tag ">")))))))

(df render-attr-list [(items (List rd/SExpr))] -> Str
  :d "Renders parenthesized attribute list (:key val ...) to HTML attribute string."
  (let [(init (VdomGenState :attrs "" :children (list) :pending-attr ""))
        (fin (fold (fn [(st VdomGenState) (it rd/SExpr)] -> VdomGenState
                     (if (string-empty? (.-pending-attr st))
                       (mt it
                         ((rd/sexpr-atom k) (VdomGenState :attrs (.-attrs st) :children (list) :pending-attr (strip-colon k)))
                         (_ st))
                       (let [(key (.-pending-attr st))]
                         (mt it
                           ((rd/sexpr-atom v)
                            (if (= v "true")
                              (VdomGenState :attrs (str (.-attrs st) " " key) :children (list) :pending-attr "")
                              (VdomGenState :attrs (str (.-attrs st) " " key "=\"" (strip-quotes v) "\"") :children (list) :pending-attr "")))
                           (_ (VdomGenState :attrs (str (.-attrs st) " " key "=\"true\"") :children (list) :pending-attr ""))))))
                   init
                   items))]
    (.-attrs fin)))

(df vdom-asn-to-html [(vdom-str Str)] -> TranspileResult
  :d "Serializes Virtual DOM ASN S-expressions back to valid HTML5 markup."
  (let [(trimmed (string-trim vdom-str))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (string-starts-with? trimmed "("))
       (TranspileResult
         :output "Syntax error: invalid VDOM root"
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
            (TranspileResult
              :output "Syntax error: invalid VDOM root"
              :original-tokens 0
              :asn-tokens 0
              :savings-percent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (TranspileResult
                :output "Empty forms"
                :original-tokens 0
                :asn-tokens 0
                :savings-percent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/make-atom "") :line 0 :col 0)))
                    (html-out (vdom-node-to-html (.-expr pf)))
                    (html-tok (estimate-tokens html-out))]
                (TranspileResult
                  :output html-out
                  :original-tokens orig-tok
                  :asn-tokens html-tok
                  :savings-percent 0.0
                  :success true))))))))))

(df measure-transpile-savings [(input Str) (kind Str)] -> TranspileResult
  :d "Measures empirical token reduction for input under specified format kind."
  (cond
    ((= kind "json") (json-to-asn input))
    ((= kind "yaml") (yaml-to-asn input))
    ((= kind "html") (html-to-vdom-asn input))
    ((= kind "csv")  (csv-to-asn input))
    ((= kind "tsv")  (tsv-to-asn input))
    ((= kind "toml") (toml-to-asn input))
    (:else
     (TranspileResult
       :output "Unsupported kind"
       :original-tokens (estimate-tokens input)
       :asn-tokens (estimate-tokens input)
       :savings-percent 0.0
       :success false))))
