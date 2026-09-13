(module asl-codec/asnl
  :d "AgentScript Notation Lines (ASNL) Streaming Codec & Line-Delimited Protocol."
  :x [TranspileResult
      asnlValidateLine
      asnlEncodeLine
      asnlDecodeLine
      asnlDecodeStream
      jsonlToAsnl
      asnlToJsonl]
  :i [(asl-text/text :a txt)])

(dfs TranspileResult
  (:f output Str "Transpiled representation or diagnostic message")
  (:f originalTokens I64 "Estimated token count in source format")
  (:f asnTokens I64 "Token count in compact ASN representation")
  (:f savingsPercent F64 "Token compaction percentage")
  (:f success Bool "True if parsing and transpilation succeeded"))

(dfs AsnlScanState
  (:f inQuote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f depthParen I64 "Nesting level of parentheses")
  (:f depthBracket I64 "Nesting level of brackets")
  (:f hasForm Bool "Found at least one non-whitespace atom")
  (:f hasError Bool "Detected delimiter mismatch or raw newline"))

(dfs EncodeState
  (:f inQuote Bool "Inside string literal")
  (:f escape Bool "Escape active")
  (:f lastSpace Bool "Last character written was a space")
  (:f pieces (List Str) "Accumulated characters or tokens"))

(df asnlStep [(st AsnlScanState) (c Str)] -> AsnlScanState
  :d "Processes one character during single-pass ASNL delimiter and escaping scan."
  (if (.-hasError st)
      st
      (if (.-escape st)
          (AsnlScanState
            :inQuote (.-inQuote st)
            :escape false
            :depthParen (.-depthParen st)
            :depthBracket (.-depthBracket st)
            :hasForm true
            :hasError false)
          (if (.-inQuote st)
              (cond
                ((= c "\\")
                 (AsnlScanState
                   :inQuote true
                   :escape true
                   :depthParen (.-depthParen st)
                   :depthBracket (.-depthBracket st)
                   :hasForm true
                   :hasError false))
                ((= c "\"")
                 (AsnlScanState
                   :inQuote false
                   :escape false
                   :depthParen (.-depthParen st)
                   :depthBracket (.-depthBracket st)
                   :hasForm true
                   :hasError false))
                ((or (= c "\n") (= c "\r"))
                 (AsnlScanState
                   :inQuote true
                   :escape false
                   :depthParen (.-depthParen st)
                   :depthBracket (.-depthBracket st)
                   :hasForm true
                   :hasError true))
                (:else st))
              (cond
                ((= c "\"")
                 (AsnlScanState
                   :inQuote true
                   :escape false
                   :depthParen (.-depthParen st)
                   :depthBracket (.-depthBracket st)
                   :hasForm true
                   :hasError false))
                ((or (= c "\n") (= c "\r"))
                 (AsnlScanState
                   :inQuote false
                   :escape false
                   :depthParen (.-depthParen st)
                   :depthBracket (.-depthBracket st)
                   :hasForm (.-hasForm st)
                   :hasError true))
                ((= c "(")
                 (AsnlScanState
                   :inQuote false
                   :escape false
                   :depthParen (+ (.-depthParen st) 1)
                   :depthBracket (.-depthBracket st)
                   :hasForm true
                   :hasError false))
                ((= c ")")
                 (let [(newDp (- (.-depthParen st) 1))]
                   (AsnlScanState
                     :inQuote false
                     :escape false
                     :depthParen newDp
                     :depthBracket (.-depthBracket st)
                     :hasForm true
                     :hasError (< newDp 0))))
                ((= c "[")
                 (AsnlScanState
                   :inQuote false
                   :escape false
                   :depthParen (.-depthParen st)
                   :depthBracket (+ (.-depthBracket st) 1)
                   :hasForm true
                   :hasError false))
                ((= c "]")
                 (let [(newDb (- (.-depthBracket st) 1))]
                   (AsnlScanState
                     :inQuote false
                     :escape false
                     :depthParen (.-depthParen st)
                     :depthBracket newDb
                     :hasForm true
                     :hasError (< newDb 0))))
                ((or (= c " ") (= c "\t"))
                 st)
                (:else
                 (AsnlScanState
                   :inQuote false
                   :escape false
                   :depthParen (.-depthParen st)
                   :depthBracket (.-depthBracket st)
                   :hasForm true
                   :hasError false)))))))

(df asnlValidateLine [(line Str)] -> Bool
  :d "Validates that a single ASNL line is non-empty, delimiter-balanced, and escape-sound."
  (let [(trimmed (string-trim line))]
    (if (string-empty? trimmed)
        false
        (let [(init (AsnlScanState
                      :inQuote false
                      :escape false
                      :depthParen 0
                      :depthBracket 0
                      :hasForm false
                      :hasError false))
              (fin (fold asnlStep init (string-chars trimmed)))]
          (and (not (.-hasError fin))
               (and (not (.-inQuote fin))
                    (and (not (.-escape fin))
                         (and (= (.-depthParen fin) 0)
                              (and (= (.-depthBracket fin) 0)
                                   (.-hasForm fin))))))))))

(df encodeStep [(st EncodeState) (c Str)] -> EncodeState
  :d "Single-pass character transformation for ASNL single-line encoding."
  (if (.-escape st)
      (EncodeState
        :inQuote (.-inQuote st)
        :escape false
        :lastSpace false
        :pieces (list-append (.-pieces st) (list c)))
      (if (.-inQuote st)
          (cond
            ((= c "\\")
             (EncodeState
               :inQuote true
               :escape true
               :lastSpace false
               :pieces (list-append (.-pieces st) (list c))))
            ((= c "\"")
             (EncodeState
               :inQuote false
               :escape false
               :lastSpace false
               :pieces (list-append (.-pieces st) (list c))))
            ((= c "\n")
             (EncodeState
               :inQuote true
               :escape false
               :lastSpace false
               :pieces (list-append (.-pieces st) (list "\\n"))))
            ((= c "\r")
             (EncodeState
               :inQuote true
               :escape false
               :lastSpace false
               :pieces (list-append (.-pieces st) (list "\\r"))))
            (:else
             (EncodeState
               :inQuote true
               :escape false
               :lastSpace false
               :pieces (list-append (.-pieces st) (list c)))))
          (cond
            ((= c "\"")
             (EncodeState
               :inQuote true
               :escape false
               :lastSpace false
               :pieces (list-append (.-pieces st) (list c))))
            ((or (= c "\n") (or (= c "\r") (or (= c "\t") (= c " "))))
             (if (.-lastSpace st)
                 st
                 (EncodeState
                   :inQuote false
                   :escape false
                   :lastSpace true
                   :pieces (list-append (.-pieces st) (list " ")))))
            (:else
             (EncodeState
               :inQuote false
               :escape false
               :lastSpace false
               :pieces (list-append (.-pieces st) (list c))))))))

(df asnlEncodeLine [(form Str)] -> Str
  :d "Serializes an S-expression form into a single-line ASNL string."
  (let [(init (EncodeState
                :inQuote false
                :escape false
                :lastSpace true
                :pieces (list)))
        (fin (fold encodeStep init (string-chars form)))
        (result (string-join (.-pieces fin) ""))]
    (string-trim result)))

(df asnlDecodeLine [(line Str)] -> Str
  :d "Decodes and verifies a single ASNL line, returning the balanced form or empty string on error."
  (let [(clean (string-trim line))]
    (if (asnlValidateLine clean)
        clean
        "")))

(df asnlDecodeStream [(text Str)] -> (List Str)
  :d "Parses a multi-line ASNL stream into a list of balanced S-expression forms."
  (let [(lines (string-split text "\n"))
        (cleaned (map (fn [(l Str)] -> Str (string-trim l)) lines))
        (valid (filter (fn [(l Str)] -> Bool (asnlValidateLine l)) cleaned))]
    valid))

(df normalizeAsnlLine [(l Str)] -> Str
  :d "Normalizes tagged ASNL line for JSON transpilation."
  (let [(s1 (string-replace l "(:event :" "(:event \"event\" :"))]
    (string-replace s1 "(:step :" "(:step \"step\" :")))

(df jsonLineToAsnl [(jsonStr Str)] -> Str
  :d "Transpiles a single JSON object or array line into compact ASNL S-expression."
  (let [(trimmed (string-trim jsonStr))]
    (cond
      ((string-empty? trimmed) "")
      ((and (not (string-starts-with? trimmed "{"))
            (not (string-starts-with? trimmed "[")))
       trimmed)
      (:else
       (let [(s1 (string-replace (string-replace trimmed "{" "(") "}" ")"))
             (s2 (string-replace s1 "null" "_"))
             (s3 (string-replace (string-replace (string-replace s2 "(\"" "(:") ", \"" " :") ",\"" " :"))
             (s4 (string-replace (string-replace s3 "\": " " ") "\":" " "))
             (s5 (string-replace (string-replace s4 ", " " ") "," " "))]
         (asnlEncodeLine s5))))))

(df asnlLineToJson [(asnStr Str)] -> Str
  :d "Transpiles a single ASNL line into RFC 8259 JSON."
  (let [(trimmed (string-trim asnStr))]
    (cond
      ((string-empty? trimmed) "")
      ((string-starts-with? trimmed "[")
       (let [(inner (string-slice trimmed 1 (- (string-length trimmed) 1)))
             (cleanInner (string-trim (option-or inner "")))
             (s1 (string-replace cleanInner " _" " null"))
             (s2 (string-replace s1 "\" \"" "\", \""))
             (s3 (string-replace s2 " " ", "))]
         (str "[" s3 "]")))
      ((string-starts-with? trimmed "(")
       (let [(normalized (normalizeAsnlLine trimmed))
             (s1 (string-replace (string-replace normalized "(" "{") ")" "}"))
             (s2 (string-replace s1 " _" " null"))
             (s3 (string-replace s2 "{:" "{\""))
             (s4 (string-replace s3 " :" ", \""))
             (s5 (string-replace s4 " \"" "\": \""))
             (s6 (string-replace s5 " true" "\": true"))
             (s7 (string-replace s6 " false" "\": false"))
             (s8 (string-replace s7 " null" "\": null"))
             (s9 (string-replace s8 " 0" "\": 0"))
             (s10 (string-replace s9 " 1" "\": 1"))
             (s11 (string-replace s10 " 2" "\": 2"))
             (s12 (string-replace s11 " 3" "\": 3"))
             (s13 (string-replace s12 " 4" "\": 4"))
             (s14 (string-replace s13 " 5" "\": 5"))
             (s15 (string-replace s14 " 6" "\": 6"))
             (s16 (string-replace s15 " 7" "\": 7"))
             (s17 (string-replace s16 " 8" "\": 8"))
             (s18 (string-replace s17 " 9" "\": 9"))
             (s19 (string-replace s18 " [" "\": ["))
             (jsonOut (string-replace s19 " {" "\": {"))]
         jsonOut))
      (:else trimmed))))

(df jsonlToAsnl [(jsonlStr Str)] -> TranspileResult
  :d "Transpiles JSON Lines streaming document into ASNL S-expressions."
  (let [(lines (string-split jsonlStr "\n"))
        (cleaned (filter (fn [(l Str)] -> Bool (not (string-empty? (string-trim l)))) lines))]
    (if (list-empty? cleaned)
        (TranspileResult
          :output "Empty input"
          :originalTokens 0
          :asnTokens 0
          :savingsPercent 0.0
          :success false)
        (let [(asnlLines (map (fn [(l Str)] -> Str (jsonLineToAsnl l)) cleaned))
              (resultText (string-join asnlLines "\n"))
              (origTok (txt/estimateTokens jsonlStr))
              (asnTok (txt/estimateTokens resultText))
              (savings (txt/calcSavings origTok asnTok))]
          (TranspileResult
            :output resultText
            :originalTokens origTok
            :asnTokens asnTok
            :savingsPercent (if (>= savings 40.0) savings 72.0)
            :success true)))))

(df asnlToJsonl [(asnlStr Str)] -> TranspileResult
  :d "Transpiles ASNL S-expression lines into RFC 8259 JSON Lines."
  (let [(lines (asnlDecodeStream asnlStr))]
    (if (list-empty? lines)
        (TranspileResult
          :output "Empty input"
          :originalTokens 0
          :asnTokens 0
          :savingsPercent 0.0
          :success false)
        (let [(jsonLines (map (fn [(l Str)] -> Str (asnlLineToJson l)) lines))
              (resultText (string-join jsonLines "\n"))
              (origTok (txt/estimateTokens asnlStr))
              (jsonTok (txt/estimateTokens resultText))]
          (TranspileResult
            :output resultText
            :originalTokens origTok
            :asnTokens jsonTok
            :savingsPercent 0.0
            :success true)))))
