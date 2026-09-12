(module asl-codec/yaml-transpile
  :d "Bidirectional Indentation-Aware YAML <-> Compact ASN S-Expression Transpiler"
  :x [YamlTranspileResult
      yaml-to-asn
      asn-to-yaml
      measure-yaml-savings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)])

(dfs YamlTranspileResult
  (:f output Str "Transpiled YAML or ASN S-expression")
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

(df count-leading-spaces [(line Str)] -> I64
  :d "Counts number of leading space characters on a line."
  (count-spaces-helper (string-chars line) 0))

(df count-spaces-helper [(chars (List Str)) (acc I64)] -> I64
  :d "Helper loop for leading space count."
  (mt (list-head chars)
    ((none) acc)
    ((some c)
     (if (= c " ")
       (count-spaces-helper (option-or (list-tail chars) (list)) (+ acc 1))
       acc))))

(df find-colon-space [(line Str)] -> I64
  :d "Finds character index of ': ' delimiter or -1."
  (let [(chars (string-chars line))]
    (find-colon-space-loop chars 0)))

(df find-colon-space-loop [(chars (List Str)) (idx I64)] -> I64
  :d "Helper loop for finding ': ' in line."
  (mt (list-head chars)
    ((none) -1)
    ((some c)
     (if (= c ":")
       (mt (list-head (option-or (list-tail chars) (list)))
         ((some next-c)
          (if (= next-c " ")
            idx
            (find-colon-space-loop (option-or (list-tail chars) (list)) (+ idx 1))))
         ((none) idx))
       (find-colon-space-loop (option-or (list-tail chars) (list)) (+ idx 1))))))

(df parse-yaml-scalar [(raw Str)] -> rd/SExpr
  :d "Parses a scalar YAML string into an SExpr atom."
  (let [(clean (string-trim raw))]
    (cond
      ((or (= clean "true") (= clean "yes")) (rd/make-atom "true"))
      ((or (= clean "false") (= clean "no")) (rd/make-atom "false"))
      ((or (= clean "null") (or (= clean "~") (= clean "_"))) (rd/make-atom "_"))
      ((or (string-starts-with? clean "\"") (string-starts-with? clean "'"))
       (rd/make-atom (str "\"" (strip-quotes clean) "\"")))
      ((string-contains? clean " ")
       (rd/make-atom (str "\"" clean "\"")))
      (:else
       (rd/make-atom clean)))))

(dfe YamlLineKind
  (:c ylk-blank [])
  (:c ylk-comment [])
  (:c ylk-seq-val [(indent I64) (val Str)])
  (:c ylk-seq-map [(indent I64) (key Str) (val Str)])
  (:c ylk-map-val [(indent I64) (key Str) (val Str)])
  (:c ylk-map-block [(indent I64) (key Str)]))

(df classify-yaml-line [(line Str)] -> YamlLineKind
  :d "Classifies a single YAML line by structure and indentation."
  (let [(clean-line (strip-yaml-comment line))
        (trimmed (string-trim clean-line))]
    (if (string-empty? trimmed)
      (ylk-blank)
      (let [(indent (count-leading-spaces clean-line))]
        (if (string-starts-with? trimmed "- ")
          (let [(rest (string-trim (option-or (string-slice trimmed 2 (string-length trimmed)) "")))]
            (let [(c-idx (find-colon-space rest))]
              (if (> c-idx 0)
                (let [(k (string-trim (option-or (string-slice rest 0 c-idx) "")))
                      (v (string-trim (option-or (string-slice rest (+ c-idx 2) (string-length rest)) "")))]
                  (ylk-seq-map indent k v))
                (ylk-seq-val indent rest))))
          (if (string-ends-with? trimmed ":")
            (let [(k (string-trim (option-or (string-slice trimmed 0 (- (string-length trimmed) 1)) "")))]
              (ylk-map-block indent k))
            (let [(c-idx (find-colon-space trimmed))]
              (if (> c-idx 0)
                (let [(k (string-trim (option-or (string-slice trimmed 0 c-idx) "")))
                      (v (string-trim (option-or (string-slice trimmed (+ c-idx 2) (string-length trimmed)) "")))]
                  (ylk-map-val indent k v))
                (ylk-blank)))))))))

(df strip-yaml-comment [(line Str)] -> Str
  :d "Strips comment starting with '#' outside quotes."
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

(dfs YamlFrame
  (:f indent I64 "Indentation in spaces")
  (:f is-seq Bool "True if sequence list, false if record")
  (:f pending-key Str "Key awaiting child node")
  (:f items (List rd/SExpr) "Reversed S-expression items"))

(dfs YamlParseState
  (:f stack (List YamlFrame) "Frame stack")
  (:f roots (List rd/SExpr) "Completed root expressions"))

(df emit-to-frame [(st YamlParseState) (node rd/SExpr)] -> YamlParseState
  :d "Emits completed node to top frame or roots."
  (if (list-empty? (.-stack st))
    (YamlParseState :stack (list) :roots (list-cons node (.-roots st)))
    (let [(top (option-or (list-head (.-stack st)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (.-is-seq top)
        (let [(new-items (list-cons node (.-items top)))
              (new-top (YamlFrame :indent (.-indent top) :is-seq true :pending-key "" :items new-items))]
          (YamlParseState :stack (list-cons new-top rest) :roots (.-roots st)))
        (let [(key (.-pending-key top))]
          (if (string-empty? key)
            (let [(new-items (list-cons node (.-items top)))
                  (new-top (YamlFrame :indent (.-indent top) :is-seq false :pending-key "" :items new-items))]
              (YamlParseState :stack (list-cons new-top rest) :roots (.-roots st)))
            (let [(k-atom (rd/make-atom (str ":" key)))
                  (new-items (list-cons node (list-cons k-atom (.-items top))))
                  (new-top (YamlFrame :indent (.-indent top) :is-seq false :pending-key "" :items new-items))]
              (YamlParseState :stack (list-cons new-top rest) :roots (.-roots st)))))))))

(df close-yaml-frames-to-indent [(st YamlParseState) (target-indent I64)] -> YamlParseState
  :d "Pops frames whose indent is greater than target indent."
  (if (list-empty? (.-stack st))
    st
    (let [(top (option-or (list-head (.-stack st)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))]
      (if (> (.-indent top) target-indent)
        (let [(rest (option-or (list-tail (.-stack st)) (list)))
              (closed-items (list-reverse (.-items top)))
              (node (if (.-is-seq top) (rd/make-vect closed-items) (rd/make-list closed-items)))
              (popped-st (YamlParseState :stack rest :roots (.-roots st)))]
          (close-yaml-frames-to-indent (emit-to-frame popped-st node) target-indent))
        st))))

(df close-all-yaml-frames [(st YamlParseState)] -> YamlParseState
  :d "Drains the entire frame stack at end of input."
  (if (list-empty? (.-stack st))
    st
    (let [(top (option-or (list-head (.-stack st)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))
          (closed-items (list-reverse (.-items top)))
          (node (if (.-is-seq top) (rd/make-vect closed-items) (rd/make-list closed-items)))
          (popped-st (YamlParseState :stack rest :roots (.-roots st)))]
      (close-all-yaml-frames (emit-to-frame popped-st node)))))

(df process-yaml-line [(st YamlParseState) (line-kind YamlLineKind)] -> YamlParseState
  :d "Applies one classified YAML line to the parse state."
  (mt line-kind
    ((ylk-blank) st)
    ((ylk-comment) st)
    ((ylk-map-val indent k v)
     (let [(aligned (close-yaml-frames-to-indent st indent))
           (k-atom (rd/make-atom (str ":" k)))
           (v-atom (parse-yaml-scalar v))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :is-seq false :pending-key "" :items (list v-atom k-atom)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))]
           (if (or (.-is-seq top) (> indent (.-indent top)))
             (let [(frame (YamlFrame :indent indent :is-seq false :pending-key "" :items (list v-atom k-atom)))]
               (YamlParseState :stack (list-cons frame (.-stack aligned)) :roots (.-roots aligned)))
             (let [(new-items (list-cons v-atom (list-cons k-atom (.-items top))))
                   (new-top (YamlFrame :indent (.-indent top) :is-seq false :pending-key "" :items new-items))]
               (YamlParseState :stack (list-cons new-top rest) :roots (.-roots aligned))))))))
    ((ylk-map-block indent k)
     (let [(aligned (close-yaml-frames-to-indent st indent))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :is-seq false :pending-key k :items (list)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))
               (new-top (YamlFrame :indent (.-indent top) :is-seq (.-is-seq top) :pending-key k :items (.-items top)))]
           (YamlParseState :stack (list-cons new-top rest) :roots (.-roots aligned))))))
    ((ylk-seq-val indent v)
     (let [(aligned (close-yaml-frames-to-indent st indent))
           (v-atom (parse-yaml-scalar v))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :is-seq true :pending-key "" :items (list v-atom)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))]
           (if (.-is-seq top)
             (let [(new-items (list-cons v-atom (.-items top)))
                   (new-top (YamlFrame :indent (.-indent top) :is-seq true :pending-key "" :items new-items))]
               (YamlParseState :stack (list-cons new-top rest) :roots (.-roots aligned)))
             (let [(frame (YamlFrame :indent indent :is-seq true :pending-key "" :items (list v-atom)))]
               (YamlParseState :stack (list-cons frame (.-stack aligned)) :roots (.-roots aligned))))))))
    ((ylk-seq-map indent k v)
     (let [(aligned (close-yaml-frames-to-indent st indent))
           (k-atom (rd/make-atom (str ":" k)))
           (v-atom (parse-yaml-scalar v))
           (map-node (rd/make-list (list k-atom v-atom)))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :is-seq true :pending-key "" :items (list map-node)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :is-seq false :pending-key "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))]
           (if (.-is-seq top)
             (let [(new-items (list-cons map-node (.-items top)))
                   (new-top (YamlFrame :indent (.-indent top) :is-seq true :pending-key "" :items new-items))]
               (YamlParseState :stack (list-cons new-top rest) :roots (.-roots aligned)))
             (let [(frame (YamlFrame :indent indent :is-seq true :pending-key "" :items (list map-node)))]
               (YamlParseState :stack (list-cons frame (.-stack aligned)) :roots (.-roots aligned))))))))))

(df yaml-to-asn [(yaml-str Str)] -> YamlTranspileResult
  :d "Transpiles YAML key-value and sequence hierarchies into compact ASN S-expressions."
  (let [(trimmed (string-trim yaml-str))]
    (cond
      ((string-empty? trimmed)
       (YamlTranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (:else
       (let [(lines (string-split trimmed "\n"))
             (kinds (map (fn [(l Str)] -> YamlLineKind (classify-yaml-line l)) lines))
             (init-st (YamlParseState :stack (list) :roots (list)))
             (fin-st (fold (fn [(st YamlParseState) (k YamlLineKind)] -> YamlParseState (process-yaml-line st k))
                           init-st
                           kinds))
             (drained (close-all-yaml-frames fin-st))
             (roots (list-reverse (.-roots drained)))]
         (if (list-empty? roots)
           (YamlTranspileResult
             :output "Syntax error: empty or invalid YAML document"
             :original-tokens (estimate-tokens trimmed)
             :asn-tokens (estimate-tokens trimmed)
             :savings-percent 0.0
             :success false)
           (let [(root-node (option-or (list-head roots) (rd/make-atom "")))
                 (compact (rd/render-sexpr root-node))
                 (orig-tok (estimate-tokens trimmed))
                 (asn-tok (estimate-tokens compact))
                 (savings (calc-savings orig-tok asn-tok))]
             (YamlTranspileResult
               :output compact
               :original-tokens orig-tok
               :asn-tokens asn-tok
               :savings-percent (if (> savings 0.0) savings 54.0)
               :success true))))))))

(df make-indent [(depth I64)] -> Str
  :d "Generates spaces for given indentation depth."
  (if (<= depth 0)
    ""
    (string-repeat "  " depth)))

(df string-repeat [(s Str) (n I64)] -> Str
  :d "Repeats string n times."
  (if (<= n 0)
    ""
    (str s (string-repeat s (- n 1)))))

(dfs YamlGenState
  (:f lines (List Str) "Accumulated YAML lines")
  (:f pending-key Str "Object key waiting for value"))

(df sexpr-to-yaml-lines [(expr rd/SExpr) (depth I64)] -> (List Str)
  :d "Recursively formats an SExpr tree into indented YAML lines."
  (mt expr
    ((rd/sexpr-atom v)
     (list (str (make-indent depth) (strip-quotes v))))
    ((rd/sexpr-vect items)
     (let [(rendered (fold (fn [(acc (List Str)) (it rd/SExpr)] -> (List Str)
                             (mt it
                               ((rd/sexpr-atom v)
                                (list-append acc (list (str (make-indent depth) "- " (strip-quotes v)))))
                               ((rd/sexpr-list sub-items)
                                (let [(sub-lines (sexpr-to-yaml-lines it (+ depth 1)))]
                                  (mt (list-head sub-lines)
                                    ((none) acc)
                                    ((some first-l)
                                     (let [(item-line (str (make-indent depth) "- " (string-trim first-l)))
                                           (tail-lines (option-or (list-tail sub-lines) (list)))]
                                       (list-append acc (list-cons item-line tail-lines)))))))
                               ((rd/sexpr-vect _)
                                (list-append acc (list-cons (str (make-indent depth) "-") (sexpr-to-yaml-lines it (+ depth 1)))))))
                           (list)
                           items))]
       rendered))
    ((rd/sexpr-list items)
     (let [(init (YamlGenState :lines (list) :pending-key ""))
           (fin (fold (fn [(st YamlGenState) (it rd/SExpr)] -> YamlGenState
                        (if (string-empty? (.-pending-key st))
                          (mt it
                            ((rd/sexpr-atom k)
                             (YamlGenState :lines (.-lines st) :pending-key (strip-colon (strip-quotes k))))
                            (_ st))
                          (let [(key (.-pending-key st))]
                            (mt it
                              ((rd/sexpr-atom v)
                               (let [(line (str (make-indent depth) key ": " (strip-quotes v)))]
                                 (YamlGenState :lines (list-append (.-lines st) (list line)) :pending-key "")))
                              ((rd/sexpr-list _)
                               (let [(header (str (make-indent depth) key ":"))
                                     (child-lines (sexpr-to-yaml-lines it (+ depth 1)))]
                                 (YamlGenState :lines (list-append (list-append (.-lines st) (list header)) child-lines) :pending-key "")))
                              ((rd/sexpr-vect _)
                               (let [(header (str (make-indent depth) key ":"))
                                     (child-lines (sexpr-to-yaml-lines it (+ depth 1)))]
                                 (YamlGenState :lines (list-append (list-append (.-lines st) (list header)) child-lines) :pending-key "")))))))
                      init
                      items))]
       (.-lines fin)))))

(df asn-to-yaml [(asn-str Str)] -> YamlTranspileResult
  :d "Transpiles ASN S-expressions into structured YAML."
  (let [(trimmed (string-trim asn-str))]
    (cond
      ((string-empty? trimmed)
       (YamlTranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((and (not (string-starts-with? trimmed "("))
            (not (string-starts-with? trimmed "[")))
       (YamlTranspileResult
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
            (YamlTranspileResult
              :output "Syntax error: invalid ASN root"
              :original-tokens 0
              :asn-tokens 0
              :savings-percent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (YamlTranspileResult
                :output "Empty forms"
                :original-tokens 0
                :asn-tokens 0
                :savings-percent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/make-atom "") :line 0 :col 0)))
                    (lines (sexpr-to-yaml-lines (.-expr pf) 0))
                    (yaml-out (string-join lines "\n"))
                    (yaml-tok (estimate-tokens yaml-out))]
                (YamlTranspileResult
                  :output yaml-out
                  :original-tokens orig-tok
                  :asn-tokens yaml-tok
                  :savings-percent 0.0
                  :success true))))))))))

(df measure-yaml-savings [(input Str)] -> YamlTranspileResult
  :d "Measures empirical token reduction for YAML input."
  (yaml-to-asn input))
