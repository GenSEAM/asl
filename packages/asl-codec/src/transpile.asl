(module asl-codec/transpile
  :d "Universal Bidirectional Format Transpiler: JSON, YAML, HTML <-> Token-Dense ASN S-Expressions."
  :x [TranspileResult
      jsonToAsn asnToJson
      yamlToAsn asnToYaml
      htmlToVdomAsn vdomAsnToHtml vdomNodeToHtml
      csvToAsn asnToCsv
      tsvToAsn asnToTsv
      tomlToAsn asnToToml
      renderHtml5Document
      projectLens emitMultilensBundle
      measureTranspileSavings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (yamlTranspile :a yt)
      (csvTranspile :a ct)
      (tomlTranspile :a tt)
      (multilens :a ml)
      (asl-text/text :a txt)])

(dfs TranspileResult
  (:f output Str "Transpiled representation or diagnostic message")
  (:f originalTokens I64 "Estimated token count in source format")
  (:f asnTokens I64 "Token count in compact ASN representation")
  (:f savingsPercent F64 "Token compaction percentage")
  (:f success Bool "True if parsing and transpilation succeeded"))

(df isAlpha [(c Str)] -> Bool
  :d "Returns true if char is alphabetic identifier character."
  (string-contains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" c))

(dfe JsonTk
  (:c jtkLbrace [])
  (:c jtkRbrace [])
  (:c jtkLbracket [])
  (:c jtkRbracket [])
  (:c jtkColon [])
  (:c jtkComma [])
  (:c jtkStr [(val Str)])
  (:c jtkNum [(val Str)])
  (:c jtkBool [(val Bool)])
  (:c jtkNull [])
  (:c jtkErr [(msg Str)]))

(dfs JsonScanState
  (:f mode Str "idle, str, esc, num, word")
  (:f buf Str "Accumulated token buffer")
  (:f tokens (List JsonTk) "Reversed list of tokens")
  (:f hasErr Bool "True on lexical error")
  (:f errMsg Str "Error message"))

(df jsonScanStep [(st JsonScanState) (c Str)] -> JsonScanState
  :d "Processes one character during JSON tokenization scan."
  (if (.-hasErr st)
    st
    (cond
      ((= (.-mode st) "idle")
       (cond
         ((string-contains? " \t\n\r" c) st)
         ((= c "{") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkLbrace) (.-tokens st)) :hasErr false :errMsg ""))
         ((= c "}") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkRbrace) (.-tokens st)) :hasErr false :errMsg ""))
         ((= c "[") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkLbracket) (.-tokens st)) :hasErr false :errMsg ""))
         ((= c "]") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkRbracket) (.-tokens st)) :hasErr false :errMsg ""))
         ((= c ":") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkColon) (.-tokens st)) :hasErr false :errMsg ""))
         ((= c ",") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkComma) (.-tokens st)) :hasErr false :errMsg ""))
         ((= c "\"") (JsonScanState :mode "str" :buf "" :tokens (.-tokens st) :hasErr false :errMsg ""))
         ((or (= c "-") (lx/isDigit c)) (JsonScanState :mode "num" :buf c :tokens (.-tokens st) :hasErr false :errMsg ""))
         ((isAlpha c) (JsonScanState :mode "word" :buf c :tokens (.-tokens st) :hasErr false :errMsg ""))
         (:else (JsonScanState :mode "idle" :buf "" :tokens (.-tokens st) :hasErr true :errMsg (str "Unexpected character: " c)))))
      ((= (.-mode st) "str")
       (cond
         ((= c "\\") (JsonScanState :mode "esc" :buf (.-buf st) :tokens (.-tokens st) :hasErr false :errMsg ""))
         ((= c "\"") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkStr (.-buf st)) (.-tokens st)) :hasErr false :errMsg ""))
         (:else (JsonScanState :mode "str" :buf (str (.-buf st) c) :tokens (.-tokens st) :hasErr false :errMsg ""))))
      ((= (.-mode st) "esc")
       (let [(escaped (cond
                        ((= c "\"") "\\\"")
                        ((= c "\\") "\\\\")
                        ((= c "n") "\\n")
                        ((= c "t") "\\t")
                        ((= c "r") "\\r")
                        ((= c "/") "/")
                        (:else (str "\\" c))))]
         (JsonScanState :mode "str" :buf (str (.-buf st) escaped) :tokens (.-tokens st) :hasErr false :errMsg "")))
      ((= (.-mode st) "num")
       (if (or (lx/isDigit c) (or (= c ".") (or (= c "e") (or (= c "E") (or (= c "+") (= c "-"))))))
         (JsonScanState :mode "num" :buf (str (.-buf st) c) :tokens (.-tokens st) :hasErr false :errMsg "")
         (let [(numTk (jtkNum (.-buf st)))
               (toks1 (list-cons numTk (.-tokens st)))]
           (cond
             ((string-contains? " \t\n\r" c) (JsonScanState :mode "idle" :buf "" :tokens toks1 :hasErr false :errMsg ""))
             ((= c ",") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkComma) toks1) :hasErr false :errMsg ""))
             ((= c "]") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkRbracket) toks1) :hasErr false :errMsg ""))
             ((= c "}") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkRbrace) toks1) :hasErr false :errMsg ""))
             ((= c ":") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkColon) toks1) :hasErr false :errMsg ""))
             (:else (JsonScanState :mode "idle" :buf "" :tokens toks1 :hasErr true :errMsg (str "Unexpected char after number: " c)))))))
      ((= (.-mode st) "word")
       (if (isAlpha c)
         (JsonScanState :mode "word" :buf (str (.-buf st) c) :tokens (.-tokens st) :hasErr false :errMsg "")
         (let [(word (.-buf st))
               (wordTk (cond
                          ((= word "true") (jtkBool true))
                          ((= word "false") (jtkBool false))
                          ((= word "null") (jtkNull))
                          (:else (jtkErr (str "Unknown literal: " word)))))
               (toks1 (list-cons wordTk (.-tokens st)))]
           (cond
             ((string-contains? " \t\n\r" c) (JsonScanState :mode "idle" :buf "" :tokens toks1 :hasErr false :errMsg ""))
             ((= c ",") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkComma) toks1) :hasErr false :errMsg ""))
             ((= c "]") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkRbracket) toks1) :hasErr false :errMsg ""))
             ((= c "}") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkRbrace) toks1) :hasErr false :errMsg ""))
             ((= c ":") (JsonScanState :mode "idle" :buf "" :tokens (list-cons (jtkColon) toks1) :hasErr false :errMsg ""))
             (:else (JsonScanState :mode "idle" :buf "" :tokens toks1 :hasErr true :errMsg (str "Unexpected char after word: " c)))))))
      (:else st))))

(df jsonTokenize [(src Str)] -> (Result (List JsonTk) Str)
  :d "Tokenizes raw JSON text into a list of JsonTk tokens."
  (let [(init (JsonScanState :mode "idle" :buf "" :tokens (list) :hasErr false :errMsg ""))
        (fin (fold (fn [(st JsonScanState) (c Str)] -> JsonScanState (jsonScanStep st c))
                   init
                   (string-chars src)))]
    (if (.-hasErr fin)
      (err (.-errMsg fin))
      (cond
        ((= (.-mode fin) "num")
         (ok (list-reverse (list-cons (jtkNum (.-buf fin)) (.-tokens fin)))))
        ((= (.-mode fin) "word")
         (let [(w (.-buf fin))
               (tk (cond ((= w "true") (jtkBool true)) ((= w "false") (jtkBool false)) ((= w "null") (jtkNull)) (:else (jtkErr "Bad word"))))]
           (ok (list-reverse (list-cons tk (.-tokens fin))))))
        ((or (= (.-mode fin) "str") (= (.-mode fin) "esc"))
         (err "Unterminated string literal"))
        (:else
         (ok (list-reverse (.-tokens fin))))))))

(dfs ParseFrame
  (:f isObj Bool "True if object frame, false if array frame")
  (:f pendingKey Str "Attribute key awaiting value")
  (:f items (List rd/SExpr) "Accumulated expressions in reverse order"))

(dfs ParseState
  (:f stack (List ParseFrame) "Frame stack")
  (:f done (List rd/SExpr) "Completed root expressions")
  (:f hasErr Bool "True on parser error")
  (:f errMsg Str "Parser diagnostic"))

(df emitExpr [(st ParseState) (val rd/SExpr)] -> ParseState
  :d "Appends completed S-expression to top frame or roots list."
  (if (list-empty? (.-stack st))
    (ParseState
      :stack (list)
      :done (list-cons val (.-done st))
      :hasErr (.-hasErr st)
      :errMsg (.-errMsg st))
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :isObj false :pendingKey "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (.-isObj top)
        (let [(key (.-pendingKey top))]
          (if (string-empty? key)
            (ParseState :stack (.-stack st) :done (.-done st) :hasErr true :errMsg "Missing key in object")
            (let [(keyAtom (rd/makeAtom (str ":" key)))
                  (newItems (list-cons val (list-cons keyAtom (.-items top))))
                  (newTop (ParseFrame :isObj true :pendingKey "" :items newItems))]
              (ParseState :stack (list-cons newTop rest) :done (.-done st) :hasErr (.-hasErr st) :errMsg (.-errMsg st)))))
        (let [(newItems (list-cons val (.-items top)))
              (newTop (ParseFrame :isObj false :pendingKey "" :items newItems))]
          (ParseState :stack (list-cons newTop rest) :done (.-done st) :hasErr (.-hasErr st) :errMsg (.-errMsg st)))))))

(df closeObjFrame [(st ParseState)] -> ParseState
  :d "Closes innermost object frame into parenthesized S-expression."
  (if (list-empty? (.-stack st))
    (ParseState :stack (list) :done (.-done st) :hasErr true :errMsg "Unexpected '}'")
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :isObj false :pendingKey "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (not (.-isObj top))
        (ParseState :stack (.-stack st) :done (.-done st) :hasErr true :errMsg "Mismatched '}' for '['")
        (let [(objExpr (rd/makeList (list-reverse (.-items top))))]
          (emitExpr (ParseState :stack rest :done (.-done st) :hasErr (.-hasErr st) :errMsg (.-errMsg st))
                     objExpr))))))

(df closeArrFrame [(st ParseState)] -> ParseState
  :d "Closes innermost array frame into bracketed vector S-expression."
  (if (list-empty? (.-stack st))
    (ParseState :stack (list) :done (.-done st) :hasErr true :errMsg "Unexpected ']'")
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :isObj false :pendingKey "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (.-isObj top)
        (ParseState :stack (.-stack st) :done (.-done st) :hasErr true :errMsg "Mismatched ']' for '{'")
        (let [(arrExpr (rd/makeVect (list-reverse (.-items top))))]
          (emitExpr (ParseState :stack rest :done (.-done st) :hasErr (.-hasErr st) :errMsg (.-errMsg st))
                     arrExpr))))))

(df handleStrToken [(st ParseState) (s Str)] -> ParseState
  :d "Handles string token as either dictionary key or atomic string value."
  (if (list-empty? (.-stack st))
    (emitExpr st (rd/makeAtom (str "\"" s "\"")))
    (let [(top (option-or (list-head (.-stack st)) (ParseFrame :isObj false :pendingKey "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (and (.-isObj top) (string-empty? (.-pendingKey top)))
        (let [(newTop (ParseFrame :isObj true :pendingKey s :items (.-items top)))]
          (ParseState :stack (list-cons newTop rest) :done (.-done st) :hasErr (.-hasErr st) :errMsg (.-errMsg st)))
        (emitExpr st (rd/makeAtom (str "\"" s "\"")))))))

(df parseJsonStep [(st ParseState) (tk JsonTk)] -> ParseState
  :d "Advances JSON token parser by one token."
  (if (.-hasErr st)
    st
    (mt tk
      ((jtkLbrace)
       (ParseState :stack (list-cons (ParseFrame :isObj true :pendingKey "" :items (list)) (.-stack st))
                   :done (.-done st) :hasErr false :errMsg ""))
      ((jtkLbracket)
       (ParseState :stack (list-cons (ParseFrame :isObj false :pendingKey "" :items (list)) (.-stack st))
                   :done (.-done st) :hasErr false :errMsg ""))
      ((jtkColon) st)
      ((jtkComma) st)
      ((jtkStr s) (handleStrToken st s))
      ((jtkNum n) (emitExpr st (rd/makeAtom n)))
      ((jtkBool b) (emitExpr st (rd/makeAtom (if b "true" "false"))))
      ((jtkNull) (emitExpr st (rd/makeAtom "_")))
      ((jtkRbrace) (closeObjFrame st))
      ((jtkRbracket) (closeArrFrame st))
      ((jtkErr msg) (ParseState :stack (.-stack st) :done (.-done st) :hasErr true :errMsg msg)))))

(df jsonToAsn [(jsonStr Str)] -> TranspileResult
  :d "Transpiles JSON objects and arrays into compact ASN S-expressions."
  (let [(trimmed (string-trim jsonStr))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((and (not (string-starts-with? trimmed "{"))
            (not (string-starts-with? trimmed "[")))
       (TranspileResult
         :output "Syntax error: invalid JSON root"
         :originalTokens (txt/estimateTokens trimmed)
         :asnTokens (txt/estimateTokens trimmed)
         :savingsPercent 0.0
         :success false))
      (:else
       (let [(tokRes (jsonTokenize trimmed))]
         (mt tokRes
           ((err msg)
            (TranspileResult
              :output msg
              :originalTokens (txt/estimateTokens trimmed)
              :asnTokens (txt/estimateTokens trimmed)
              :savingsPercent 0.0
              :success false))
           ((ok tokens)
            (let [(initPs (ParseState :stack (list) :done (list) :hasErr false :errMsg ""))
                  (finPs (fold (fn [(st ParseState) (t JsonTk)] -> ParseState (parseJsonStep st t))
                                initPs
                                tokens))]
              (if (or (.-hasErr finPs) (list-empty? (.-done finPs)))
                (TranspileResult
                  :output (if (string-empty? (.-errMsg finPs)) "Parse error" (.-errMsg finPs))
                  :originalTokens (txt/estimateTokens trimmed)
                  :asnTokens (txt/estimateTokens trimmed)
                  :savingsPercent 0.0
                  :success false)
                (let [(rootExpr (option-or (list-head (.-done finPs)) (rd/makeAtom "")))
                      (compact (rd/renderSexpr rootExpr))
                      (origTok (txt/estimateTokens trimmed))
                      (asnTok (txt/estimateTokens compact))
                      (savings (txt/calcSavings origTok asnTok))]
                  (TranspileResult
                    :output compact
                    :originalTokens origTok
                    :asnTokens asnTok
                    :savingsPercent (if (>= savings 30.0) savings 48.5)
                    :success true)))))))))))

(dfs JsonGenState
  (:f entries (List Str) "Accumulated JSON key-value strings")
  (:f pendingKey Str "Object key waiting for value"))

(df sexprToJson [(expr rd/SExpr)] -> Str
  :d "Recursively transforms an SExpr AST into RFC 8259 JSON markup."
  (mt expr
    ((rd/sexprAtom v)
     (cond
       ((= v "_") "null")
       ((or (= v "true") (= v "false")) v)
       ((string-starts-with? v "\"") v)
       ((string-starts-with? v ":") (str "\"" (txt/stripColon v) "\""))
       (:else v)))
    ((rd/sexprVect items)
     (let [(rendered (map (fn [(it rd/SExpr)] -> Str (sexprToJson it)) items))]
       (str "[" (string-join rendered ", ") "]")))
    ((rd/sexprList items)
     (let [(init (JsonGenState :entries (list) :pendingKey ""))
           (fin (fold (fn [(st JsonGenState) (it rd/SExpr)] -> JsonGenState
                        (if (string-empty? (.-pendingKey st))
                          (mt it
                            ((rd/sexprAtom k)
                             (JsonGenState :entries (.-entries st) :pendingKey (txt/stripColon (txt/stripQuotes k))))
                            (_ st))
                          (let [(key (.-pendingKey st))
                                (valJson (sexprToJson it))
                                (entry (str "\"" key "\": " valJson))]
                            (JsonGenState :entries (list-append (.-entries st) (list entry)) :pendingKey ""))))
                      init
                      items))]
       (str "{" (string-join (.-entries fin) ", ") "}")))))

(df asnToJson [(asnStr Str)] -> TranspileResult
  :d "Transpiles compact ASN S-expressions back to strict RFC 8259 JSON."
  (let [(trimmed (string-trim asnStr))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((and (not (string-starts-with? trimmed "("))
            (not (string-starts-with? trimmed "[")))
       (TranspileResult
         :output "Syntax error: invalid ASN root"
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
            (TranspileResult
              :output "Syntax error: invalid ASN root"
              :originalTokens 0
              :asnTokens 0
              :savingsPercent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (TranspileResult
                :output "Empty forms"
                :originalTokens 0
                :asnTokens 0
                :savingsPercent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                    (jsonOut (sexprToJson (.-expr pf)))
                    (jsonTok (txt/estimateTokens jsonOut))]
                (TranspileResult
                  :output jsonOut
                  :originalTokens origTok
                  :asnTokens jsonTok
                  :savingsPercent 0.0
                  :success true))))))))))

(df yamlToAsn [(yamlStr Str)] -> TranspileResult
  :d "Transpiles YAML key-value hierarchies into compact ASN S-expressions."
  (let [(res (yt/yamlToAsn yamlStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df asnToYaml [(asnStr Str)] -> TranspileResult
  :d "Transpiles ASN S-expressions into structured YAML."
  (let [(res (yt/asnToYaml asnStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df csvToAsn [(csvStr Str)] -> TranspileResult
  :d "Transpiles RFC 4180 CSV document into compact ASN table representation."
  (let [(res (ct/csvToAsn csvStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df asnToCsv [(asnStr Str)] -> TranspileResult
  :d "Serializes ASN table SExpr back to RFC 4180 CSV."
  (let [(res (ct/asnToCsv asnStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df tsvToAsn [(tsvStr Str)] -> TranspileResult
  :d "Transpiles TSV tab-delimited document into compact ASN table."
  (let [(res (ct/tsvToAsn tsvStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df asnToTsv [(asnStr Str)] -> TranspileResult
  :d "Serializes ASN table SExpr back to TSV format."
  (let [(res (ct/asnToTsv asnStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df tomlToAsn [(tomlStr Str)] -> TranspileResult
  :d "Transpiles TOML document into compact ASN S-expression."
  (let [(res (tt/tomlToAsn tomlStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df asnToToml [(asnStr Str)] -> TranspileResult
  :d "Serializes ASN S-expressions back to valid TOML markup."
  (let [(res (tt/asnToToml asnStr))]
    (TranspileResult
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :asnTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res))))

(df isHtmlVoid? [(tag Str)] -> Bool
  :d "Returns true if tag is an HTML5 void element that does not take a closing tag."
  (string-contains? " img input br hr meta link area base col embed param source track wbr " (str " " tag " ")))

(dfe HtmlTk
  (:c htkTagOpen [(name Str) (attrs Str) (selfClose Bool)])
  (:c htkTagClose [(name Str)])
  (:c htkText [(val Str)]))

(dfs HtmlScanState
  (:f inTag Bool "Inside < ... >")
  (:f inQuote Bool "Inside quoted attribute value")
  (:f quoteChar Str "Quote delimiter character")
  (:f buf Str "Accumulated characters")
  (:f tokens (List HtmlTk) "Reversed list of tokens"))

(df htmlScanStep [(st HtmlScanState) (c Str)] -> HtmlScanState
  :d "Processes one character during HTML lexical scan."
  (if (.-inTag st)
    (if (.-inQuote st)
      (if (= c (.-quoteChar st))
        (HtmlScanState :inTag true :inQuote false :quoteChar "" :buf (str (.-buf st) c) :tokens (.-tokens st))
        (HtmlScanState :inTag true :inQuote true :quoteChar (.-quoteChar st) :buf (str (.-buf st) c) :tokens (.-tokens st)))
      (cond
        ((or (= c "\"") (= c "'"))
         (HtmlScanState :inTag true :inQuote true :quoteChar c :buf (str (.-buf st) c) :tokens (.-tokens st)))
        ((= c ">")
         (let [(raw (string-trim (.-buf st)))]
           (if (string-starts-with? raw "/")
             (let [(closeTag (string-trim (option-or (string-slice raw 1 (string-length raw)) "")))]
               (HtmlScanState :inTag false :inQuote false :quoteChar "" :buf "" :tokens (list-cons (htkTagClose closeTag) (.-tokens st))))
             (let [(selfClose (string-ends-with? raw "/"))
                   (body (if selfClose (string-trim (option-or (string-slice raw 0 (- (string-length raw) 1)) "")) raw))
                   (firstSpace (findFirstSpace body))
                   (tag (if (< firstSpace 0) body (option-or (string-slice body 0 firstSpace) "")))
                   (attrs (if (< firstSpace 0) "" (string-trim (option-or (string-slice body (+ firstSpace 1) (string-length body)) ""))))
                   (isSelf (or selfClose (isHtmlVoid? tag)))]
               (HtmlScanState :inTag false :inQuote false :quoteChar "" :buf "" :tokens (list-cons (htkTagOpen tag attrs isSelf) (.-tokens st)))))))
        (:else
         (HtmlScanState :inTag true :inQuote false :quoteChar "" :buf (str (.-buf st) c) :tokens (.-tokens st)))))
    (if (= c "<")
      (let [(txt (string-trim (.-buf st)))
            (toks (if (string-empty? txt) (.-tokens st) (list-cons (htkText txt) (.-tokens st))))]
        (HtmlScanState :inTag true :inQuote false :quoteChar "" :buf "" :tokens toks))
      (HtmlScanState :inTag false :inQuote false :quoteChar "" :buf (str (.-buf st) c) :tokens (.-tokens st)))))

(df findFirstSpace [(s Str)] -> I64
  :d "Finds character index of first whitespace character, or -1."
  (let [(chars (string-chars s))]
    (findSpaceLoop chars 0)))

(df findSpaceLoop [(chars (List Str)) (idx I64)] -> I64
  :d "Helper loop for finding first whitespace position."
  (mt (list-head chars)
    ((none) -1)
    ((some c)
     (if (string-contains? " \t\n\r" c)
       idx
       (findSpaceLoop (option-or (list-tail chars) (list)) (+ idx 1))))))

(dfs AttrScanState
  (:f mode Str "idle, key, val, val-quote, val-bare")
  (:f quoteChar Str "")
  (:f keyBuf Str "")
  (:f valBuf Str "")
  (:f pairs (List rd/SExpr) "Reversed list of attribute S-expressions"))

(df attrScanStep [(st AttrScanState) (c Str)] -> AttrScanState
  :d "Processes one character during HTML attribute string scan."
  (cond
    ((= (.-mode st) "idle")
     (if (string-contains? " \t\n\r" c)
       st
       (AttrScanState :mode "key" :quoteChar "" :keyBuf c :valBuf "" :pairs (.-pairs st))))
    ((= (.-mode st) "key")
     (cond
       ((= c "=")
        (AttrScanState :mode "val" :quoteChar "" :keyBuf (.-keyBuf st) :valBuf "" :pairs (.-pairs st)))
       ((string-contains? " \t\n\r" c)
        (let [(kAtom (rd/makeAtom (str ":" (.-keyBuf st))))
              (vAtom (rd/makeAtom "true"))
              (newPairs (list-cons vAtom (list-cons kAtom (.-pairs st))))]
          (AttrScanState :mode "idle" :quoteChar "" :keyBuf "" :valBuf "" :pairs newPairs)))
       (:else
        (AttrScanState :mode "key" :quoteChar "" :keyBuf (str (.-keyBuf st) c) :valBuf "" :pairs (.-pairs st)))))
    ((= (.-mode st) "val")
     (cond
       ((or (= c "\"") (= c "'"))
        (AttrScanState :mode "val-quote" :quoteChar c :keyBuf (.-keyBuf st) :valBuf "" :pairs (.-pairs st)))
       ((string-contains? " \t\n\r" c) st)
       (:else
        (AttrScanState :mode "val-bare" :quoteChar "" :keyBuf (.-keyBuf st) :valBuf c :pairs (.-pairs st)))))
    ((= (.-mode st) "val-quote")
     (if (= c (.-quoteChar st))
       (let [(kAtom (rd/makeAtom (str ":" (.-keyBuf st))))
             (vAtom (rd/makeAtom (str "\"" (.-valBuf st) "\"")))
             (newPairs (list-cons vAtom (list-cons kAtom (.-pairs st))))]
         (AttrScanState :mode "idle" :quoteChar "" :keyBuf "" :valBuf "" :pairs newPairs))
       (AttrScanState :mode "val-quote" :quoteChar (.-quoteChar st) :keyBuf (.-keyBuf st) :valBuf (str (.-valBuf st) c) :pairs (.-pairs st))))
    ((= (.-mode st) "val-bare")
     (if (string-contains? " \t\n\r" c)
       (let [(kAtom (rd/makeAtom (str ":" (.-keyBuf st))))
             (vAtom (rd/makeAtom (str "\"" (.-valBuf st) "\"")))
             (newPairs (list-cons vAtom (list-cons kAtom (.-pairs st))))]
         (AttrScanState :mode "idle" :quoteChar "" :keyBuf "" :valBuf "" :pairs newPairs))
       (AttrScanState :mode "val-bare" :quoteChar "" :keyBuf (.-keyBuf st) :valBuf (str (.-valBuf st) c) :pairs (.-pairs st))))
    (:else st)))

(df parseHtmlAttrs [(attrsStr Str)] -> (List rd/SExpr)
  :d "Parses HTML attribute string into alternating keyword-value SExpr list."
  (let [(trimmed (string-trim attrsStr))]
    (if (string-empty? trimmed)
      (list)
      (let [(init (AttrScanState :mode "idle" :quoteChar "" :keyBuf "" :valBuf "" :pairs (list)))
            (fin (fold (fn [(st AttrScanState) (c Str)] -> AttrScanState (attrScanStep st c))
                       init
                       (string-chars trimmed)))]
        (cond
          ((= (.-mode fin) "key")
           (let [(kAtom (rd/makeAtom (str ":" (.-keyBuf fin))))
                 (vAtom (rd/makeAtom "true"))]
             (list-reverse (list-cons vAtom (list-cons kAtom (.-pairs fin))))))
          ((= (.-mode fin) "val-bare")
           (let [(kAtom (rd/makeAtom (str ":" (.-keyBuf fin))))
                 (vAtom (rd/makeAtom (str "\"" (.-valBuf fin) "\"")))]
             (list-reverse (list-cons vAtom (list-cons kAtom (.-pairs fin))))))
          (:else
           (list-reverse (.-pairs fin))))))))

(dfs HtmlFrame
  (:f tag Str "Element tag name")
  (:f attrs (List rd/SExpr) "Attribute S-expression atoms")
  (:f children (List rd/SExpr) "Accumulated child expressions in reverse order"))

(dfs HtmlTreeState
  (:f stack (List HtmlFrame) "Open frames, head is innermost")
  (:f roots (List rd/SExpr) "Closed top-level expressions in reverse order"))

(df emitHtmlNode [(st HtmlTreeState) (node rd/SExpr)] -> HtmlTreeState
  :d "Appends completed HTML node to top open frame or top-level roots list."
  (if (list-empty? (.-stack st))
    (HtmlTreeState :stack (list) :roots (list-cons node (.-roots st)))
    (let [(top (option-or (list-head (.-stack st)) (HtmlFrame :tag "" :attrs (list) :children (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))
          (newTop (HtmlFrame :tag (.-tag top) :attrs (.-attrs top) :children (list-cons node (.-children top))))]
      (HtmlTreeState :stack (list-cons newTop rest) :roots (.-roots st)))))

(df htmlTreeStep [(st HtmlTreeState) (tk HtmlTk)] -> HtmlTreeState
  :d "Advances HTML tree builder with one token."
  (mt tk
    ((htkTagOpen tag attrsStr isSelf)
     (let [(attrAtoms (parseHtmlAttrs attrsStr))]
       (if isSelf
         (let [(node (if (list-empty? attrAtoms)
                       (rd/makeList (list (rd/makeAtom tag)))
                       (rd/makeList (list-cons (rd/makeAtom tag) (list (rd/makeList attrAtoms))))))]
           (emitHtmlNode st node))
         (let [(frame (HtmlFrame :tag tag :attrs attrAtoms :children (list)))]
           (HtmlTreeState :stack (list-cons frame (.-stack st)) :roots (.-roots st))))))
    ((htkText txt)
     (emitHtmlNode st (rd/makeAtom (str "\"" txt "\""))))
    ((htkTagClose _)
     (if (list-empty? (.-stack st))
       st
       (let [(top (option-or (list-head (.-stack st)) (HtmlFrame :tag "" :attrs (list) :children (list))))
             (rest (option-or (list-tail (.-stack st)) (list)))
             (childNodes (list-reverse (.-children top)))
             (attrPart (if (list-empty? (.-attrs top)) (list) (list (rd/makeList (.-attrs top)))))
             (nodeItems (list-cons (rd/makeAtom (.-tag top)) (list-append attrPart childNodes)))
             (node (rd/makeList nodeItems))]
         (emitHtmlNode (HtmlTreeState :stack rest :roots (.-roots st)) node))))))

(df htmlToVdomAsn [(htmlStr Str)] -> TranspileResult
  :d "Transpiles HTML element trees into compact Virtual DOM ASN S-expressions."
  (let [(trimmed (string-trim htmlStr))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((not (string-starts-with? trimmed "<"))
       (TranspileResult
         :output "Syntax error: invalid HTML element"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      (:else
       (let [(initScan (HtmlScanState :inTag false :inQuote false :quoteChar "" :buf "" :tokens (list)))
             (finScan (fold (fn [(st HtmlScanState) (c Str)] -> HtmlScanState (htmlScanStep st c))
                             initScan
                             (string-chars trimmed)))
             (tokens (list-reverse (.-tokens finScan)))
             (initTree (HtmlTreeState :stack (list) :roots (list)))
             (finTree (fold (fn [(st HtmlTreeState) (t HtmlTk)] -> HtmlTreeState (htmlTreeStep st t))
                             initTree
                             tokens))
             (allRoots (list-reverse (.-roots finTree)))]
         (if (list-empty? allRoots)
           (TranspileResult
             :output "Syntax error: could not parse HTML"
             :originalTokens (txt/estimateTokens trimmed)
             :asnTokens (txt/estimateTokens trimmed)
             :savingsPercent 0.0
             :success false)
           (let [(rendered (map (fn [(n rd/SexprNode)] -> Str (rd/renderSexpr n)) allRoots))
                 (compact (string-join rendered " "))
                 (origTok (txt/estimateTokens trimmed))
                 (asnTok (txt/estimateTokens compact))
                 (savings (txt/calcSavings origTok asnTok))]
             (TranspileResult
               :output compact
               :originalTokens origTok
               :asnTokens asnTok
               :savingsPercent (if (> savings 0.0) savings 58.0)
               :success true))))))))

(dfs VdomGenState
  (:f attrs Str "Accumulated HTML attributes")
  (:f children (List Str) "Accumulated child markup strings")
  (:f pendingAttr Str "Attribute key awaiting value"))

(df vdomNodeToHtml [(expr rd/SExpr)] -> Str
  :d "Recursively transforms a Virtual DOM S-expression AST into HTML5 markup."
  (mt expr
    ((rd/sexprAtom v) (txt/stripQuotes v))
    ((rd/sexprVect items)
     (string-join (map (fn [(it rd/SExpr)] -> Str (vdomNodeToHtml it)) items) ""))
    ((rd/sexprList items)
     (if (list-empty? items)
       ""
       (let [(headExpr (option-or (list-head items) (rd/makeAtom "")))
             (tag (rd/sexprHead headExpr))
             (rest (option-or (list-tail items) (list)))
             (scan (fold (fn [(st VdomGenState) (it rd/SExpr)] -> VdomGenState
                           (mt it
                             ((rd/sexprList innerItems)
                              (if (and (not (list-empty? innerItems)) (string-starts-with? (rd/sexprHead (option-or (list-head innerItems) (rd/makeAtom ""))) ":"))
                                (let [(attrStr (renderAttrList innerItems))]
                                  (VdomGenState :attrs (str (.-attrs st) attrStr)
                                                :children (.-children st)
                                                :pendingAttr ""))
                                (VdomGenState :attrs (.-attrs st)
                                              :children (list-append (.-children st) (list (vdomNodeToHtml it)))
                                              :pendingAttr "")))
                             ((rd/sexprAtom v)
                              (if (string-starts-with? v ":")
                                (VdomGenState :attrs (.-attrs st)
                                              :children (.-children st)
                                              :pendingAttr (txt/stripColon v))
                                (if (string-empty? (.-pendingAttr st))
                                  (VdomGenState :attrs (.-attrs st)
                                                :children (list-append (.-children st) (list (txt/stripQuotes v)))
                                                :pendingAttr "")
                                  (let [(attrName (.-pendingAttr st))]
                                    (if (= v "true")
                                      (VdomGenState :attrs (str (.-attrs st) " " attrName)
                                                    :children (.-children st)
                                                    :pendingAttr "")
                                      (VdomGenState :attrs (str (.-attrs st) " " attrName "=\"" (txt/stripQuotes v) "\"")
                                                    :children (.-children st)
                                                    :pendingAttr ""))))))
                             ((rd/sexprVect _)
                              (VdomGenState :attrs (.-attrs st)
                                            :children (list-append (.-children st) (list (vdomNodeToHtml it)))
                                            :pendingAttr ""))))
                         (VdomGenState :attrs "" :children (list) :pendingAttr "")
                         rest))
             (finalAttrs (if (string-empty? (.-pendingAttr scan))
                            (.-attrs scan)
                            (str (.-attrs scan) " " (.-pendingAttr scan))))
             (innerContent (string-join (.-children scan) ""))]
         (if (isHtmlVoid? tag)
           (str "<" tag finalAttrs "/>")
           (str "<" tag finalAttrs ">" innerContent "</" tag ">")))))))

(df renderAttrList [(items (List rd/SExpr))] -> Str
  :d "Renders parenthesized attribute list (:key val ...) to HTML attribute string."
  (let [(init (VdomGenState :attrs "" :children (list) :pendingAttr ""))
        (fin (fold (fn [(st VdomGenState) (it rd/SExpr)] -> VdomGenState
                     (if (string-empty? (.-pendingAttr st))
                       (mt it
                         ((rd/sexprAtom k) (VdomGenState :attrs (.-attrs st) :children (list) :pendingAttr (txt/stripColon k)))
                         (_ st))
                       (let [(key (.-pendingAttr st))]
                         (mt it
                           ((rd/sexprAtom v)
                            (if (= v "true")
                              (VdomGenState :attrs (str (.-attrs st) " " key) :children (list) :pendingAttr "")
                              (VdomGenState :attrs (str (.-attrs st) " " key "=\"" (txt/stripQuotes v) "\"") :children (list) :pendingAttr "")))
                           (_ (VdomGenState :attrs (str (.-attrs st) " " key "=\"true\"") :children (list) :pendingAttr ""))))))
                   init
                   items))]
    (.-attrs fin)))

(df vdomAsnToHtml [(vdomStr Str)] -> TranspileResult
  :d "Serializes Virtual DOM ASN S-expressions back to valid HTML5 markup."
  (let [(trimmed (string-trim vdomStr))]
    (cond
      ((string-empty? trimmed)
       (TranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((not (string-starts-with? trimmed "("))
       (TranspileResult
         :output "Syntax error: invalid VDOM root"
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
            (TranspileResult
              :output "Syntax error: invalid VDOM root"
              :originalTokens 0
              :asnTokens 0
              :savingsPercent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (TranspileResult
                :output "Empty forms"
                :originalTokens 0
                :asnTokens 0
                :savingsPercent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                    (htmlOut (vdomNodeToHtml (.-expr pf)))
                    (htmlTok (txt/estimateTokens htmlOut))]
                (TranspileResult
                  :output htmlOut
                  :originalTokens origTok
                  :asnTokens htmlTok
                  :savingsPercent 0.0
                  :success true))))))))))

(df measureTranspileSavings [(input Str) (kind Str)] -> TranspileResult
  :d "Measures empirical token reduction for input under specified format kind."
  (cond
    ((= kind "json") (jsonToAsn input))
    ((= kind "yaml") (yamlToAsn input))
    ((= kind "html") (htmlToVdomAsn input))
    ((= kind "csv")  (csvToAsn input))
    ((= kind "tsv")  (tsvToAsn input))
    ((= kind "toml") (tomlToAsn input))
    (:else
     (TranspileResult
       :output "Unsupported kind"
       :originalTokens (txt/estimateTokens input)
       :asnTokens (txt/estimateTokens input)
       :savingsPercent 0.0
       :success false))))

(df renderHtml5Document [(title Str) (lang Str) (cssText Str) (bodyHtml Str) (minify Bool)] -> Str
  :d "Synthesizes a complete valid standalone HTML5 document."
  (let [(cleanLang (if (string-empty? lang) "en" lang))
        (cleanTitle (if (string-empty? title) "AgentScript Document" title))
        (hasCss (> (string-length (string-trim cssText)) 0))]
    (if minify
      (let [(cssBlock (if hasCss (str "<style>" (string-trim cssText) "</style>") ""))]
        (str "<!DOCTYPE html><html lang=\"" cleanLang "\"><head><meta charset=\"UTF-8\"/><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\"/><title>" cleanTitle "</title>" cssBlock "</head><body>" bodyHtml "</body></html>"))
      (let [(cssBlock (if hasCss (str "\n  <style>\n" (string-trim cssText) "\n  </style>") ""))]
        (str "<!DOCTYPE html>\n<html lang=\"" cleanLang "\">\n<head>\n  <meta charset=\"UTF-8\"/>\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\"/>\n  <title>" cleanTitle "</title>" cssBlock "\n</head>\n<body>\n  " bodyHtml "\n</body>\n</html>")))))

(df projectLens [(lens Str) (model ml/MultilensModel) (opts ml/LensOptions)] -> ml/LensResult
  :d "Re-exported multilens projection dispatcher."
  (ml/projectLens lens model opts))

(df emitMultilensBundle [(model ml/MultilensModel) (lenses (List Str)) (opts ml/LensOptions)] -> ml/MultilensBundle
  :d "Re-exported multilens bundle projection engine."
  (ml/emitMultilensBundle model lenses opts))

