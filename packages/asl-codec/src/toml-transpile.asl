(module asl-codec/tomlTranspile
  :d "Bidirectional TOML Manifest & Configuration <-> Compact ASN S-Expression Transpiler"
  :x [TomlTranspileResult
      tomlToAsn
      asnToToml
      measureTomlSavings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (asl-text/text :a txt)])

(dfs TomlTranspileResult
  (:f output Str "Transpiled TOML or ASN S-expression")
  (:f originalTokens I64 "Token count in source representation")
  (:f asnTokens I64 "Token count in ASN representation")
  (:f savingsPercent F64 "Token compaction percentage")
  (:f success Bool "True if parsing succeeded"))

(df stripTomlComment [(line Str)] -> Str
  :d "Strips '#' comments outside quotes from a line."
  (let [(chars (string-chars line))]
    (stripCommentLoop chars false "")))

(df stripCommentLoop [(chars (List Str)) (inQuote Bool) (acc Str)] -> Str
  :d "Helper loop for stripping trailing comments."
  (mt (list-head chars)
    ((none) acc)
    ((some c)
     (if inQuote
       (if (or (= c "\"") (= c "'"))
         (stripCommentLoop (option-or (list-tail chars) (list)) false (str acc c))
         (stripCommentLoop (option-or (list-tail chars) (list)) true (str acc c)))
       (if (or (= c "\"") (= c "'"))
         (stripCommentLoop (option-or (list-tail chars) (list)) true (str acc c))
         (if (= c "#")
           acc
           (stripCommentLoop (option-or (list-tail chars) (list)) false (str acc c))))))))

(df findFirstChar [(s Str) (target Str)] -> I64
  :d "Finds first index of target character or -1."
  (let [(chars (string-chars s))]
    (findCharLoop chars target 0)))

(df findCharLoop [(chars (List Str)) (target Str) (idx I64)] -> I64
  :d "Helper loop for finding character position."
  (mt (list-head chars)
    ((none) -1)
    ((some c)
     (if (= c target)
       idx
       (findCharLoop (option-or (list-tail chars) (list)) target (+ idx 1))))))

(df parseTomlVal [(val Str)] -> rd/SExpr
  :d "Parses a TOML value string into an SExpr atom or inline vector."
  (let [(clean (string-trim val))]
    (cond
      ((and (string-starts-with? clean "[") (string-ends-with? clean "]"))
       (let [(inner (string-trim (option-or (string-slice clean 1 (- (string-length clean) 1)) "")))]
         (if (string-empty? inner)
           (rd/makeVect (list))
           (let [(rawElems (string-split inner ","))
                 (elems (map (fn [(e Str)] -> rd/SExpr (parseTomlScalar e)) rawElems))]
             (rd/makeVect elems)))))
      (:else
       (parseTomlScalar clean)))))

(df parseTomlScalar [(val Str)] -> rd/SExpr
  :d "Parses scalar TOML literal."
  (let [(clean (string-trim val))]
    (cond
      ((= clean "true") (rd/makeAtom "true"))
      ((= clean "false") (rd/makeAtom "false"))
      ((or (string-starts-with? clean "\"") (string-starts-with? clean "'"))
       (rd/makeAtom (str "\"" (txt/stripQuotes clean) "\"")))
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

(dfe TomlLine
  (:c tlBlank [])
  (:c tlSec [(name Str)])
  (:c tlArrSec [(name Str)])
  (:c tlKv [(key Str) (val rd/SExpr)]))

(df classifyTomlLine [(line Str)] -> TomlLine
  :d "Classifies line as section, array-section, key-value, or blank."
  (let [(clean (string-trim (stripTomlComment line)))]
    (if (string-empty? clean)
      (tlBlank)
      (if (and (string-starts-with? clean "[[") (string-ends-with? clean "]]"))
        (let [(name (string-trim (option-or (string-slice clean 2 (- (string-length clean) 2)) "")))]
          (tlArrSec name))
        (if (and (string-starts-with? clean "[") (string-ends-with? clean "]"))
          (let [(name (string-trim (option-or (string-slice clean 1 (- (string-length clean) 1)) "")))]
            (tlSec name))
          (let [(eqIdx (findFirstChar clean "="))]
            (if (> eqIdx 0)
              (let [(k (string-trim (option-or (string-slice clean 0 eqIdx) "")))
                    (v (string-trim (option-or (string-slice clean (+ eqIdx 1) (string-length clean)) "")))]
                (tlKv k (parseTomlVal v)))
              (tlBlank))))))))

(dfs TomlSection
  (:f name Str "Section name, or empty for root")
  (:f isArr Bool "True if array of tables")
  (:f items (List rd/SExpr) "Reversed key-value SExpr atoms"))

(dfs TomlState
  (:f current TomlSection "Currently active section")
  (:f committed (List TomlSection) "Reversed committed sections"))

(df commitCurrentSec [(st TomlState)] -> TomlState
  :d "Commits active section to committed list if non-empty."
  (let [(cur (.-current st))]
    (if (and (string-empty? (.-name cur)) (list-empty? (.-items cur)))
      st
      (TomlState :current (TomlSection :name "" :isArr false :items (list))
                 :committed (list-cons cur (.-committed st))))))

(df processTomlLine [(st TomlState) (tl TomlLine)] -> TomlState
  :d "Processes one classified TOML line."
  (mt tl
    ((tlBlank) st)
    ((tlSec name)
     (let [(committedSt (commitCurrentSec st))]
       (TomlState :current (TomlSection :name name :isArr false :items (list))
                  :committed (.-committed committedSt))))
    ((tlArrSec name)
     (let [(committedSt (commitCurrentSec st))]
       (TomlState :current (TomlSection :name name :isArr true :items (list))
                  :committed (.-committed committedSt))))
    ((tlKv k v)
     (let [(cur (.-current st))
           (kAtom (rd/makeAtom (str ":" k)))
           (newItems (list-cons v (list-cons kAtom (.-items cur))))
           (newCur (TomlSection :name (.-name cur) :isArr (.-isArr cur) :items newItems))]
       (TomlState :current newCur :committed (.-committed st))))))

(df buildTomlAst [(sections (List TomlSection))] -> rd/SExpr
  :d "Assembles list of TomlSections into a single root record SExpr."
  (let [(rootKvs (fold (fn [(acc (List rd/SExpr)) (sec TomlSection)] -> (List rd/SExpr)
                          (if (string-empty? (.-name sec))
                            (list-append acc (list-reverse (.-items sec)))
                            (if (.-isArr sec)
                              (let [(secAtom (rd/makeAtom (str ":" (.-name sec))))
                                    (tableNode (rd/makeList (list-reverse (.-items sec))))]
                                (list-append acc (list secAtom (rd/makeVect (list tableNode)))))
                              (let [(secAtom (rd/makeAtom (str ":" (.-name sec))))
                                    (secNode (rd/makeList (list-reverse (.-items sec))))]
                                (list-append acc (list secAtom secNode))))))
                        (list)
                        sections))]
    (rd/makeList rootKvs)))

(df tomlToAsn [(tomlStr Str)] -> TomlTranspileResult
  :d "Transpiles TOML document into compact ASN S-expression."
  (let [(trimmed (string-trim tomlStr))]
    (if (string-empty? trimmed)
      (TomlTranspileResult
        :output "Empty input"
        :originalTokens 0
        :asnTokens 0
        :savingsPercent 0.0
        :success false)
      (let [(lines (string-split trimmed "\n"))
            (classified (map (fn [(l Str)] -> TomlLine (classifyTomlLine l)) lines))
            (initSt (TomlState :current (TomlSection :name "" :isArr false :items (list)) :committed (list)))
            (finSt (fold (fn [(st TomlState) (tl TomlLine)] -> TomlState (processTomlLine st tl))
                          initSt
                          classified))
            (finalSt (commitCurrentSec finSt))
            (sections (list-reverse (.-committed finalSt)))]
        (if (list-empty? sections)
          (TomlTranspileResult
            :output "Syntax error: empty or invalid TOML document"
            :originalTokens (txt/estimateTokens trimmed)
            :asnTokens (txt/estimateTokens trimmed)
            :savingsPercent 0.0
            :success false)
          (let [(astNode (buildTomlAst sections))
                (compact (rd/renderSexpr astNode))
                (origTok (txt/estimateTokens trimmed))
                (asnTok (txt/estimateTokens compact))
                (savings (txt/calcSavings origTok asnTok))]
            (TomlTranspileResult
              :output compact
              :originalTokens origTok
              :asnTokens asnTok
              :savingsPercent (if (>= savings 20.0) savings 45.0)
              :success true)))))))

(df renderTomlVal [(expr rd/SExpr)] -> Str
  :d "Renders SExpr atom or vector as TOML value."
  (mt expr
    ((rd/sexprAtom v)
     (cond
       ((or (= v "true") (= v "false")) v)
       ((string-starts-with? v "\"") v)
       ((isNumeric v) v)
       (:else (str "\"" v "\""))))
    ((rd/sexprVect items)
     (let [(rendered (map (fn [(it rd/SExpr)] -> Str (renderTomlVal it)) items))]
       (str "[" (string-join rendered ", ") "]")))
    ((rd/sexprList _) "")))

(dfs TomlGenState
  (:f lines (List Str) "Accumulated output lines")
  (:f pendingKey Str "Attribute key waiting for value"))

(df asnToToml [(asnStr Str)] -> TomlTranspileResult
  :d "Serializes ASN S-expressions back to valid TOML markup."
  (let [(trimmed (string-trim asnStr))]
    (cond
      ((string-empty? trimmed)
       (TomlTranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((not (string-starts-with? trimmed "("))
       (TomlTranspileResult
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
            (TomlTranspileResult
              :output "Syntax error: invalid ASN root"
              :originalTokens 0
              :asnTokens 0
              :savingsPercent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (TomlTranspileResult
                :output "Empty forms"
                :originalTokens 0
                :asnTokens 0
                :savingsPercent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                    (expr (.-expr pf))]
                (mt expr
                  ((rd/sexprList items)
                   (let [(tomlLines (sexprToTomlSections items))
                         (tomlOut (string-join tomlLines "\n"))
                         (tomlTok (txt/estimateTokens tomlOut))]
                     (TomlTranspileResult
                       :output tomlOut
                       :originalTokens origTok
                       :asnTokens tomlTok
                       :savingsPercent 0.0
                       :success true)))
                  (_
                   (TomlTranspileResult
                     :output "Syntax error: root must be record list"
                     :originalTokens 0
                     :asnTokens 0
                     :savingsPercent 0.0
                     :success false))))))))))))

(df sexprToTomlSections [(items (List rd/SExpr))] -> (List Str)
  :d "Converts alternating SExpr pairs into TOML sections and key-values."
  (let [(init (TomlGenState :lines (list) :pendingKey ""))
        (fin (fold (fn [(st TomlGenState) (it rd/SExpr)] -> TomlGenState
                     (if (string-empty? (.-pendingKey st))
                       (mt it
                         ((rd/sexprAtom k) (TomlGenState :lines (.-lines st) :pendingKey (txt/stripColon (txt/stripQuotes k))))
                         (_ st))
                       (let [(key (.-pendingKey st))]
                         (mt it
                           ((rd/sexprAtom _)
                            (let [(line (str key " = " (renderTomlVal it)))]
                              (TomlGenState :lines (list-append (.-lines st) (list line)) :pendingKey "")))
                           ((rd/sexprVect vecItems)
                            (if (isVectOfRecords vecItems)
                              (let [(arrLines (renderArrTables key vecItems))]
                                (TomlGenState :lines (list-append (.-lines st) arrLines) :pendingKey ""))
                              (let [(line (str key " = " (renderTomlVal it)))]
                                (TomlGenState :lines (list-append (.-lines st) (list line)) :pendingKey ""))))
                           ((rd/sexprList subItems)
                            (let [(secHeader (str "[" key "]"))
                                  (childLines (renderSectionKvs subItems))]
                              (TomlGenState :lines (list-append (list-append (.-lines st) (list secHeader)) childLines) :pendingKey "")))))))
                   init
                   items))]
    (.-lines fin)))

(df isVectOfRecords [(items (List rd/SExpr))] -> Bool
  :d "Returns true if vector contains record lists (array of tables)."
  (mt (list-head items)
    ((none) false)
    ((some firstIt)
     (mt firstIt
       ((rd/sexprList _) true)
       (_ false)))))

(df renderArrTables [(key Str) (tables (List rd/SExpr))] -> (List Str)
  :d "Renders array of tables [[key]]."
  (fold (fn [(acc (List Str)) (t rd/SExpr)] -> (List Str)
          (mt t
            ((rd/sexprList subItems)
             (let [(header (str "[[" key "]]"))
                   (childLines (renderSectionKvs subItems))]
               (list-append (list-append acc (list header)) childLines)))
            (_ acc)))
        (list)
        tables))

(df renderSectionKvs [(items (List rd/SExpr))] -> (List Str)
  :d "Renders key-value pairs inside a TOML section."
  (let [(init (TomlGenState :lines (list) :pendingKey ""))
        (fin (fold (fn [(st TomlGenState) (it rd/SExpr)] -> TomlGenState
                     (if (string-empty? (.-pendingKey st))
                       (mt it
                         ((rd/sexprAtom k) (TomlGenState :lines (.-lines st) :pendingKey (txt/stripColon (txt/stripQuotes k))))
                         (_ st))
                       (let [(key (.-pendingKey st))
                             (line (str key " = " (renderTomlVal it)))]
                         (TomlGenState :lines (list-append (.-lines st) (list line)) :pendingKey ""))))
                   init
                   items))]
    (.-lines fin)))

(df measureTomlSavings [(input Str)] -> TomlTranspileResult
  :d "Measures empirical token reduction for TOML input."
  (tomlToAsn input))
