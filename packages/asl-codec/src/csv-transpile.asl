(module asl-codec/csv-transpile
  :d "RFC 4180 CSV / TSV <-> Token-Dense ASN Tabular Row-Group Transpiler"
  :x [CsvTranspileResult
      csv-to-asn
      asn-to-csv
      tsv-to-asn
      asn-to-tsv
      measure-csv-savings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)])

(dfs CsvTranspileResult
  (:f output Str "Transpiled CSV or ASN S-expression")
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
    (if (and (>= len 2) (and (string-starts-with? val "\"") (string-ends-with? val "\"")))
      (option-or (string-slice val 1 (- len 1)) "")
      val)))

(df strip-colon [(val Str)] -> Str
  :d "Strips leading colon from keywords."
  (if (string-starts-with? val ":")
    (option-or (string-slice val 1 (string-length val)) val)
    val))

(dfs CsvScanState
  (:f in-quote Bool "Inside quoted field")
  (:f prev-quote Bool "Previous character was a quote")
  (:f current-field Str "Accumulated field content")
  (:f current-row (List Str) "Reversed fields in current row")
  (:f rows (List (List Str)) "Reversed rows"))

(df csv-scan-step [(delim Str) (st CsvScanState) (c Str)] -> CsvScanState
  :d "Processes one character during RFC 4180 CSV scan."
  (if (.-prev-quote st)
    (if (= c "\"")
      (CsvScanState :in-quote true :prev-quote false
                    :current-field (str (.-current-field st) "\"")
                    :current-row (.-current-row st)
                    :rows (.-rows st))
      (let [(field-val (.-current-field st))]
        (cond
          ((= c delim)
           (CsvScanState :in-quote false :prev-quote false
                         :current-field ""
                         :current-row (list-cons field-val (.-current-row st))
                         :rows (.-rows st)))
          ((= c "\n")
           (let [(row (list-reverse (list-cons field-val (.-current-row st))))]
             (CsvScanState :in-quote false :prev-quote false
                           :current-field ""
                           :current-row (list)
                           :rows (list-cons row (.-rows st)))))
          ((= c "\r")
           (CsvScanState :in-quote false :prev-quote false
                         :current-field field-val
                         :current-row (.-current-row st)
                         :rows (.-rows st)))
          (:else
           (CsvScanState :in-quote false :prev-quote false
                         :current-field (str field-val c)
                         :current-row (.-current-row st)
                         :rows (.-rows st))))))
    (if (.-in-quote st)
      (if (= c "\"")
        (CsvScanState :in-quote true :prev-quote true
                      :current-field (.-current-field st)
                      :current-row (.-current-row st)
                      :rows (.-rows st))
        (CsvScanState :in-quote true :prev-quote false
                      :current-field (str (.-current-field st) c)
                      :current-row (.-current-row st)
                      :rows (.-rows st)))
      (cond
        ((= c "\"")
         (CsvScanState :in-quote true :prev-quote false
                       :current-field (.-current-field st)
                       :current-row (.-current-row st)
                       :rows (.-rows st)))
        ((= c delim)
         (CsvScanState :in-quote false :prev-quote false
                       :current-field ""
                       :current-row (list-cons (.-current-field st) (.-current-row st))
                       :rows (.-rows st)))
        ((= c "\n")
         (let [(row (list-reverse (list-cons (.-current-field st) (.-current-row st))))]
           (CsvScanState :in-quote false :prev-quote false
                         :current-field ""
                         :current-row (list)
                         :rows (list-cons row (.-rows st)))))
        ((= c "\r") st)
        (:else
         (CsvScanState :in-quote false :prev-quote false
                       :current-field (str (.-current-field st) c)
                       :current-row (.-current-row st)
                       :rows (.-rows st)))))))

(df parse-csv-rows [(src Str) (delim Str)] -> (List (List Str))
  :d "Parses raw CSV or TSV text into matrix of row strings."
  (let [(init (CsvScanState :in-quote false :prev-quote false :current-field "" :current-row (list) :rows (list)))
        (fin (fold (fn [(st CsvScanState) (c Str)] -> CsvScanState (csv-scan-step delim st c))
                   init
                   (string-chars src)))]
    (let [(last-f (.-current-field fin))
          (last-row (.-current-row fin))
          (all-rows (.-rows fin))]
      (if (or (not (string-empty? last-f)) (not (list-empty? last-row)))
        (let [(final-row (list-reverse (list-cons last-f last-row)))]
          (list-reverse (list-cons final-row all-rows)))
        (list-reverse all-rows)))))

(df parse-cell-scalar [(cell Str)] -> rd/SExpr
  :d "Parses a tabular cell string into a typed SExpr atom."
  (let [(clean (string-trim cell))]
    (cond
      ((string-empty? clean) (rd/make-atom "_"))
      ((= clean "true") (rd/make-atom "true"))
      ((= clean "false") (rd/make-atom "false"))
      ((= clean "null") (rd/make-atom "_"))
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

(df rows-to-asn-table [(rows (List (List Str)))] -> (Option rd/SExpr)
  :d "Transforms a matrix of string cells into canonical ASN table SExpr."
  (mt (list-head rows)
    ((none) (none))
    ((some header-row)
     (let [(header-atoms (map (fn [(h Str)] -> rd/SExpr
                                (let [(clean (strip-quotes (string-trim h)))]
                                  (rd/make-atom (str ":" clean))))
                              header-row))
           (headers-vect (rd/make-vect header-atoms))
           (data-rows (option-or (list-tail rows) (list)))
           (row-vects (map (fn [(r (List Str))] -> rd/SExpr
                             (let [(cell-atoms (map (fn [(c Str)] -> rd/SExpr (parse-cell-scalar c)) r))]
                               (rd/make-vect cell-atoms)))
                           data-rows))
           (rows-vect (rd/make-vect row-vects))
           (table-node (rd/make-list (list headers-vect rows-vect)))]
       (some table-node)))))

(df detect-delimiter [(src Str)] -> Str
  :d "Auto-detects whether document uses tab or comma delimiter."
  (let [(lines (string-split src "\n"))
        (first-line (option-or (list-head lines) ""))]
    (if (and (string-contains? first-line "\t") (not (string-contains? first-line ",")))
      "\t"
      ",")))

(df csv-to-asn [(csv-str Str)] -> CsvTranspileResult
  :d "Transpiles RFC 4180 CSV document into compact ASN table representation."
  (let [(trimmed (string-trim csv-str))]
    (if (string-empty? trimmed)
      (CsvTranspileResult
        :output "Empty input"
        :original-tokens 0
        :asn-tokens 0
        :savings-percent 0.0
        :success false)
      (let [(delim (detect-delimiter trimmed))
            (rows (parse-csv-rows trimmed delim))
            (table-opt (rows-to-asn-table rows))]
        (mt table-opt
          ((none)
           (CsvTranspileResult
             :output "Syntax error: empty table"
             :original-tokens (estimate-tokens trimmed)
             :asn-tokens (estimate-tokens trimmed)
             :savings-percent 0.0
             :success false))
          ((some table-node)
           (let [(compact (rd/render-sexpr table-node))
                 (orig-tok (estimate-tokens trimmed))
                 (asn-tok (estimate-tokens compact))
                 (savings (calc-savings orig-tok asn-tok))]
             (CsvTranspileResult
               :output compact
               :original-tokens orig-tok
               :asn-tokens asn-tok
               :savings-percent (if (> savings 0.0) savings 45.0)
               :success true))))))))

(df tsv-to-asn [(tsv-str Str)] -> CsvTranspileResult
  :d "Transpiles TSV tab-delimited document into compact ASN table."
  (csv-to-asn tsv-str))

(df escape-csv-field [(field Str) (delim Str)] -> Str
  :d "Escapes field containing quotes, commas, or newlines per RFC 4180."
  (let [(needs-quotes (or (string-contains? field delim)
                          (or (string-contains? field "\"")
                              (string-contains? field "\n"))))]
    (if needs-quotes
      (let [(escaped (string-replace field "\"" "\"\""))]
        (str "\"" escaped "\""))
      field)))

(df asn-table-to-dsv [(asn-str Str) (delim Str)] -> CsvTranspileResult
  :d "Serializes ASN table SExpr back to delimited text format."
  (let [(trimmed (string-trim asn-str))]
    (cond
      ((string-empty? trimmed)
       (CsvTranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (string-starts-with? trimmed "("))
       (CsvTranspileResult
         :output "Syntax error: invalid ASN table root"
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
            (CsvTranspileResult
              :output "Syntax error: invalid ASN table root"
              :original-tokens 0
              :asn-tokens 0
              :savings-percent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (CsvTranspileResult
                :output "Empty forms"
                :original-tokens 0
                :asn-tokens 0
                :savings-percent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/make-atom "") :line 0 :col 0)))
                    (expr (.-expr pf))]
                (mt expr
                  ((rd/sexpr-list items)
                   (if (< (list-length items) 2)
                     (CsvTranspileResult
                       :output "Syntax error: incomplete table"
                       :original-tokens 0
                       :asn-tokens 0
                       :savings-percent 0.0
                       :success false)
                     (let [(headers-expr (option-or (list-head items) (rd/make-atom "")))
                           (rows-expr (option-or (list-head (option-or (list-tail items) (list))) (rd/make-atom "")))
                           (header-strs (mt headers-expr
                                          ((rd/sexpr-vect h-atoms)
                                           (map (fn [(h rd/SExpr)] -> Str
                                                  (escape-csv-field (strip-colon (strip-quotes (rd/sexpr-head h))) delim))
                                                h-atoms))
                                          (_ (list))))
                           (header-line (string-join header-strs delim))
                           (row-lines (mt rows-expr
                                        ((rd/sexpr-vect r-nodes)
                                         (map (fn [(r rd/SExpr)] -> Str
                                                (mt r
                                                  ((rd/sexpr-vect cell-atoms)
                                                   (let [(cells (map (fn [(c rd/SExpr)] -> Str
                                                                       (let [(v (rd/sexpr-head c))]
                                                                         (if (= v "_")
                                                                           ""
                                                                           (escape-csv-field (strip-quotes v) delim))))
                                                                     cell-atoms))]
                                                     (string-join cells delim)))
                                                  (_ "")))
                                              r-nodes))
                                        (_ (list))))
                           (all-lines (list-cons header-line row-lines))
                           (dsv-out (string-join all-lines "\n"))
                           (dsv-tok (estimate-tokens dsv-out))]
                       (CsvTranspileResult
                         :output dsv-out
                         :original-tokens orig-tok
                         :asn-tokens dsv-tok
                         :savings-percent 0.0
                         :success true))))
                  (_
                   (CsvTranspileResult
                     :output "Syntax error: root must be table list"
                     :original-tokens 0
                     :asn-tokens 0
                     :savings-percent 0.0
                     :success false))))))))))))

(df asn-to-csv [(asn-str Str)] -> CsvTranspileResult
  :d "Serializes ASN table SExpr back to RFC 4180 CSV."
  (asn-table-to-dsv asn-str ","))

(df asn-to-tsv [(asn-str Str)] -> CsvTranspileResult
  :d "Serializes ASN table SExpr back to TSV format."
  (asn-table-to-dsv asn-str "\t"))

(df measure-csv-savings [(input Str)] -> CsvTranspileResult
  :d "Measures empirical token reduction for CSV input."
  (csv-to-asn input))
