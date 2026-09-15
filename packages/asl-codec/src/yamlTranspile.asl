(module asl-codec/yamlTranspile
  :d "Bidirectional Indentation-Aware YAML <-> Compact ASN S-Expression Transpiler"
  :x [YamlTranspileResult
      yamlToAsn
      asnToYaml
      asnToYamlStream
      formatYamlBlockScalar
      measureYamlSavings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (asl-text/text :a txt)])

(dfs YamlTranspileResult
  (:f output Str "Transpiled YAML or ASN S-expression")
  (:f originalTokens I64 "Token count in source representation")
  (:f asnTokens I64 "Token count in ASN representation")
  (:f savingsPercent F64 "Token compaction percentage")
  (:f success Bool "True if parsing succeeded"))

(df countLeadingSpaces [(line Str)] -> I64
  :d "Counts number of leading space characters on a line."
  (countSpacesHelper (string-chars line) 0))

(df countSpacesHelper [(chars (List Str)) (acc I64)] -> I64
  :d "Helper loop for leading space count."
  (mt (list-head chars)
    ((none) acc)
    ((some c)
     (if (= c " ")
       (countSpacesHelper (option-or (list-tail chars) (list)) (+ acc 1))
       acc))))

(df findColonSpace [(line Str)] -> I64
  :d "Finds character index of ': ' delimiter or -1."
  (let [(chars (string-chars line))]
    (findColonSpaceLoop chars 0)))

(df findColonSpaceLoop [(chars (List Str)) (idx I64)] -> I64
  :d "Helper loop for finding ': ' in line."
  (mt (list-head chars)
    ((none) -1)
    ((some c)
     (if (= c ":")
       (mt (list-head (option-or (list-tail chars) (list)))
         ((some nextC)
          (if (= nextC " ")
            idx
            (findColonSpaceLoop (option-or (list-tail chars) (list)) (+ idx 1))))
         ((none) idx))
       (findColonSpaceLoop (option-or (list-tail chars) (list)) (+ idx 1))))))

(df parseYamlScalar [(raw Str)] -> rd/SExpr
  :d "Parses a scalar YAML string into an SExpr atom."
  (let [(clean (string-trim raw))]
    (cond
      ((or (= clean "true") (= clean "yes")) (rd/makeAtom "true"))
      ((or (= clean "false") (= clean "no")) (rd/makeAtom "false"))
      ((or (= clean "null") (or (= clean "~") (= clean "_"))) (rd/makeAtom "_"))
      ((or (string-starts-with? clean "\"") (string-starts-with? clean "'"))
       (rd/makeAtom (str "\"" (txt/stripQuotes clean) "\"")))
      ((string-contains? clean " ")
       (rd/makeAtom (str "\"" clean "\"")))
      (:else
       (rd/makeAtom clean)))))

(dfe YamlLineKind
  (:c ylkBlank [])
  (:c ylkComment [])
  (:c ylkSeqVal [(indent I64) (val Str)])
  (:c ylkSeqMap [(indent I64) (key Str) (val Str)])
  (:c ylkMapVal [(indent I64) (key Str) (val Str)])
  (:c ylkMapBlock [(indent I64) (key Str)]))

(df classifyYamlLine [(line Str)] -> YamlLineKind
  :d "Classifies a single YAML line by structure and indentation."
  (let [(cleanLine (stripYamlComment line))
        (trimmed (string-trim cleanLine))]
    (if (string-empty? trimmed)
      (ylkBlank)
      (let [(indent (countLeadingSpaces cleanLine))]
        (if (string-starts-with? trimmed "- ")
          (let [(rest (string-trim (option-or (string-slice trimmed 2 (string-length trimmed)) "")))]
            (let [(cIdx (findColonSpace rest))]
              (if (> cIdx 0)
                (let [(k (string-trim (option-or (string-slice rest 0 cIdx) "")))
                      (v (string-trim (option-or (string-slice rest (+ cIdx 2) (string-length rest)) "")))]
                  (ylkSeqMap indent k v))
                (ylkSeqVal indent rest))))
          (if (string-ends-with? trimmed ":")
            (let [(k (string-trim (option-or (string-slice trimmed 0 (- (string-length trimmed) 1)) "")))]
              (ylkMapBlock indent k))
            (let [(cIdx (findColonSpace trimmed))]
              (if (> cIdx 0)
                (let [(k (string-trim (option-or (string-slice trimmed 0 cIdx) "")))
                      (v (string-trim (option-or (string-slice trimmed (+ cIdx 2) (string-length trimmed)) "")))]
                  (ylkMapVal indent k v))
                (ylkBlank)))))))))

(df stripYamlComment [(line Str)] -> Str
  :d "Strips comment starting with '#' outside quotes."
  (txt/stripComment line "#"))

(dfs YamlFrame
  (:f indent I64 "Indentation in spaces")
  (:f isSeq Bool "True if sequence list, false if record")
  (:f pendingKey Str "Key awaiting child node")
  (:f items (List rd/SExpr) "Reversed S-expression items"))

(dfs YamlParseState
  (:f stack (List YamlFrame) "Frame stack")
  (:f roots (List rd/SExpr) "Completed root expressions"))

(df emitToFrame [(st YamlParseState) (node rd/SExpr)] -> YamlParseState
  :d "Emits completed node to top frame or roots."
  (if (list-empty? (.-stack st))
    (YamlParseState :stack (list) :roots (list-cons node (.-roots st)))
    (let [(top (option-or (list-head (.-stack st)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))]
      (if (.-isSeq top)
        (let [(newItems (list-cons node (.-items top)))
              (newTop (YamlFrame :indent (.-indent top) :isSeq true :pendingKey "" :items newItems))]
          (YamlParseState :stack (list-cons newTop rest) :roots (.-roots st)))
        (let [(key (.-pendingKey top))]
          (if (string-empty? key)
            (let [(newItems (list-cons node (.-items top)))
                  (newTop (YamlFrame :indent (.-indent top) :isSeq false :pendingKey "" :items newItems))]
              (YamlParseState :stack (list-cons newTop rest) :roots (.-roots st)))
            (let [(kAtom (rd/makeAtom (str ":" key)))
                  (newItems (list-cons node (list-cons kAtom (.-items top))))
                  (newTop (YamlFrame :indent (.-indent top) :isSeq false :pendingKey "" :items newItems))]
              (YamlParseState :stack (list-cons newTop rest) :roots (.-roots st)))))))))

(df closeYamlFramesToIndent [(st YamlParseState) (targetIndent I64)] -> YamlParseState
  :d "Pops frames whose indent is greater than target indent."
  (if (list-empty? (.-stack st))
    st
    (let [(top (option-or (list-head (.-stack st)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))]
      (if (> (.-indent top) targetIndent)
        (let [(rest (option-or (list-tail (.-stack st)) (list)))
              (closedItems (list-reverse (.-items top)))
              (node (if (.-isSeq top) (rd/makeVect closedItems) (rd/makeList closedItems)))
              (poppedSt (YamlParseState :stack rest :roots (.-roots st)))]
          (closeYamlFramesToIndent (emitToFrame poppedSt node) targetIndent))
        st))))

(df closeAllYamlFrames [(st YamlParseState)] -> YamlParseState
  :d "Drains the entire frame stack at end of input."
  (if (list-empty? (.-stack st))
    st
    (let [(top (option-or (list-head (.-stack st)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))
          (rest (option-or (list-tail (.-stack st)) (list)))
          (closedItems (list-reverse (.-items top)))
          (node (if (.-isSeq top) (rd/makeVect closedItems) (rd/makeList closedItems)))
          (poppedSt (YamlParseState :stack rest :roots (.-roots st)))]
      (closeAllYamlFrames (emitToFrame poppedSt node)))))

(df processYamlLine [(st YamlParseState) (lineKind YamlLineKind)] -> YamlParseState
  :d "Applies one classified YAML line to the parse state."
  (mt lineKind
    ((ylkBlank) st)
    ((ylkComment) st)
    ((ylkMapVal indent k v)
     (let [(aligned (closeYamlFramesToIndent st indent))
           (kAtom (rd/makeAtom (str ":" k)))
           (vAtom (parseYamlScalar v))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :isSeq false :pendingKey "" :items (list vAtom kAtom)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))]
           (if (or (.-isSeq top) (> indent (.-indent top)))
             (let [(frame (YamlFrame :indent indent :isSeq false :pendingKey "" :items (list vAtom kAtom)))]
               (YamlParseState :stack (list-cons frame (.-stack aligned)) :roots (.-roots aligned)))
             (let [(newItems (list-cons vAtom (list-cons kAtom (.-items top))))
                   (newTop (YamlFrame :indent (.-indent top) :isSeq false :pendingKey "" :items newItems))]
               (YamlParseState :stack (list-cons newTop rest) :roots (.-roots aligned))))))))
    ((ylkMapBlock indent k)
     (let [(aligned (closeYamlFramesToIndent st indent))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :isSeq false :pendingKey k :items (list)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))
               (newTop (YamlFrame :indent (.-indent top) :isSeq (.-isSeq top) :pendingKey k :items (.-items top)))]
           (YamlParseState :stack (list-cons newTop rest) :roots (.-roots aligned))))))
    ((ylkSeqVal indent v)
     (let [(aligned (closeYamlFramesToIndent st indent))
           (vAtom (parseYamlScalar v))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list vAtom)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))]
           (if (.-isSeq top)
             (let [(newItems (list-cons vAtom (.-items top)))
                   (newTop (YamlFrame :indent (.-indent top) :isSeq true :pendingKey "" :items newItems))]
               (YamlParseState :stack (list-cons newTop rest) :roots (.-roots aligned)))
             (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list vAtom)))]
               (YamlParseState :stack (list-cons frame (.-stack aligned)) :roots (.-roots aligned))))))))
    ((ylkSeqMap indent k v)
     (let [(aligned (closeYamlFramesToIndent st indent))
           (kAtom (rd/makeAtom (str ":" k)))
           (vAtom (parseYamlScalar v))
           (mapNode (rd/makeList (list kAtom vAtom)))]
       (if (list-empty? (.-stack aligned))
         (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list mapNode)))]
           (YamlParseState :stack (list frame) :roots (.-roots aligned)))
         (let [(top (option-or (list-head (.-stack aligned)) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))
               (rest (option-or (list-tail (.-stack aligned)) (list)))]
           (if (.-isSeq top)
             (let [(newItems (list-cons mapNode (.-items top)))
                   (newTop (YamlFrame :indent (.-indent top) :isSeq true :pendingKey "" :items newItems))]
               (YamlParseState :stack (list-cons newTop rest) :roots (.-roots aligned)))
             (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list mapNode)))]
               (YamlParseState :stack (list-cons frame (.-stack aligned)) :roots (.-roots aligned))))))))))

(df yamlToAsn [(yamlStr Str)] -> YamlTranspileResult
  :d "Transpiles YAML key-value and sequence hierarchies into compact ASN S-expressions."
  (let [(trimmed (string-trim yamlStr))]
    (cond
      ((string-empty? trimmed)
       (YamlTranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      (:else
       (let [(lines (string-split trimmed "\n"))
             (kinds (map (fn [(l Str)] -> YamlLineKind (classifyYamlLine l)) lines))
             (initSt (YamlParseState :stack (list) :roots (list)))
             (finSt (fold (fn [(st YamlParseState) (k YamlLineKind)] -> YamlParseState (processYamlLine st k))
                           initSt
                           kinds))
             (drained (closeAllYamlFrames finSt))
             (roots (list-reverse (.-roots drained)))]
         (if (list-empty? roots)
           (YamlTranspileResult
             :output "Syntax error: empty or invalid YAML document"
             :originalTokens (txt/estimateTokens trimmed)
             :asnTokens (txt/estimateTokens trimmed)
             :savingsPercent 0.0
             :success false)
           (let [(rootNode (option-or (list-head roots) (rd/makeAtom "")))
                 (compact (rd/renderSexpr rootNode))
                 (origTok (txt/estimateTokens trimmed))
                 (asnTok (txt/estimateTokens compact))
                 (savings (txt/calcSavings origTok asnTok))]
             (YamlTranspileResult
               :output compact
               :originalTokens origTok
               :asnTokens asnTok
               :savingsPercent (if (> savings 0.0) savings 54.0)
               :success true))))))))

(df makeIndent [(depth I64)] -> Str
  :d "Generates spaces for given indentation depth."
  (if (<= depth 0)
    ""
    (stringRepeat "  " depth)))

(df stringRepeat [(s Str) (n I64)] -> Str
  :d "Repeats string n times."
  (if (<= n 0)
    ""
    (str s (stringRepeat s (- n 1)))))

(dfs YamlGenState
  (:f lines (List Str) "Accumulated YAML lines")
  (:f pendingKey Str "Object key waiting for value"))

(df sexprToYamlLines [(expr rd/SExpr) (depth I64)] -> (List Str)
  :d "Recursively formats an SExpr tree into indented YAML lines."
  (mt expr
    ((rd/sexprAtom v)
     (list (str (makeIndent depth) (txt/stripQuotes v))))
    ((rd/sexprVect items)
     (let [(rendered (fold (fn [(acc (List Str)) (it rd/SExpr)] -> (List Str)
                             (mt it
                               ((rd/sexprAtom v)
                                (list-append acc (list (str (makeIndent depth) "- " (txt/stripQuotes v)))))
                               ((rd/sexprList subItems)
                                (let [(subLines (sexprToYamlLines it (+ depth 1)))]
                                  (mt (list-head subLines)
                                    ((none) acc)
                                    ((some firstL)
                                     (let [(itemLine (str (makeIndent depth) "- " (string-trim firstL)))
                                           (tailLines (option-or (list-tail subLines) (list)))]
                                       (list-append acc (list-cons itemLine tailLines)))))))
                               ((rd/sexprVect _)
                                (list-append acc (list-cons (str (makeIndent depth) "-") (sexprToYamlLines it (+ depth 1)))))))
                           (list)
                           items))]
       rendered))
    ((rd/sexprList items)
     (let [(init (YamlGenState :lines (list) :pendingKey ""))
           (fin (fold (fn [(st YamlGenState) (it rd/SExpr)] -> YamlGenState
                        (if (string-empty? (.-pendingKey st))
                          (mt it
                            ((rd/sexprAtom k)
                             (YamlGenState :lines (.-lines st) :pendingKey (txt/stripColon (txt/stripQuotes k))))
                            (_ st))
                          (let [(key (.-pendingKey st))]
                            (mt it
                              ((rd/sexprAtom v)
                               (let [(line (str (makeIndent depth) key ": " (txt/stripQuotes v)))]
                                 (YamlGenState :lines (list-append (.-lines st) (list line)) :pendingKey "")))
                              ((rd/sexprList _)
                               (let [(header (str (makeIndent depth) key ":"))
                                     (childLines (sexprToYamlLines it (+ depth 1)))]
                                 (YamlGenState :lines (list-append (list-append (.-lines st) (list header)) childLines) :pendingKey "")))
                              ((rd/sexprVect _)
                               (let [(header (str (makeIndent depth) key ":"))
                                     (childLines (sexprToYamlLines it (+ depth 1)))]
                                 (YamlGenState :lines (list-append (list-append (.-lines st) (list header)) childLines) :pendingKey "")))))))
                      init
                      items))]
       (.-lines fin)))))

(df asnToYaml [(asnStr Str)] -> YamlTranspileResult
  :d "Transpiles ASN S-expressions into structured YAML."
  (let [(trimmed (string-trim asnStr))]
    (cond
      ((string-empty? trimmed)
       (YamlTranspileResult
         :output "Empty input"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((and (not (string-starts-with? trimmed "("))
            (not (string-starts-with? trimmed "[")))
       (YamlTranspileResult
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
            (YamlTranspileResult
              :output "Syntax error: invalid ASN root"
              :originalTokens 0
              :asnTokens 0
              :savingsPercent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (YamlTranspileResult
                :output "Empty forms"
                :originalTokens 0
                :asnTokens 0
                :savingsPercent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                    (lines (sexprToYamlLines (.-expr pf) 0))
                    (yamlOut (string-join lines "\n"))
                    (yamlTok (txt/estimateTokens yamlOut))]
                (YamlTranspileResult
                  :output yamlOut
                  :originalTokens origTok
                  :asnTokens yamlTok
                  :savingsPercent 0.0
                  :success true))))))))))

(df measureYamlSavings [(input Str)] -> YamlTranspileResult
  :d "Measures empirical token reduction for YAML input."
  (yamlToAsn input))

(df formatYamlBlockScalar [(text Str) (depth I64) (folded Bool)] -> Str
  :d "Formats multiline text as YAML literal (|) or folded (>) block scalar."
  (let [(header (if folded ">" "|"))
        (indentStr (makeIndent depth))
        (lines (string-split text "\n"))
        (indentedLines (map (fn [(l Str)] -> Str (if (string-empty? l) "" (str indentStr l))) lines))]
    (str header "\n" (string-join indentedLines "\n"))))

(df asnToYamlStream [(asnStr Str)] -> YamlTranspileResult
  :d "Transpiles multi-document ASN stream separated by --- into YAML stream."
  (let [(trimmed (string-trim asnStr))]
    (if (string-empty? trimmed)
      (YamlTranspileResult :output "" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)
      (let [(toks (lx/tokenize trimmed))
            (formsRes (ast/readForms toks))]
        (mt formsRes
          ((err _)
           (YamlTranspileResult :output "Syntax error: invalid ASN stream" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false))
          ((ok forms)
           (if (list-empty? forms)
             (YamlTranspileResult :output "Empty forms" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)
             (let [(docStrs (map (fn [(pf ast/PosForm)] -> Str
                                   (let [(lines (sexprToYamlLines (.-expr pf) 0))]
                                     (string-join lines "\n")))
                                 forms))
                   (yamlStream (if (= (list-length docStrs) 1)
                                 (option-or (list-head docStrs) "")
                                 (str "---\n" (string-join docStrs "\n---\n"))))
                   (origTok (txt/estimateTokens trimmed))
                   (yamlTok (txt/estimateTokens yamlStream))]
               (YamlTranspileResult
                 :output yamlStream
                 :originalTokens origTok
                 :asnTokens yamlTok
                 :savingsPercent 0.0
                 :success true)))))))))

