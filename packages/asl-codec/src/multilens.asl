(module asl-codec/multilens
  :d "Unified Multilens Document and Entity Model Architecture in Pure ASL"
  :x [MultilensModel
      LensOptions
      LensResult
      MultilensBundle
      defaultLensOptions
      emptyModel
      validateMultilensModel
      parseUnifiedModel
      modelExtractMeta
      modelExtractStyles
      modelExtractContent
      modelExtractData
      modelExtractConfig
      projectLens
      projectLensHtml
      projectLensCss
      projectLensYaml
      projectLensJson
      projectLensToml
      emitMultilensBundle
      measureBundleSavings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (asl-text/text :a txt)
      (cssEmit :a ce)
      (transpile :a tr)
      (yamlTranspile :a yt)
      (tomlTranspile :a tt)])

(dfs MultilensModel
  (:f meta rd/SExpr "Document metadata record")
  (:f styles rd/SExpr "Stylesheet AST declarations and rules")
  (:f content rd/SExpr "Semantic markup content VDOM AST")
  (:f data rd/SExpr "Structured business and telemetry records")
  (:f config rd/SExpr "Runtime options and environmental configuration")
  (:f success Bool "True if model was parsed cleanly")
  (:f errorMsg Str "Error description if parsing failed"))

(dfs LensOptions
  (:f indent I64 "Indentation spaces or level")
  (:f minify Bool "True to minify emitted output")
  (:f standalone Bool "True for standalone document or fragment")
  (:f includeStyles Bool "True to embed styles in HTML head")
  (:f doctype Bool "True to emit doctype in HTML"))

(dfs LensResult
  (:f lens Str "Projection lens format name")
  (:f output Str "Rendered text output")
  (:f originalTokens I64 "Original token count")
  (:f emittedTokens I64 "Emitted token count")
  (:f savingsPercent F64 "Token compaction savings percentage")
  (:f success Bool "True if projection succeeded")
  (:f errorMsg Str "Error message on failure"))

(dfs MultilensBundle
  (:f html Str "Emitted HTML5 output")
  (:f css Str "Emitted CSS stylesheet")
  (:f yaml Str "Emitted YAML configuration")
  (:f json Str "Emitted JSON data")
  (:f toml Str "Emitted TOML configuration")
  (:f artifacts (List LensResult) "List of all generated lens results")
  (:f totalOriginalTokens I64 "Aggregate original tokens")
  (:f totalEmittedTokens I64 "Aggregate emitted tokens")
  (:f success Bool "True if all requested lenses succeeded"))

(df defaultLensOptions [] -> LensOptions
  :d "Returns canonical default lens options."
  (LensOptions
    :indent 2
    :minify false
    :standalone true
    :includeStyles true
    :doctype true))

(df emptyModel [] -> MultilensModel
  :d "Constructs an empty valid MultilensModel."
  (MultilensModel
    :meta (rd/makeList (list))
    :styles (rd/makeList (list))
    :content (rd/makeList (list))
    :data (rd/makeList (list))
    :config (rd/makeList (list))
    :success true
    :errorMsg ""))

(df modelExtractMeta [(m MultilensModel)] -> rd/SExpr
  :d "Extracts metadata AST from model."
  (.-meta m))

(df modelExtractStyles [(m MultilensModel)] -> rd/SExpr
  :d "Extracts stylesheet AST from model."
  (.-styles m))

(df modelExtractContent [(m MultilensModel)] -> rd/SExpr
  :d "Extracts semantic markup content AST from model."
  (.-content m))

(df modelExtractData [(m MultilensModel)] -> rd/SExpr
  :d "Extracts structured data records AST from model."
  (.-data m))

(df modelExtractConfig [(m MultilensModel)] -> rd/SExpr
  :d "Extracts runtime configuration AST from model."
  (.-config m))

(df extractSectionLoop [(items (List rd/SExpr)) (plain Str) (colon Str)] -> rd/SExpr
  :d "Recursive search for section in items list."
  (mt (list-head items)
    ((none) (rd/makeList (list)))
    ((some it)
     (let [(tail (option-or (list-tail items) (list)))]
       (mt it
         ((rd/sexprAtom v)
          (let [(stripped (txt/stripColon v))]
            (if (or (= v plain) (or (= v colon) (= stripped plain)))
              (mt (list-head tail)
                ((some nextIt) nextIt)
                ((none) (rd/makeList (list))))
              (extractSectionLoop tail plain colon))))
         ((rd/sexprList subItems)
          (let [(hd (rd/sexprHead it))
                (stripped (txt/stripColon hd))]
            (if (or (= hd plain) (or (= hd colon) (= stripped plain)))
              it
              (extractSectionLoop tail plain colon))))
         ((rd/sexprVect _)
          (extractSectionLoop tail plain colon)))))))

(df extractSection [(items (List rd/SExpr)) (secName Str)] -> rd/SExpr
  :d "Extracts named section from model items list or returns empty list."
  (let [(plainName (txt/stripColon secName))
        (colonName (str ":" plainName))]
    (extractSectionLoop items plainName colonName)))

(df validateMultilensModel [(input Str)] -> Bool
  :d "Validates that input string is a non-empty well-formed MultilensModel S-expression."
  (let [(trimmed (string-trim input))]
    (if (or (string-empty? trimmed) (not (string-starts-with? trimmed "(")))
      false
      (let [(toks (lx/tokenize trimmed))
            (formsRes (ast/readForms toks))]
        (mt formsRes
          ((err _) false)
          ((ok forms)
           (if (list-empty? forms)
             false
             (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                   (expr (.-expr pf))]
               (mt expr
                 ((rd/sexprList items)
                  (let [(hd (rd/sexprHead expr))]
                    (or (= hd ":doc") (= hd "doc"))))
                 (_ false))))))))))

(df parseUnifiedModel [(input Str)] -> MultilensModel
  :d "Parses a unified model S-expression into a MultilensModel record."
  (let [(trimmed (string-trim input))]
    (cond
      ((string-empty? trimmed)
       (MultilensModel
         :meta (rd/makeList (list))
         :styles (rd/makeList (list))
         :content (rd/makeList (list))
         :data (rd/makeList (list))
         :config (rd/makeList (list))
         :success false
         :errorMsg "Empty input string"))
      ((not (string-starts-with? trimmed "("))
       (MultilensModel
         :meta (rd/makeList (list))
         :styles (rd/makeList (list))
         :content (rd/makeList (list))
         :data (rd/makeList (list))
         :config (rd/makeList (list))
         :success false
         :errorMsg "Model root must be a parenthesized list"))
      (:else
       (let [(toks (lx/tokenize trimmed))
             (formsRes (ast/readForms toks))]
         (mt formsRes
           ((err msg)
            (MultilensModel
              :meta (rd/makeList (list))
              :styles (rd/makeList (list))
              :content (rd/makeList (list))
              :data (rd/makeList (list))
              :config (rd/makeList (list))
              :success false
              :errorMsg (str "S-expression syntax error: " msg)))
           ((ok forms)
            (if (list-empty? forms)
              (MultilensModel
                :meta (rd/makeList (list))
                :styles (rd/makeList (list))
                :content (rd/makeList (list))
                :data (rd/makeList (list))
                :config (rd/makeList (list))
                :success false
                :errorMsg "No forms parsed")
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))
                    (expr (.-expr pf))]
                (mt expr
                  ((rd/sexprList items)
                   (let [(hd (rd/sexprHead expr))]
                     (if (and (!= hd ":doc") (!= hd "doc"))
                       (MultilensModel
                         :meta (rd/makeList (list))
                         :styles (rd/makeList (list))
                         :content (rd/makeList (list))
                         :data (rd/makeList (list))
                         :config (rd/makeList (list))
                         :success false
                         :errorMsg "Model root form must start with :doc")
                       (let [(body (if (or (= hd ":doc") (= hd "doc"))
                                     (option-or (list-tail items) (list))
                                     items))
                             (metaSec (extractSection body ":meta"))
                             (stylesSec (extractSection body ":styles"))
                             (contentSec (extractSection body ":content"))
                             (dataSec (extractSection body ":data"))
                             (configSec (extractSection body ":config"))]
                         (MultilensModel
                           :meta metaSec
                           :styles stylesSec
                           :content contentSec
                           :data dataSec
                           :config configSec
                           :success true
                           :errorMsg "")))))
                  (_
                   (MultilensModel
                     :meta (rd/makeList (list))
                     :styles (rd/makeList (list))
                     :content (rd/makeList (list))
                     :data (rd/makeList (list))
                     :config (rd/makeList (list))
                     :success false
                     :errorMsg "Model must be a list"))))))))))))

(df findMetadataVal [(meta rd/SExpr) (kw Str) (defaultVal Str)] -> Str
  :d "Extracts a string metadata attribute from :meta SExpr or returns defaultVal."
  (mt meta
    ((rd/sexprList items)
     (let [(val (findKeywordInList items kw))]
       (if (string-empty? val) defaultVal val)))
    ((rd/sexprVect items)
     (let [(val (findKeywordInList items kw))]
       (if (string-empty? val) defaultVal val)))
    (_ defaultVal)))

(df findKeywordInList [(items (List rd/SExpr)) (kw Str)] -> Str
  :d "Finds value following keyword in items list."
  (mt (list-head items)
    ((none) "")
    ((some it)
     (let [(tail (option-or (list-tail items) (list)))]
       (mt it
         ((rd/sexprAtom v)
          (if (or (= v kw) (or (= v (txt/stripColon kw)) (= (txt/stripColon v) (txt/stripColon kw))))
            (mt (list-head tail)
              ((some nextIt) (mt nextIt
                               ((rd/sexprAtom nv) (txt/stripQuotes nv))
                               (_ "")))
              ((none) ""))
            (findKeywordInList tail kw)))
         ((rd/sexprList sub) (findKeywordInList tail kw))
         ((rd/sexprVect sub) (findKeywordInList tail kw)))))))

(df getSexprItemsList [(expr rd/SExpr)] -> (List rd/SExpr)
  :d "Unwraps items list from sexprList or returns empty list."
  (mt expr
    ((rd/sexprList items) items)
    (_ (list))))

(df isNonEmptySexpr [(expr rd/SExpr)] -> Bool
  :d "Checks if SExpr is non-empty."
  (mt expr
    ((rd/sexprList items) (not (list-empty? items)))
    ((rd/sexprVect items) (not (list-empty? items)))
    ((rd/sexprAtom v) (> (string-length (string-trim v)) 0))))

(df projectLensHtml [(model MultilensModel) (opts LensOptions)] -> LensResult
  :d "Projects MultilensModel into valid standalone HTML5 or HTML fragment."
  (let [(title (findMetadataVal (.-meta model) ":title" "AgentScript Document"))
        (lang (findMetadataVal (.-meta model) ":lang" "en"))
        (cssText (if (.-includeStyles opts)
                   (ce/asnToCss (.-styles model) (.-minify opts))
                   ""))
        (contentExpr (.-content model))
        (bodyHtml (mt contentExpr
                    ((rd/sexprList items)
                     (if (list-empty? items) "" (tr/vdomNodeToHtml contentExpr)))
                    ((rd/sexprAtom v) (txt/stripQuotes v))
                    (_ "")))
        (htmlOut (if (.-standalone opts)
                   (tr/renderHtml5Document title lang cssText bodyHtml (.-minify opts))
                   bodyHtml))
        (origStr (rd/renderSexpr (.-content model)))
        (origTok (txt/estimateTokens origStr))
        (outTok (txt/estimateTokens htmlOut))
        (savings (txt/calcSavings origTok outTok))]
    (LensResult
      :lens "html"
      :output htmlOut
      :originalTokens origTok
      :emittedTokens outTok
      :savingsPercent savings
      :success true
      :errorMsg "")))

(df projectLensCss [(model MultilensModel) (opts LensOptions)] -> LensResult
  :d "Projects MultilensModel into standard CSS stylesheet text."
  (let [(stylesExpr (.-styles model))
        (cssOut (ce/asnToCss stylesExpr (.-minify opts)))
        (origStr (rd/renderSexpr stylesExpr))
        (origTok (txt/estimateTokens origStr))
        (outTok (txt/estimateTokens cssOut))
        (savings (txt/calcSavings origTok outTok))]
    (LensResult
      :lens "css"
      :output cssOut
      :originalTokens origTok
      :emittedTokens outTok
      :savingsPercent savings
      :success true
      :errorMsg "")))

(df projectLensYaml [(model MultilensModel) (opts LensOptions)] -> LensResult
  :d "Projects MultilensModel into structured YAML configuration."
  (let [(cfg (.-config model))
        (dat (.-data model))
        (targetExpr (if (isNonEmptySexpr cfg)
                      (if (isNonEmptySexpr dat)
                        (rd/makeList (list-append (getSexprItemsList cfg) (getSexprItemsList dat)))
                        cfg)
                      (if (isNonEmptySexpr dat) dat (rd/makeList (list)))))
        (compactAsn (rd/renderSexpr targetExpr))
        (res (yt/asnToYaml compactAsn))]
    (LensResult
      :lens "yaml"
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :emittedTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res)
      :errorMsg "")))

(df projectLensJson [(model MultilensModel) (opts LensOptions)] -> LensResult
  :d "Projects MultilensModel data or config into strict RFC 8259 JSON."
  (let [(dat (.-data model))
        (cfg (.-config model))
        (targetExpr (if (isNonEmptySexpr dat) dat (if (isNonEmptySexpr cfg) cfg (rd/makeList (list)))))
        (compactAsn (rd/renderSexpr targetExpr))
        (res (tr/asnToJson compactAsn))]
    (LensResult
      :lens "json"
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :emittedTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res)
      :errorMsg "")))

(df projectLensToml [(model MultilensModel) (opts LensOptions)] -> LensResult
  :d "Projects MultilensModel configuration into valid TOML tables."
  (let [(cfg (.-config model))
        (meta (.-meta model))
        (targetExpr (if (isNonEmptySexpr cfg)
                      (if (isNonEmptySexpr meta)
                        (rd/makeList (list-append (getSexprItemsList meta) (getSexprItemsList cfg)))
                        cfg)
                      (if (isNonEmptySexpr meta) meta (rd/makeList (list)))))
        (compactAsn (rd/renderSexpr targetExpr))
        (res (tt/asnToTomlDocument compactAsn))]
    (LensResult
      :lens "toml"
      :output (.-output res)
      :originalTokens (.-originalTokens res)
      :emittedTokens (.-asnTokens res)
      :savingsPercent (.-savingsPercent res)
      :success (.-success res)
      :errorMsg "")))

(df projectLens [(lens Str) (model MultilensModel) (opts LensOptions)] -> LensResult
  :d "Polymorphic projection dispatcher for format lenses."
  (let [(cleanLens (string-trim (txt/stripColon lens)))]
    (cond
      ((= cleanLens "html") (projectLensHtml model opts))
      ((= cleanLens "css")  (projectLensCss model opts))
      ((= cleanLens "yaml") (projectLensYaml model opts))
      ((= cleanLens "json") (projectLensJson model opts))
      ((= cleanLens "toml") (projectLensToml model opts))
      (:else
       (LensResult
         :lens lens
         :output ""
         :originalTokens 0
         :emittedTokens 0
         :savingsPercent 0.0
         :success false
         :errorMsg (str "Unsupported lens: " lens))))))

(df findLensOutput [(results (List LensResult)) (target Str)] -> Str
  :d "Extracts output string of target lens from result list."
  (mt (list-head results)
    ((none) "")
    ((some r)
     (if (= (.-lens r) target)
       (.-output r)
       (findLensOutput (option-or (list-tail results) (list)) target)))))

(df emitMultilensBundle [(model MultilensModel) (lenses (List Str)) (opts LensOptions)] -> MultilensBundle
  :d "Projects unified MultilensModel simultaneously across multiple lenses."
  (let [(activeLenses (if (list-empty? lenses)
                        (list "html" "css" "yaml" "json" "toml")
                        lenses))
        (results (map (fn [(l Str)] -> LensResult (projectLens l model opts)) activeLenses))
        (hOut (findLensOutput results "html"))
        (cOut (findLensOutput results "css"))
        (yOut (findLensOutput results "yaml"))
        (jOut (findLensOutput results "json"))
        (tOut (findLensOutput results "toml"))
        (totOrig (fold (fn [(acc I64) (r LensResult)] -> I64 (+ acc (.-originalTokens r))) 0 results))
        (totEmit (fold (fn [(acc I64) (r LensResult)] -> I64 (+ acc (.-emittedTokens r))) 0 results))
        (allOk (fold (fn [(acc Bool) (r LensResult)] -> Bool (and acc (.-success r))) true results))]
    (MultilensBundle
      :html hOut
      :css cOut
      :yaml yOut
      :json jOut
      :toml tOut
      :artifacts results
      :totalOriginalTokens totOrig
      :totalEmittedTokens totEmit
      :success (and allOk (not (list-empty? results))))))

(df measureBundleSavings [(bundle MultilensBundle)] -> F64
  :d "Measures aggregate token compaction percentage across bundle."
  (txt/calcSavings (.-totalOriginalTokens bundle) (.-totalEmittedTokens bundle)))
