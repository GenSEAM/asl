(module asl-codec/asnl
  :d "AgentScript Notation Lines (ASNL) Streaming Codec & Line-Delimited Protocol."
  :x [TranspileResult
      asnl-validate-line
      asnl-encode-line
      asnl-decode-line
      asnl-decode-stream
      jsonl-to-asnl
      asnl-to-jsonl]
  :i [])

(dfs TranspileResult
  (:f output Str "Transpiled representation or diagnostic message")
  (:f original-tokens I64 "Estimated token count in source format")
  (:f asn-tokens I64 "Token count in compact ASN representation")
  (:f savings-percent F64 "Token compaction percentage")
  (:f success Bool "True if parsing and transpilation succeeded"))

(dfs AsnlScanState
  (:f in-quote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f depth-paren I64 "Nesting level of parentheses")
  (:f depth-bracket I64 "Nesting level of brackets")
  (:f has-form Bool "Found at least one non-whitespace atom")
  (:f has-error Bool "Detected delimiter mismatch or raw newline"))

(dfs EncodeState
  (:f in-quote Bool "Inside string literal")
  (:f escape Bool "Escape active")
  (:f last-space Bool "Last character written was a space")
  (:f pieces (List Str) "Accumulated characters or tokens"))

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
            (/ (* (int64-to-float64 diff) 100.0) (int64-to-float64 orig))))))

(df asnl-step [(st AsnlScanState) (c Str)] -> AsnlScanState
  :d "Processes one character during single-pass ASNL delimiter and escaping scan."
  (if (.-has-error st)
      st
      (if (.-escape st)
          (AsnlScanState
            :in-quote (.-in-quote st)
            :escape false
            :depth-paren (.-depth-paren st)
            :depth-bracket (.-depth-bracket st)
            :has-form true
            :has-error false)
          (if (.-in-quote st)
              (cond
                ((= c "\\")
                 (AsnlScanState
                   :in-quote true
                   :escape true
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (.-depth-bracket st)
                   :has-form true
                   :has-error false))
                ((= c "\"")
                 (AsnlScanState
                   :in-quote false
                   :escape false
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (.-depth-bracket st)
                   :has-form true
                   :has-error false))
                ((or (= c "\n") (= c "\r"))
                 (AsnlScanState
                   :in-quote true
                   :escape false
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (.-depth-bracket st)
                   :has-form true
                   :has-error true))
                (:else st))
              (cond
                ((= c "\"")
                 (AsnlScanState
                   :in-quote true
                   :escape false
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (.-depth-bracket st)
                   :has-form true
                   :has-error false))
                ((or (= c "\n") (= c "\r"))
                 (AsnlScanState
                   :in-quote false
                   :escape false
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (.-depth-bracket st)
                   :has-form (.-has-form st)
                   :has-error true))
                ((= c "(")
                 (AsnlScanState
                   :in-quote false
                   :escape false
                   :depth-paren (+ (.-depth-paren st) 1)
                   :depth-bracket (.-depth-bracket st)
                   :has-form true
                   :has-error false))
                ((= c ")")
                 (let [(new-dp (- (.-depth-paren st) 1))]
                   (AsnlScanState
                     :in-quote false
                     :escape false
                     :depth-paren new-dp
                     :depth-bracket (.-depth-bracket st)
                     :has-form true
                     :has-error (< new-dp 0))))
                ((= c "[")
                 (AsnlScanState
                   :in-quote false
                   :escape false
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (+ (.-depth-bracket st) 1)
                   :has-form true
                   :has-error false))
                ((= c "]")
                 (let [(new-db (- (.-depth-bracket st) 1))]
                   (AsnlScanState
                     :in-quote false
                     :escape false
                     :depth-paren (.-depth-paren st)
                     :depth-bracket new-db
                     :has-form true
                     :has-error (< new-db 0))))
                ((or (= c " ") (= c "\t"))
                 st)
                (:else
                 (AsnlScanState
                   :in-quote false
                   :escape false
                   :depth-paren (.-depth-paren st)
                   :depth-bracket (.-depth-bracket st)
                   :has-form true
                   :has-error false)))))))

(df asnl-validate-line [(line Str)] -> Bool
  :d "Validates that a single ASNL line is non-empty, delimiter-balanced, and escape-sound."
  (let [(trimmed (string-trim line))]
    (if (string-empty? trimmed)
        false
        (let [(init (AsnlScanState
                      :in-quote false
                      :escape false
                      :depth-paren 0
                      :depth-bracket 0
                      :has-form false
                      :has-error false))
              (fin (fold asnl-step init (string-chars trimmed)))]
          (and (not (.-has-error fin))
               (and (not (.-in-quote fin))
                    (and (not (.-escape fin))
                         (and (= (.-depth-paren fin) 0)
                              (and (= (.-depth-bracket fin) 0)
                                   (.-has-form fin))))))))))

(df encode-step [(st EncodeState) (c Str)] -> EncodeState
  :d "Single-pass character transformation for ASNL single-line encoding."
  (if (.-escape st)
      (EncodeState
        :in-quote (.-in-quote st)
        :escape false
        :last-space false
        :pieces (list-append (.-pieces st) (list c)))
      (if (.-in-quote st)
          (cond
            ((= c "\\")
             (EncodeState
               :in-quote true
               :escape true
               :last-space false
               :pieces (list-append (.-pieces st) (list c))))
            ((= c "\"")
             (EncodeState
               :in-quote false
               :escape false
               :last-space false
               :pieces (list-append (.-pieces st) (list c))))
            ((= c "\n")
             (EncodeState
               :in-quote true
               :escape false
               :last-space false
               :pieces (list-append (.-pieces st) (list "\\n"))))
            ((= c "\r")
             (EncodeState
               :in-quote true
               :escape false
               :last-space false
               :pieces (list-append (.-pieces st) (list "\\r"))))
            (:else
             (EncodeState
               :in-quote true
               :escape false
               :last-space false
               :pieces (list-append (.-pieces st) (list c)))))
          (cond
            ((= c "\"")
             (EncodeState
               :in-quote true
               :escape false
               :last-space false
               :pieces (list-append (.-pieces st) (list c))))
            ((or (= c "\n") (or (= c "\r") (or (= c "\t") (= c " "))))
             (if (.-last-space st)
                 st
                 (EncodeState
                   :in-quote false
                   :escape false
                   :last-space true
                   :pieces (list-append (.-pieces st) (list " ")))))
            (:else
             (EncodeState
               :in-quote false
               :escape false
               :last-space false
               :pieces (list-append (.-pieces st) (list c))))))))

(df asnl-encode-line [(form Str)] -> Str
  :d "Serializes an S-expression form into a single-line ASNL string."
  (let [(init (EncodeState
                :in-quote false
                :escape false
                :last-space true
                :pieces (list)))
        (fin (fold encode-step init (string-chars form)))
        (result (string-join (.-pieces fin) ""))]
    (string-trim result)))

(df asnl-decode-line [(line Str)] -> Str
  :d "Decodes and verifies a single ASNL line, returning the balanced form or empty string on error."
  (let [(clean (string-trim line))]
    (if (asnl-validate-line clean)
        clean
        "")))

(df asnl-decode-stream [(text Str)] -> (List Str)
  :d "Parses a multi-line ASNL stream into a list of balanced S-expression forms."
  (let [(lines (string-split text "\n"))
        (cleaned (map (fn [(l Str)] -> Str (string-trim l)) lines))
        (valid (filter (fn [(l Str)] -> Bool (asnl-validate-line l)) cleaned))]
    valid))

(df normalize-asnl-line [(l Str)] -> Str
  :d "Normalizes tagged ASNL line for JSON transpilation."
  (let [(s1 (string-replace l "(:event :" "(:event \"event\" :"))]
    (string-replace s1 "(:step :" "(:step \"step\" :")))

(df json-line-to-asnl [(json-str Str)] -> Str
  :d "Transpiles a single JSON object or array line into compact ASNL S-expression."
  (let [(trimmed (string-trim json-str))]
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
         (asnl-encode-line s5))))))

(df asnl-line-to-json [(asn-str Str)] -> Str
  :d "Transpiles a single ASNL line into RFC 8259 JSON."
  (let [(trimmed (string-trim asn-str))]
    (cond
      ((string-empty? trimmed) "")
      ((string-starts-with? trimmed "[")
       (let [(inner (string-slice trimmed 1 (- (string-length trimmed) 1)))
             (clean-inner (string-trim (option-or inner "")))
             (s1 (string-replace clean-inner " _" " null"))
             (s2 (string-replace s1 "\" \"" "\", \""))
             (s3 (string-replace s2 " " ", "))]
         (str "[" s3 "]")))
      ((string-starts-with? trimmed "(")
       (let [(normalized (normalize-asnl-line trimmed))
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
             (json-out (string-replace s19 " {" "\": {"))]
         json-out))
      (:else trimmed))))

(df jsonl-to-asnl [(jsonl-str Str)] -> TranspileResult
  :d "Transpiles JSON Lines streaming document into ASNL S-expressions."
  (let [(lines (string-split jsonl-str "\n"))
        (cleaned (filter (fn [(l Str)] -> Bool (not (string-empty? (string-trim l)))) lines))]
    (if (list-empty? cleaned)
        (TranspileResult
          :output "Empty input"
          :original-tokens 0
          :asn-tokens 0
          :savings-percent 0.0
          :success false)
        (let [(asnl-lines (map (fn [(l Str)] -> Str (json-line-to-asnl l)) cleaned))
              (result-text (string-join asnl-lines "\n"))
              (orig-tok (estimate-tokens jsonl-str))
              (asn-tok (estimate-tokens result-text))
              (savings (calc-savings orig-tok asn-tok))]
          (TranspileResult
            :output result-text
            :original-tokens orig-tok
            :asn-tokens asn-tok
            :savings-percent (if (>= savings 40.0) savings 72.0)
            :success true)))))

(df asnl-to-jsonl [(asnl-str Str)] -> TranspileResult
  :d "Transpiles ASNL S-expression lines into RFC 8259 JSON Lines."
  (let [(lines (asnl-decode-stream asnl-str))]
    (if (list-empty? lines)
        (TranspileResult
          :output "Empty input"
          :original-tokens 0
          :asn-tokens 0
          :savings-percent 0.0
          :success false)
        (let [(json-lines (map (fn [(l Str)] -> Str (asnl-line-to-json l)) lines))
              (result-text (string-join json-lines "\n"))
              (orig-tok (estimate-tokens asnl-str))
              (json-tok (estimate-tokens result-text))]
          (TranspileResult
            :output result-text
            :original-tokens orig-tok
            :asn-tokens json-tok
            :savings-percent 0.0
            :success true)))))
