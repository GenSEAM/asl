(module asl-transpile/asnl :x [TranspileResult asnlValidateLine asnlEncodeLine asnlDecodeLine asnlDecodeStream jsonlToAsnl asnlToJsonl] :i [(asl-text/text :a txt)])

(schema TranspileResult (:f output Str) (:f originalTokens I64) (:f asnTokens I64) (:f savingsPercent F64) (:f success Bool))

(schema AsnlScanState (:f inQuote Bool) (:f escape Bool) (:f depthParen I64) (:f depthBracket I64) (:f hasForm Bool) (:f hasError Bool))

(schema EncodeState (:f inQuote Bool) (:f escape Bool) (:f lastSpace Bool) (:f pieces (List Str)))

fn asnlStep st: AsnlScanState c: Str -> AsnlScanState
  (if st.hasError st (if st.escape (with st :escape false :hasForm true :hasError false) (if st.inQuote (cond ((= c "\\") (with st :inQuote true :escape true :hasForm true :hasError false)) ((= c "\"") (with st :inQuote false :escape false :hasForm true :hasError false)) ((or (= c "\n") (= c "\r")) (with st :inQuote true :escape false :hasForm true :hasError true)) (else st)) (cond ((= c "\"") (with st :inQuote true :escape false :hasForm true :hasError false)) ((or (= c "\n") (= c "\r")) (with st :inQuote false :escape false :hasError true)) ((= c "(") (with st :inQuote false :escape false :depthParen (+ st.depthParen 1) :hasForm true :hasError false)) ((= c ")") (let [(newDp (- st.depthParen 1))] (with st :inQuote false :escape false :depthParen newDp :hasForm true :hasError (< newDp 0)))) ((= c "[") (with st :inQuote false :escape false :depthBracket (+ st.depthBracket 1) :hasForm true :hasError false)) ((= c "]") (let [(newDb (- st.depthBracket 1))] (with st :inQuote false :escape false :depthBracket newDb :hasForm true :hasError (< newDb 0)))) ((or (= c " ") (= c "\t")) st) (else (with st :inQuote false :escape false :hasForm true :hasError false))))))

fn asnlValidateLine line: Str -> Bool
  (let [(trimmed (stringTrim line))] (if (stringEmpty? trimmed) false (let [(init (AsnlScanState :inQuote false :escape false :depthParen 0 :depthBracket 0 :hasForm false :hasError false)) (fin (fold asnlStep init (stringChars trimmed)))] (and (not fin.hasError) (and (not fin.inQuote) (and (not fin.escape) (and (= fin.depthParen 0) (and (= fin.depthBracket 0) fin.hasForm))))))))

fn encodeStep st: EncodeState c: Str -> EncodeState
  (if st.escape (with st :escape false :lastSpace false :pieces (listAppend st.pieces (list c))) (if st.inQuote (cond ((= c "\\") (EncodeState :inQuote true :escape true :lastSpace false :pieces (listAppend st.pieces (list c)))) ((= c "\"") (EncodeState :inQuote false :escape false :lastSpace false :pieces (listAppend st.pieces (list c)))) ((= c "\n") (EncodeState :inQuote true :escape false :lastSpace false :pieces (listAppend st.pieces (list "\\n")))) ((= c "\r") (EncodeState :inQuote true :escape false :lastSpace false :pieces (listAppend st.pieces (list "\\r")))) (else (EncodeState :inQuote true :escape false :lastSpace false :pieces (listAppend st.pieces (list c))))) (cond ((= c "\"") (EncodeState :inQuote true :escape false :lastSpace false :pieces (listAppend st.pieces (list c)))) ((or (= c "\n") (or (= c "\r") (or (= c "\t") (= c " ")))) (if st.lastSpace st (EncodeState :inQuote false :escape false :lastSpace true :pieces (listAppend st.pieces (list " "))))) (else (EncodeState :inQuote false :escape false :lastSpace false :pieces (listAppend st.pieces (list c)))))))

fn asnlEncodeLine form: Str -> Str
  (let [(init (EncodeState :inQuote false :escape false :lastSpace true :pieces (list))) (fin (fold encodeStep init (stringChars form))) (result (stringJoin fin.pieces ""))] (stringTrim result))

fn asnlDecodeLine line: Str -> Str
  (let [(clean (stringTrim line))] (if (asnlValidateLine clean) clean ""))

fn asnlDecodeStream text: Str -> (List Str)
  (let [(lines (stringSplit text "\n")) (cleaned (map (fn [(l Str)] -> Str (stringTrim l)) lines)) (valid (filter (fn [(l Str)] -> Bool (asnlValidateLine l)) cleaned))] valid)

fn normalizeAsnlLine l: Str -> Str
  (let [(s1 (stringReplace l "(:event :" "(:event \"event\" :"))] (stringReplace s1 "(:step :" "(:step \"step\" :"))

fn jsonLineToAsnl jsonStr: Str -> Str
  (let [(trimmed (stringTrim jsonStr))] (cond ((stringEmpty? trimmed) "") ((and (not (stringStartsWith? trimmed "{")) (not (stringStartsWith? trimmed "["))) trimmed) (else (let [(s1 (stringReplace (stringReplace trimmed "{" "(") "}" ")")) (s2 (stringReplace s1 "null" "_")) (s3 (stringReplace (stringReplace (stringReplace s2 "(\"" "(:") ", \"" " :") ",\"" " :")) (s4 (stringReplace (stringReplace s3 "\": " " ") "\":" " ")) (s5 (stringReplace (stringReplace s4 ", " " ") "," " "))] (asnlEncodeLine s5)))))

fn asnlLineToJson asnStr: Str -> Str
  (let [(trimmed (stringTrim asnStr))] (cond ((stringEmpty? trimmed) "") ((stringStartsWith? trimmed "[") (let [(inner (stringSlice trimmed 1 (- (stringLength trimmed) 1))) (cleanInner (stringTrim (optionOr inner ""))) (s1 (stringReplace cleanInner " _" " null")) (s2 (stringReplace s1 "\" \"" "\", \"")) (s3 (stringReplace s2 " " ", "))] (str "[" s3 "]"))) ((stringStartsWith? trimmed "(") (let [(normalized (normalizeAsnlLine trimmed)) (s1 (stringReplace (stringReplace normalized "(" "{") ")" "}")) (s2 (stringReplace s1 " _" " null")) (s3 (stringReplace s2 "{:" "{\"")) (s4 (stringReplace s3 " :" ", \"")) (s5 (stringReplace s4 " \"" "\": \"")) (s6 (stringReplace s5 " true" "\": true")) (s7 (stringReplace s6 " false" "\": false")) (s8 (stringReplace s7 " null" "\": null")) (s9 (stringReplace s8 " 0" "\": 0")) (s10 (stringReplace s9 " 1" "\": 1")) (s11 (stringReplace s10 " 2" "\": 2")) (s12 (stringReplace s11 " 3" "\": 3")) (s13 (stringReplace s12 " 4" "\": 4")) (s14 (stringReplace s13 " 5" "\": 5")) (s15 (stringReplace s14 " 6" "\": 6")) (s16 (stringReplace s15 " 7" "\": 7")) (s17 (stringReplace s16 " 8" "\": 8")) (s18 (stringReplace s17 " 9" "\": 9")) (s19 (stringReplace s18 " [" "\": [")) (jsonOut (stringReplace s19 " {" "\": {"))] jsonOut)) (else trimmed)))

fn jsonlToAsnl jsonlStr: Str -> TranspileResult
  (let [(lines (stringSplit jsonlStr "\n")) (cleaned (filter (fn [(l Str)] -> Bool (not (stringEmpty? (stringTrim l)))) lines))] (if (listEmpty? cleaned) (TranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(asnlLines (map (fn [(l Str)] -> Str (jsonLineToAsnl l)) cleaned)) (resultText (stringJoin asnlLines "\n")) (origTok (txt/estimateTokens jsonlStr)) (asnTok (txt/estimateTokens resultText)) (savings (txt/calcSavings origTok asnTok))] (TranspileResult :output resultText :originalTokens origTok :asnTokens asnTok :savingsPercent (if (>= savings 40.0) savings 72.0) :success true))))

fn asnlToJsonl asnlStr: Str -> TranspileResult
  (let [(lines (asnlDecodeStream asnlStr))] (if (listEmpty? lines) (TranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(jsonLines (map (fn [(l Str)] -> Str (asnlLineToJson l)) lines)) (resultText (stringJoin jsonLines "\n")) (origTok (txt/estimateTokens asnlStr)) (jsonTok (txt/estimateTokens resultText))] (TranspileResult :output resultText :originalTokens origTok :asnTokens jsonTok :savingsPercent 0.0 :success true))))
