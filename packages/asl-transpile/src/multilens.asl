(module asl-transpile/multilens :x [MultilensModel LensOptions LensResult MultilensBundle defaultLensOptions emptyModel validateMultilensModel parseUnifiedModel modelExtractMeta modelExtractStyles modelExtractContent modelExtractData modelExtractConfig projectLens projectLensHtml projectLensCss projectLensYaml projectLensJson projectLensToml emitMultilensBundle measureBundleSavings] :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-text/text :a txt) (cssEmit :a ce) (transpile :a tr) (yamlTranspile :a yt) (tomlTranspile :a tt)])

(schema MultilensModel (:f meta rd/SExpr) (:f styles rd/SExpr) (:f content rd/SExpr) (:f data rd/SExpr) (:f config rd/SExpr) (:f success Bool) (:f errorMsg Str))

(schema LensOptions (:f indent I64) (:f minify Bool) (:f standalone Bool) (:f includeStyles Bool) (:f doctype Bool))

(schema LensResult (:f lens Str) (:f output Str) (:f originalTokens I64) (:f emittedTokens I64) (:f savingsPercent F64) (:f success Bool) (:f errorMsg Str))

(schema MultilensBundle (:f html Str) (:f css Str) (:f yaml Str) (:f json Str) (:f toml Str) (:f artifacts (List LensResult)) (:f totalOriginalTokens I64) (:f totalEmittedTokens I64) (:f success Bool))

fn defaultLensOptions -> LensOptions
  (LensOptions :indent 2 :minify false :standalone true :includeStyles true :doctype true)

fn emptyModel -> MultilensModel
  (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success true :errorMsg "")

fn modelExtractMeta m: MultilensModel -> rd/SExpr
  m.meta

fn modelExtractStyles m: MultilensModel -> rd/SExpr
  m.styles

fn modelExtractContent m: MultilensModel -> rd/SExpr
  m.content

fn modelExtractData m: MultilensModel -> rd/SExpr
  m.data

fn modelExtractConfig m: MultilensModel -> rd/SExpr
  m.config

fn extractSectionLoop items: (List rd/SExpr) plain: Str colon: Str -> rd/SExpr
  (mt (listHead items) ((none) (rd/makeList (list))) ((some it) (let [(tail (optionOr (listTail items) (list)))] (mt it ((rd/sexprAtom v) (let [(stripped (txt/stripColon v))] (if (or (= v plain) (or (= v colon) (= stripped plain))) (mt (listHead tail) ((some nextIt) nextIt) ((none) (rd/makeList (list)))) (extractSectionLoop tail plain colon)))) ((rd/sexprList subItems) (let [(hd (rd/sexprHead it)) (stripped (txt/stripColon hd))] (if (or (= hd plain) (or (= hd colon) (= stripped plain))) it (extractSectionLoop tail plain colon)))) ((rd/sexprVect _) (extractSectionLoop tail plain colon))))))

fn extractSection items: (List rd/SExpr) secName: Str -> rd/SExpr
  (let [(plainName (txt/stripColon secName)) (colonName (str ":" plainName))] (extractSectionLoop items plainName colonName))

fn validateMultilensModel input: Str -> Bool
  (let [(trimmed (stringTrim input))] (if (or (stringEmpty? trimmed) (not (stringStartsWith? trimmed "("))) false (let [(toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) false) ((ok forms) (if (listEmpty? forms) false (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))) (expr pf.expr)] (mt expr ((rd/sexprList items) (let [(hd (rd/sexprHead expr))] (or (= hd ":doc") (= hd "doc")))) (_ false)))))))))

fn parseUnifiedModel input: Str -> MultilensModel
  (let [(trimmed (stringTrim input))] (cond ((stringEmpty? trimmed) (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success false :errorMsg "Empty input string")) ((not (stringStartsWith? trimmed "(")) (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success false :errorMsg "Model root must be a parenthesized list")) (else (let [(toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err msg) (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success false :errorMsg (str "S-expression syntax error: " msg))) ((ok forms) (if (listEmpty? forms) (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success false :errorMsg "No forms parsed") (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))) (expr pf.expr)] (mt expr ((rd/sexprList items) (let [(hd (rd/sexprHead expr))] (if (and (!= hd ":doc") (!= hd "doc")) (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success false :errorMsg "Model root form must start with :doc") (let [(body (if (or (= hd ":doc") (= hd "doc")) (optionOr (listTail items) (list)) items)) (metaSec (extractSection body ":meta")) (stylesSec (extractSection body ":styles")) (contentSec (extractSection body ":content")) (dataSec (extractSection body ":data")) (configSec (extractSection body ":config"))] (MultilensModel :meta metaSec :styles stylesSec :content contentSec :data dataSec :config configSec :success true :errorMsg ""))))) (_ (MultilensModel :meta (rd/makeList (list)) :styles (rd/makeList (list)) :content (rd/makeList (list)) :data (rd/makeList (list)) :config (rd/makeList (list)) :success false :errorMsg "Model must be a list")))))))))))

fn findMetadataVal meta: rd/SExpr kw: Str defaultVal: Str -> Str
  (mt meta ((rd/sexprList items) (let [(val (findKeywordInList items kw))] (if (stringEmpty? val) defaultVal val))) ((rd/sexprVect items) (let [(val (findKeywordInList items kw))] (if (stringEmpty? val) defaultVal val))) (_ defaultVal))

fn findKeywordInList items: (List rd/SExpr) kw: Str -> Str
  (mt (listHead items) ((none) "") ((some it) (let [(tail (optionOr (listTail items) (list)))] (mt it ((rd/sexprAtom v) (if (or (= v kw) (or (= v (txt/stripColon kw)) (= (txt/stripColon v) (txt/stripColon kw)))) (mt (listHead tail) ((some nextIt) (mt nextIt ((rd/sexprAtom nv) (txt/stripQuotes nv)) (_ ""))) ((none) "")) (findKeywordInList tail kw))) ((rd/sexprList sub) (findKeywordInList tail kw)) ((rd/sexprVect sub) (findKeywordInList tail kw))))))

fn getSexprItemsList expr: rd/SExpr -> (List rd/SExpr)
  (mt expr ((rd/sexprList items) items) (_ (list)))

fn isNonEmptySexpr expr: rd/SExpr -> Bool
  (mt expr ((rd/sexprList items) (not (listEmpty? items))) ((rd/sexprVect items) (not (listEmpty? items))) ((rd/sexprAtom v) (> (stringLength (stringTrim v)) 0)))

fn projectLensHtml model: MultilensModel opts: LensOptions -> LensResult
  (let [(title (findMetadataVal model.meta ":title" "AgentScript Document")) (lang (findMetadataVal model.meta ":lang" "en")) (cssText (if opts.includeStyles (ce/asnToCss model.styles opts.minify) "")) (contentExpr model.content) (bodyHtml (mt contentExpr ((rd/sexprList items) (if (listEmpty? items) "" (tr/vdomNodeToHtml contentExpr))) ((rd/sexprAtom v) (txt/stripQuotes v)) (_ ""))) (htmlOut (if opts.standalone (tr/renderHtml5Document title lang cssText bodyHtml opts.minify) bodyHtml)) (origStr (rd/renderSexpr model.content)) (origTok (txt/estimateTokens origStr)) (outTok (txt/estimateTokens htmlOut)) (savings (txt/calcSavings origTok outTok))] (LensResult :lens "html" :output htmlOut :originalTokens origTok :emittedTokens outTok :savingsPercent savings :success true :errorMsg ""))

fn projectLensCss model: MultilensModel opts: LensOptions -> LensResult
  (let [(stylesExpr model.styles) (cssOut (ce/asnToCss stylesExpr opts.minify)) (origStr (rd/renderSexpr stylesExpr)) (origTok (txt/estimateTokens origStr)) (outTok (txt/estimateTokens cssOut)) (savings (txt/calcSavings origTok outTok))] (LensResult :lens "css" :output cssOut :originalTokens origTok :emittedTokens outTok :savingsPercent savings :success true :errorMsg ""))

fn projectLensYaml model: MultilensModel opts: LensOptions -> LensResult
  (let [(cfg model.config) (dat model.data) (targetExpr (if (isNonEmptySexpr cfg) (if (isNonEmptySexpr dat) (rd/makeList (listAppend (getSexprItemsList cfg) (getSexprItemsList dat))) cfg) (if (isNonEmptySexpr dat) dat (rd/makeList (list))))) (compactAsn (rd/renderSexpr targetExpr)) (res (yt/asnToYaml compactAsn))] (LensResult :lens "yaml" :output res.output :originalTokens res.originalTokens :emittedTokens res.asnTokens :savingsPercent res.savingsPercent :success res.success :errorMsg ""))

fn projectLensJson model: MultilensModel opts: LensOptions -> LensResult
  (let [(dat model.data) (cfg model.config) (targetExpr (if (isNonEmptySexpr dat) dat (if (isNonEmptySexpr cfg) cfg (rd/makeList (list))))) (compactAsn (rd/renderSexpr targetExpr)) (res (tr/asnToJson compactAsn))] (LensResult :lens "json" :output res.output :originalTokens res.originalTokens :emittedTokens res.asnTokens :savingsPercent res.savingsPercent :success res.success :errorMsg ""))

fn projectLensToml model: MultilensModel opts: LensOptions -> LensResult
  (let [(cfg model.config) (meta model.meta) (targetExpr (if (isNonEmptySexpr cfg) (if (isNonEmptySexpr meta) (rd/makeList (listAppend (getSexprItemsList meta) (getSexprItemsList cfg))) cfg) (if (isNonEmptySexpr meta) meta (rd/makeList (list))))) (compactAsn (rd/renderSexpr targetExpr)) (res (tt/asnToTomlDocument compactAsn))] (LensResult :lens "toml" :output res.output :originalTokens res.originalTokens :emittedTokens res.asnTokens :savingsPercent res.savingsPercent :success res.success :errorMsg ""))

fn projectLens lens: Str model: MultilensModel opts: LensOptions -> LensResult
  (let [(cleanLens (stringTrim (txt/stripColon lens)))] (cond ((= cleanLens "html") (projectLensHtml model opts)) ((= cleanLens "css") (projectLensCss model opts)) ((= cleanLens "yaml") (projectLensYaml model opts)) ((= cleanLens "json") (projectLensJson model opts)) ((= cleanLens "toml") (projectLensToml model opts)) (else (LensResult :lens lens :output "" :originalTokens 0 :emittedTokens 0 :savingsPercent 0.0 :success false :errorMsg (str "Unsupported lens: " lens)))))

fn findLensOutput results: (List LensResult) target: Str -> Str
  (mt (listHead results) ((none) "") ((some r) (if (= r.lens target) r.output (findLensOutput (optionOr (listTail results) (list)) target))))

fn emitMultilensBundle model: MultilensModel lenses: (List Str) opts: LensOptions -> MultilensBundle
  (let [(activeLenses (if (listEmpty? lenses) (list "html" "css" "yaml" "json" "toml") lenses)) (results (map (fn [(l Str)] -> LensResult (projectLens l model opts)) activeLenses)) (hOut (findLensOutput results "html")) (cOut (findLensOutput results "css")) (yOut (findLensOutput results "yaml")) (jOut (findLensOutput results "json")) (tOut (findLensOutput results "toml")) (totOrig (fold (fn [(acc I64) (r LensResult)] -> I64 (+ acc r.originalTokens)) 0 results)) (totEmit (fold (fn [(acc I64) (r LensResult)] -> I64 (+ acc r.emittedTokens)) 0 results)) (allOk (fold (fn [(acc Bool) (r LensResult)] -> Bool (and acc r.success)) true results))] (MultilensBundle :html hOut :css cOut :yaml yOut :json jOut :toml tOut :artifacts results :totalOriginalTokens totOrig :totalEmittedTokens totEmit :success (and allOk (not (listEmpty? results)))))

fn measureBundleSavings bundle: MultilensBundle -> F64
  (txt/calcSavings bundle.totalOriginalTokens bundle.totalEmittedTokens)
