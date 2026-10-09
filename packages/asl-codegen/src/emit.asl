(module asl-codegen/emit :x [emitDefschema emitDefenum emitDefun emitTopForms emitRustProgram mergeMaps hasMainFn?] :i [(ast :a a) (mangle :a m) (rtypes :a cgTy) (expr :a ex) (asl-checker/types :a ty)])

fn mergeMaps m1: (Map String String) m2: (Map String String) -> (Map String String)
  (fold (fn [(acc (Map String String)) (p (pair String String))] -> (Map String String) (mapSet acc (pairFirst p) (pairSecond p))) m1 (mapPairs m2))

fn emitGenericParams tvars: (List String) -> String
  (if (> (listLength tvars) 0) (str "<" (stringJoin (map (fn [(v String)] -> String (str v ": Clone")) tvars) ", ") ">") "")

fn typeListFlags name: String tys: (List ty/Type) -> (Pair Bool Bool)
  (let [(hasIo (fold (fn [(acc Bool) (t ty/Type)] (or acc (cgTy/typeMentionsIoError? t))) false tys)) (hasFloat (or (or (= name "Token") (= name "TokenType")) (fold (fn [(acc Bool) (t ty/Type)] (or acc (cgTy/typeMentionsFloat? t))) false tys)))] (pair hasIo hasFloat))

fn schemaFlags s: a/SchemaNode -> (Pair Bool Bool)
  (let [(fTys (map (fn [(f a/AstField)] -> ty/Type (ty/parseTypeStr f.type (list))) s.fields))] (typeListFlags s.name fTys))

fn enumFlags e: a/EnumNode -> (Pair Bool Bool)
  (let [(name e.name) (cases e.cases)] (fold (fn [(acc (pair Bool Bool)) (c a/EnumCase)] -> (Pair Bool Bool) (let [(pTys (map (fn [(p a/Param)] -> ty/Type (ty/parseTypeStr p.type (list))) c.fields)) (cFlags (typeListFlags name pTys))] (pair (or (pairFirst acc) (pairFirst cFlags)) (or (pairSecond acc) (pairSecond cFlags))))) (pair false false) cases))

fn emitDefschema s: a/SchemaNode -> String
  (let [(name s.name) (genStr (emitGenericParams s.typeVars)) (flags (schemaFlags s)) (derives (cgTy/emitDerives (pairFirst flags) (pairSecond flags))) (fStrs (map (fn [(f a/AstField)] -> String (let [(fName (m/mangleIdent f.name)) (fTy (cgTy/emitTypeStr f.type))] (str "    pub " fName ": " fTy ",\n"))) s.fields))] (str derives "\npub struct " name genStr " {\n" (stringJoin fStrs "") "}\n"))

fn emitDefenum e: a/EnumNode -> String
  (let [(name e.name) (genStr (emitGenericParams e.typeVars)) (flags (enumFlags e)) (derives (cgTy/emitDerives (pairFirst flags) (pairSecond flags))) (caseStrs (map (fn [(c a/EnumCase)] -> String (let [(cName (m/pascalIdent c.name)) (fields c.fields)] (if (<= (listLength fields) 0) (str "    " cName ",\n") (let [(fTys (map (fn [(p a/Param)] -> String (cgTy/emitTypeStr p.type)) fields))] (str "    " cName "(" (stringJoin fTys ", ") "),\n"))))) e.cases))] (str derives "\npub enum " name genStr " {\n" (stringJoin caseStrs "") "}\n"))

fn emitDefun d: a/DefunNode aliases: (Map String String) -> String
  (let [(name (m/mangleIdent d.name)) (genStr (emitGenericParams d.typeVars)) (params (map (fn [(p a/Param)] -> String (let [(pName (m/mangleIdent p.name)) (pTy (cgTy/emitTypeStr p.type))] (str pName ": " pTy))) d.params)) (argsStr (stringJoin params ", ")) (retStr (cgTy/emitTypeStr d.retType)) (bodyStr (ex/emitBodySeq d.body aliases))] (str "pub fn " name genStr "(" argsStr ") -> " retStr " {\n    " bodyStr "\n}\n"))

fn hasMainFn? defs: (List a/TopForm) -> Bool
  (let [(mains (filter (fn [(top a/TopForm)] -> Bool (mt top ((a/topDefun d) (= d.name "main")) (_ false))) defs))] (> (listLength mains) 0))

fn emitHostEntry hasMain: Bool -> String
  (if hasMain "\nfn main() {\n    let args: Vec<String> = std::env::args().skip(1).collect();\n    std::process::exit(rt::main_exit(main_(args)));\n}\n" "")

fn buildAliasesMap imports: (List (Pair String String)) -> (Map String String)
  (fold (fn [(acc (Map String String)) (im (pair String String))] -> (Map String String) (mapSet acc (pairSecond im) (pairFirst im))) (mapEmpty) imports)

fn collectModuleEnums m: a/ModuleNode -> (Map String String)
  (let [(mPath m.path) (rMod (m/rustModName mPath)) (shortMod (m/shortModName mPath))] (fold (fn [(acc (Map String String)) (top a/TopForm)] -> (Map String String) (mt top ((a/topEnum e) (let [(eName (m/pascalIdent e.name)) (cases e.cases)] (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String) (let [(cName c.name) (pCname (m/pascalIdent cName)) (tgt (str "crate::" rMod "::" eName "::" pCname)) (cacc1 (mapSet cacc (str mPath "/" cName) tgt)) (cacc2 (mapSet cacc1 (str shortMod "/" cName) tgt))] (mapSet cacc2 cName (str eName "::" pCname)))) acc cases))) (_ acc))) (mapEmpty) m.defs))

fn collectAllEnums rootDefs: (List a/TopForm) deps: (List a/TopForm) -> (Map String String)
  (let [(depMaps (map (fn [(top a/TopForm)] -> (Map String String) (mt top ((a/topModule m) (collectModuleEnums m)) (_ (mapEmpty)))) deps)) (rootMap (fold (fn [(acc (Map String String)) (top a/TopForm)] -> (Map String String) (mt top ((a/topEnum e) (let [(eName (m/pascalIdent e.name)) (cases e.cases)] (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String) (let [(cName c.name) (pCname (m/pascalIdent cName))] (mapSet cacc cName (str eName "::" pCname)))) acc cases))) (_ acc))) (mapEmpty) rootDefs))] (fold (fn [(acc (Map String String)) (m (Map String String))] -> (Map String String) (mergeMaps acc m)) rootMap depMaps))

fn emitModule m: a/ModuleNode allEnums: (Map String String) -> String
  (let [(modname (m/rustModName m.path)) (modAliases (buildAliasesMap m.imports)) (mergedAliases (mergeMaps allEnums modAliases)) (useAliases (map (fn [(im (pair String String))] -> String (let [(mpath (pairFirst im)) (alias (pairSecond im)) (rMod (m/rustModName mpath))] (if (not (= alias rMod)) (str "    #[allow(unused_imports)]\n    pub use crate::" rMod " as " (m/mangleIdent alias) ";\n") ""))) m.imports)) (body (emitTopForms m.defs mergedAliases allEnums))] (str "pub mod " modname " {\n" "    #![allow(dead_code, unused_variables, unused_mut, unused_parens)]\n" "    #[allow(unused_imports)]\n" "    use super::rt;\n" (stringJoin useAliases "") "\n" body "\n}\n"))

fn formsHaveTopExpr? forms: (List a/TopForm) -> Bool
  (fold (fn [(acc Bool) (t a/TopForm)] -> Bool (or acc (mt t ((a/topExpr _) true) (_ false)))) false forms)

fn emitTopForms defs: (List a/TopForm) aliases: (Map String String) allEnums: (Map String String) -> String
  (do (assert (not (formsHaveTopExpr? defs)) "ERR_RUST_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook in the Rust target")
      (let [(renderedDefs (map (fn [(top a/TopForm)] -> String (mt top ((a/topSchema s) (emitDefschema s)) ((a/topEnum e) (emitDefenum e)) ((a/topDefun d) (emitDefun d aliases)) ((a/topModule m) (emitModule m allEnums)) ((a/topExpr _) ""))) defs))] (stringJoin renderedDefs "\n")))

fn extractModuleInfo forms: (List a/TopForm) -> (Pair (Map String String) (Pair (List a/TopForm) Bool))
  (if (<= (listLength forms) 0) (pair (mapEmpty) (pair (list) false)) (let [(firstForm (optionOr (listGet forms 0) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))] (mt firstForm ((a/topModule m) (let [(aliases (buildAliasesMap m.imports)) (defs m.defs) (hm (hasMainFn? defs))] (pair aliases (pair defs hm)))) (_ (let [(defs forms) (hm (hasMainFn? defs))] (pair (mapEmpty) (pair defs hm)))))))

fn emitUseAlias srcMod: String tgtAlias: String -> String
  (if (not (= srcMod tgtAlias)) (str "#[allow(unused_imports)]\npub use self::" srcMod " as " tgtAlias ";\n") "")

fn emitRustProgram rootForms: (List a/TopForm) deps: (List a/TopForm) -> String
  (let [(header "#![allow(dead_code, unused_variables, unused_mut, unused_parens)]\nmod rt;\n\n") (info (extractModuleInfo rootForms)) (rootAliases (pairFirst info)) (defs (pairFirst (pairSecond info))) (hasMain (pairSecond (pairSecond info))) (allEnums (collectAllEnums defs deps)) (mergedRootAliases (mergeMaps allEnums rootAliases)) (depRendered (if (> (listLength deps) 0) (str (emitTopForms deps (mapEmpty) allEnums) "\n\n") "")) (rootUseAliases (if (> (listLength deps) 0) (let [(useLines (map (fn [(top a/TopForm)] -> String (mt top ((a/topModule m) (let [(rMod (m/rustModName m.path)) (sMod (m/shortModName m.path))] (str "#[allow(unused_imports)]\npub use self::" rMod "::*;\n" (emitUseAlias rMod sMod)))) (_ ""))) deps)) (aliasLines (map (fn [(p (pair String String))] -> String (emitUseAlias (m/shortModName (pairSecond p)) (m/mangleIdent (pairFirst p)))) (mapPairs rootAliases)))] (str (stringJoin useLines "") (stringJoin aliasLines "") "\n")) "")) (rootBody (emitTopForms defs mergedRootAliases allEnums)) (entry (emitHostEntry hasMain))] (str header depRendered rootUseAliases rootBody entry))
