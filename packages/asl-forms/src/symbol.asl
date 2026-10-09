(module asl-forms/symbol :x [SymbolDef languageOf! aslSymbols findSymbol findSymbolInLang lineOf outlineReceipt readSymbolReceipt readAnchorReceipt nearestSymbols] :i [(asl-syntax/core/source :a src) (asl-syntax/core/symbols :a csym) (asl-syntax/core/outline :a cout) (asl-syntax/registry :a reg) (asl-syntax/asl/symbols :a aslsym) (asl-syntax/markdownSymbols :a mdsym) (asl-syntax/text :a txt)])


(schema SymbolDef
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f depth Int64)
  (:f container String))

fn fromSyntaxDef d: csym/SymbolDef -> SymbolDef
  (SymbolDef :name (csym/symbolName d)
             :kind (csym/symbolKind d)
             :start (csym/symbolStart d)
             :end (csym/symbolEnd d)
             :depth (csym/symbolDepth d)
             :container (csym/symbolContainer d))

fn supportedLanguage? lang: String -> Bool
  (listContains? (list "asl" "asn" "markdown" "md" "text") lang)

fn languageOf! path: String -> String
  (let [(lang (reg/languageOf! path))]
    (if (supportedLanguage? lang)
      lang
      ""))

fn aslSymbols text: String -> (List SymbolDef)
  (map fromSyntaxDef (aslsym/aslSymbols text))

fn findInDefs syms: (List csym/SymbolDef) sym: String -> (Pair (Option SymbolDef) (List SymbolDef))
  (let [(hit (csym/findSymbolDotted syms sym))]
    (pair (mt hit ((some h) (some (fromSyntaxDef h))) ((none) (none)))
          (map fromSyntaxDef syms)))

fn textSymbols text: String -> (List csym/SymbolDef)
  (let [(s (src/sourceFromString "" text))]
    (txt/textSymbols s text))

fn findSymbolInLang text: String lang: String sym: String -> (Pair (Option SymbolDef) (List SymbolDef))
  (cond
    ((or (= lang "asl") (= lang "asn"))
     (findInDefs (aslsym/aslSymbols text) sym))
    ((or (= lang "markdown") (= lang "md"))
     (let [(syms (mdsym/markdownSymbols text))
           (hit (mdsym/findSymbol text sym))]
       (pair (mt hit ((ok h) (some (fromSyntaxDef h))) ((err _) (none)))
             (map fromSyntaxDef syms))))
    ((= lang "text")
     (findInDefs (textSymbols text) sym))
    (else
     (let [(aslList (aslsym/aslSymbols text))]
       (if (not (listEmpty? aslList))
         (findInDefs aslList sym)
         (let [(mdList (mdsym/markdownSymbols text))]
           (if (not (listEmpty? mdList))
             (let [(hit (mdsym/findSymbol text sym))]
               (pair (mt hit ((ok h) (some (fromSyntaxDef h))) ((err _) (none)))
                     (map fromSyntaxDef mdList)))
             (findInDefs (textSymbols text) sym)))))))

fn findSymbol text: String sym: String -> (Pair (Option SymbolDef) (List SymbolDef))
  (findSymbolInLang text "" sym)

fn lineOf text: String offset: Int64 -> Int64
  (let [(s (src/sourceFromString "" text))
        (safeOff (max 0 (min (stringLength text) offset)))]
    (optionOr (src/sourceLineAt s safeOff) 1))

fn outlineReceipt file: String lang: String text: String -> String
  (cond
    ((or (= lang "asl") (= lang "asn"))
     (aslsym/aslOutlineReceipt file lang text))
    ((or (= lang "markdown") (= lang "md"))
     (mdsym/markdownOutlineReceipt file text))
    ((= lang "text")
     (txt/textOutlineReceipt file text))
    (else
     (cout/formatOutlineReceiptFromText file lang (list) text)))

fn readAnchorReceipt file: String text: String anchor: String occurrence: Int64 limit: Int64 -> String
  (txt/readAnchorReceipt file text anchor occurrence limit)

fn readSymbolReceipt file: String lang: String text: String sym: String -> String
  (cond
    ((or (= lang "markdown") (= lang "md"))
     (mdsym/markdownReadSymbolReceipt file text sym))
    (else
     (let [(found (findSymbolInLang text lang sym))
           (hit (pairFirst found))
           (syms (pairSecond found))]
       (mt hit
         ((none)
          (let [(names (map (fn [(d SymbolDef)] -> String d.name) syms))
                (near (csym/nearestNames sym names 5))]
            (str "(:read :status :rejected :error ERR_SYMBOL_NOT_FOUND :file \"" (cout/escapeAsnValue file)
                 "\" :symbol \"" (cout/escapeAsnValue sym)
                 "\" :language \"" (cout/escapeAsnValue lang)
                 "\" :symbolsIndexed " (stringFromInt64 (listLength syms))
                 " :nearest [" (stringJoin (map (fn [(s String)] -> String (str "\"" (cout/escapeAsnValue s) "\"")) near) " ")
                 "] :see \"(:help :op read)\")")))
         ((some d)
          (let [(first (lineOf text d.start))
                (last (lineOf text (max d.start (- d.end 1))))
                (content (optionOr (stringSlice text d.start d.end) ""))]
            (str "(:read :file \"" (cout/escapeAsnValue file)
                 "\" :symbol \"" (cout/escapeAsnValue sym)
                 "\" :kind \"" (cout/escapeAsnValue d.kind)
                 "\" :language \"" (cout/escapeAsnValue lang)
                 "\" :start " (stringFromInt64 first)
                 " :end " (stringFromInt64 last)
                 " :content \"" (cout/escapeAsnValue content) "\")")))))))

fn nearestSymbols sym: String syms: (List SymbolDef) k: Int64 -> (List String)
  (let [(names (map (fn [(d SymbolDef)] -> String d.name) syms))]
    (csym/nearestNames sym names k))
