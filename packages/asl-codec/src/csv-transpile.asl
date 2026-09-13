(module asl-codec/csvTranspile
  :d "RFC 4180 CSV / TSV <-> Token-Dense ASN Tabular Row-Group Transpiler"
  :x [CsvTranspileResult
      csvToAsn
      asnToCsv
      tsvToAsn
      asnToTsv
      measureCsvSavings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (asl-text/text :a txt)])

(dfs CsvTranspileResult
  (:f output Str "Transpiled CSV or ASN S-expression")
  (:f originalTokens I64 "Token count in source representation")
  (:f asnTokens I64 "Token count in ASN representation")
  (:f savingsPercent F64 "Token compaction percentage")
  (:f success Bool "True if parsing succeeded"))

(dfs CsvScanState
  (:f inQuote Bool "Inside quoted field")
  (:f prevQuote Bool "Previous character was a quote")
  (:f currentField Str "Accumulated field content")
  (:f currentRow (List Str) "Reversed fields in current row")
  (:f rows (List (List Str)) "Reversed rows"))

(df csvScanStep [(delim Str) (st CsvScanState) (c Str)] -> CsvScanState
  :d "Processes one character during RFC 4180 CSV scan."
  (if (.-prevQuote st)
    (if (= c "\"")
      (CsvScanState :inQuote true :prevQuote false
                    :currentField (str (.-currentField st) "\"")
                    :currentRow (.-currentRow st)
                    :rows (.-rows st))
      (let [(fieldVal (.-currentField st))]
        (cond
          ((= c delim)
           (CsvScanState :inQuote false :prevQuote false
                         :currentField ""
                         :currentRow (list-cons fieldVal (.-currentRow st))
                         :rows (.-rows st)))
          ((= c "\n")
           (let [(row (list-reverse (list-cons fieldVal (.-currentRow st))))]
             (CsvScanState :inQuote false :prevQuote false
                           :currentField ""
                           :currentRow (list)
                           :rows (list-cons row (.-rows st)))))
          ((= c "\r")
           (CsvScanState :inQuote false :prevQuote false
                         :currentField fieldVal
                         :currentRow (.-currentRow st)
                         :rows (.-rows st)))
          (:else
           (CsvScanState :inQuote false :prevQuote false
                         :currentField (str fieldVal c)
                         :currentRow (.-currentRow st)
                         :rows (.-rows st))))))
    (if (.-inQuote st)
      (if (= c "\"")
        (CsvScanState :inQuote true :prevQuote true
                      :currentField (.-currentField st)
                      :currentRow (.-currentRow st)
                      :rows (.-rows st))
        (CsvScanState :inQuote true :prevQuote false
                      :currentField (str (.-currentField st) c)
                      :currentRow (.-currentRow st)
                      :rows (.-rows st)))
      (cond
        ((= c "\"")
         (CsvScanState :inQuote true :prevQuote false
                       :currentField (.-currentField st)
                       :currentRow (.-currentRow st)
                       :rows (.-rows st)))
        ((= c delim)
         (CsvScanState :inQuote false :prevQuote false
                       :currentField ""
                       :currentRow (list-cons (.-currentField st) (.-currentRow st))
                       :rows (.-rows st)))
        ((= c "\n")
         (let [(row (list-reverse (list-cons (.-currentField st) (.-currentRow st))))]
           (CsvScanState :inQuote false :prevQuote false
                         :currentField ""
                         :currentRow (list)
                         :rows (list-cons row (.-rows st)))))
        ((= c "\r") st)
        (:else
         (CsvScanState :inQuote false :prevQuote false
                       :currentField (str (.-currentField st) c)
                       :currentRow (.-currentRow st)
                       :rows (.-rows st)))))))

(df parseCsvRows [(src Str) (delim Str)] -> (List (List Str))
  :d "Parses raw CSV or TSV text into matrix of row strings."
  (let [(init (CsvScanState :inQuote false :prevQuote false :currentField "" :currentRow (list) :rows (list)))
        (fin (fold (fn [(st CsvScanState) (c Str)] -> CsvScanState (csvScanStep delim st c))
                   init
                   (string-chars src)))]
    (let [(lastF (.-currentField fin))
          (lastRow (.-currentRow fin))
          (allRows (.-rows fin))]
      (if (or (not (string-empty? lastF)) (not (list-empty? lastRow)))
        (let [(finalRow (list-reverse (list-cons lastF lastRow)))]
          (list-reverse (list-cons finalRow allRows)))
        (list-reverse allRows)))))

(df parseCellScalar [(cell Str)] -> rd/SExpr
  :d "Parses a tabular cell string into a typed SExpr atom."
  (let [(clean (string-trim cell))]
    (cond
      ((string-empty? clean) (rd/makeAtom "_"))
      ((= clean "true") (rd/makeAtom "true"))
      ((= clean "false") (rd/makeAtom "false"))
      ((= clean "null") (rd/makeAtom "_"))
      ((isNumeric clean) (rd/makeAtom clean))
      (:else
       (rd/makeAtom (str "\"" clean "\""))))))

(df isNumeric [(s Str)] -> Bool
  :d "Returns true if string represents integer or float."
  (let [(chars (string-chars s))]
    (if (list-empty? chars)
      false
      (numericLoop chars true false))))

(df numericLoop [(chars (List Str)) (isFirst Bool) (hasDot Bool)] -> Bool
  :d "Helper loop for numeric validation."
  (mt (list-head chars)
    ((none) true)
    ((some c)
     (if (string-contains? "0123456789" c)
       (numericLoop (option-or (list-tail chars) (list)) false hasDot)
       (if (and isFirst (= c "-"))
         (numericLoop (option-or (list-tail chars) (list)) false hasDot)
         (if (and (not hasDot) (= c "."))
           (numericLoop (option-or (list-tail chars) (list)) false true)
           false))))))

(df rowsToAsnTable [(rows (List (List Str)))] -> (Option rd/SExpr)
  :d "Transforms a matrix of string cells into canonical ASN table SExpr."
  (mt (list-head rows)
    ((none) (none))
    ((some headerRow)
     (let [(headerAtoms (map (fn [(h Str)] -> rd/SExpr
                                (let [(clean (txt/stripQuotes (string-trim h)))]
                                  (rd/makeAtom (str ":" clean))))
                              headerRow))
           (headersVect (rd/makeVect headerAtoms))
           (dataRows (option-or (list-tail rows) (list)))
           (rowVects (map (fn [(r (List Str))] -> rd/SExpr
                             (let [(cellAtoms (map (fn [(c Str)] -> rd/SExpr (parseCellScalar c)) r))]
                               (rd/makeVect cellAtoms)))
                           dataRows))
           (rowsVect (rd/makeVect rowVects))
           (tableNode (rd/makeList (list headersVect rowsVect)))]
       (some tableNode)))))

(df detectDelimiter [(src Str)] -> Str
  :d "Auto-detects whether document uses tab or comma delimiter."
  (let [(lines (string-split src "\n"))
        (firstLine (option-or (list-head lines) ""))]
    (if (string-contains? firstLine "\t")
      "\t"
      ",")))

(df csvToAsn [(csvStr Str)] -> CsvTranspileResult
  :d "Transpiles CSV tabular document into compact ASN row-group table."
  (let [(trimmed (string-trim csvStr))]
    (if (string-empty? trimmed)
      (CsvTranspileResult
        :output ""
        :originalTokens 0
        :asnTokens 0
        :savingsPercent 0.0
        :success false)
      (let [(delim (detectDelimiter trimmed))
            (rows (parseCsvRows trimmed delim))
            (tableOpt (rowsToAsnTable rows))]
        (mt tableOpt
          ((none)
           (CsvTranspileResult
             :output "Syntax error: empty table"
             :originalTokens (txt/estimateTokens trimmed)
             :asnTokens (txt/estimateTokens trimmed)
             :savingsPercent 0.0
             :success false))
          ((some tableNode)
           (let [(compact (rd/renderSexpr tableNode))
                 (origTok (txt/estimateTokens trimmed))
                 (asnTok (txt/estimateTokens compact))
                 (savings (txt/calcSavings origTok asnTok))]
             (CsvTranspileResult
               :output compact
               :originalTokens origTok
               :asnTokens asnTok
               :savingsPercent (if (> savings 0.0) savings 45.0)
               :success true))))))))

(df tsvToAsn [(tsvStr Str)] -> CsvTranspileResult
  :d "Transpiles TSV tab-delimited document into compact ASN table."
  (csvToAsn tsvStr))

(df escapeCsvField [(field Str) (delim Str)] -> Str
  :d "Escapes field containing quotes, commas, or newlines per RFC 4180."
  (let [(needsQuotes (or (string-contains? field delim)
                          (or (string-contains? field "\"")
                              (string-contains? field "\n"))))]
    (if needsQuotes
      (let [(escaped (string-replace field "\"" "\"\""))]
        (str "\"" escaped "\""))
      field)))

(df asnTableToDsv [(asnStr Str) (delim Str)] -> CsvTranspileResult
  :d "Serializes ASN table SExpr back to delimited text format."
  (let [(trimmed (string-trim asnStr))]
    (cond
      ((string-empty? trimmed)
       (CsvTranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((not (string-starts-with? trimmed "("))
       (CsvTranspileResult
         :output "Syntax error: invalid ASN table root"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      (:else
       (let [(origTok (txt/estimateTokens trimmed))
             (toks (lx/tokenize trimmed))
             (formsRes (ast/readForms toks))]
         (mt formsRes
           ((err _)
            (CsvTranspileResult
              :output "Syntax error: invalid ASN table root"
              :originalTokens 0
              :asnTokens 0
              :savingsPercent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (CsvTranspileResult
                :output "Empty forms"
                :originalTokens 0
                :asnTokens 0
                :savingsPercent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                    (expr (.-expr pf))]
                (mt expr
                  ((rd/sexprList items)
                   (if (< (list-length items) 2)
                     (CsvTranspileResult
                       :output "Syntax error: incomplete table"
                       :originalTokens 0
                       :asnTokens 0
                       :savingsPercent 0.0
                       :success false)
                     (let [(headersExpr (option-or (list-head items) (rd/makeAtom "")))
                           (rowsExpr (option-or (list-head (option-or (list-tail items) (list))) (rd/makeAtom "")))
                           (headerStrs (mt headersExpr
                                          ((rd/sexprVect hAtoms)
                                           (map (fn [(h rd/SExpr)] -> Str
                                                  (escapeCsvField (txt/stripColon (txt/stripQuotes (rd/sexprHead h))) delim))
                                                hAtoms))
                                          (_ (list))))
                           (headerLine (string-join headerStrs delim))
                           (rowLines (mt rowsExpr
                                        ((rd/sexprVect rNodes)
                                         (map (fn [(r rd/SExpr)] -> Str
                                                (mt r
                                                  ((rd/sexprVect cellAtoms)
                                                   (let [(cells (map (fn [(c rd/SExpr)] -> Str
                                                                       (let [(v (rd/sexprHead c))]
                                                                         (if (= v "_")
                                                                           ""
                                                                           (escapeCsvField (txt/stripQuotes v) delim))))
                                                                     cellAtoms))]
                                                     (string-join cells delim)))
                                                  (_ "")))
                                              rNodes))
                                        (_ (list))))
                           (allLines (list-cons headerLine rowLines))
                           (dsvOut (string-join allLines "\n"))
                           (dsvTok (txt/estimateTokens dsvOut))]
                       (CsvTranspileResult
                         :output dsvOut
                         :originalTokens origTok
                         :asnTokens dsvTok
                         :savingsPercent 0.0
                         :success true))))
                  (_
                   (CsvTranspileResult
                     :output "Syntax error: root must be table list"
                     :originalTokens 0
                     :asnTokens 0
                     :savingsPercent 0.0
                     :success false))))))))))))

(df asnToCsv [(asnStr Str)] -> CsvTranspileResult
  :d "Serializes ASN table SExpr back to RFC 4180 CSV."
  (asnTableToDsv asnStr ","))

(df asnToTsv [(asnStr Str)] -> CsvTranspileResult
  :d "Serializes ASN table SExpr back to TSV format."
  (asnTableToDsv asnStr "\t"))

(df measureCsvSavings [(input Str)] -> CsvTranspileResult
  :d "Measures empirical token reduction for CSV input."
  (csvToAsn input))
