(module asl-codegen/emit
  :d "Top-level form emission, module linking, and Rust program assembly."
  :x [emitDefschema
      emitDefenum
      emitDefun
      emitTopForms
      emitRustProgram
      mergeMaps
      hasMainFn?]
  :i [(ast :a a) (mangle :a m) (rtypes :a cgTy) (expr :a ex) (asl-checker/types :a ty)])

(df mergeMaps [(m1 (Map String String)) (m2 (Map String String))] -> (Map String String)
  :d "Merges two maps."
  (fold (fn [(acc (Map String String)) (p (Pair String String))] -> (Map String String)
          (map-set acc (.-first p) (.-second p)))
        m1
        (map-pairs m2)))

(df emitGenericParams [(tvars (List String))] -> String
  :d "Emits generic type parameter clause with Clone bound."
  (if (> (list-length tvars) 0)
      (str "<" (string-join (map (fn [(v String)] -> String (str v ": Clone")) tvars) ", ") ">")
      ""))

(df typeListFlags [(name String) (tys (List ty/Type))] -> (Pair Bool Bool)
  :d "Checks a list of types for IoError and Float64 containment."
  (let [(hasIo (fold (fn [(acc Bool) (t ty/Type)] (or acc (cgTy/typeMentionsIoError? t))) false tys))
        (hasFloat (or (or (= name "Token") (= name "TokenType"))
                       (fold (fn [(acc Bool) (t ty/Type)] (or acc (cgTy/typeMentionsFloat? t))) false tys)))]
    (pair hasIo hasFloat)))

(df schemaFlags [(s a/SchemaNode)] -> (Pair Bool Bool)
  :d "Computes IoError and Float64 containment flags for a schema."
  (let [(fTys (map (fn [(f a/AstField)] -> ty/Type
                      (ty/parseTypeStr (.-type f) (list)))
                    (.-fields s)))]
    (typeListFlags (.-name s) fTys)))

(df enumFlags [(e a/EnumNode)] -> (Pair Bool Bool)
  :d "Computes IoError and Float64 containment flags for an enum."
  (let [(name (.-name e))
        (cases (.-cases e))]
    (fold (fn [(acc (Pair Bool Bool)) (c a/EnumCase)] -> (Pair Bool Bool)
            (let [(pTys (map (fn [(p a/Param)] -> ty/Type
                                (ty/parseTypeStr (.-type p) (list)))
                              (.-fields c)))
                  (cFlags (typeListFlags name pTys))]
              (pair (or (.-first acc) (.-first cFlags))
                    (or (.-second acc) (.-second cFlags)))))
          (pair false false)
          cases)))

(df emitDefschema [(s a/SchemaNode)] -> String
  :d "Emits a Rust struct definition with derives and fields."
  (let [(name (.-name s))
        (genStr (emitGenericParams (.-typeVars s)))
        (flags (schemaFlags s))
        (derives (cgTy/emitDerives (.-first flags) (.-second flags)))
        (fStrs (map (fn [(f a/AstField)] -> String
                       (let [(fName (m/mangleIdent (.-name f)))
                             (fTy (cgTy/emitTypeStr (.-type f)))]
                         (str "    pub " fName ": " fTy ",\n")))
                     (.-fields s)))]
    (str derives "\npub struct " name genStr " {\n" (string-join fStrs "") "}\n")))

(df emitDefenum [(e a/EnumNode)] -> String
  :d "Emits a Rust enum definition with derives and cases."
  (let [(name (.-name e))
        (genStr (emitGenericParams (.-typeVars e)))
        (flags (enumFlags e))
        (derives (cgTy/emitDerives (.-first flags) (.-second flags)))
        (caseStrs (map (fn [(c a/EnumCase)] -> String
                          (let [(cName (m/pascalIdent (.-name c)))
                                (fields (.-fields c))]
                            (if (<= (list-length fields) 0)
                                (str "    " cName ",\n")
                                (let [(fTys (map (fn [(p a/Param)] -> String
                                                    (cgTy/emitTypeStr (.-type p)))
                                                  fields))]
                                  (str "    " cName "(" (string-join fTys ", ") "),\n")))))
                        (.-cases e)))]
    (str derives "\npub enum " name genStr " {\n" (string-join caseStrs "") "}\n")))

(df emitDefun [(d a/DefunNode) (aliases (Map String String))] -> String
  :d "Emits a Rust public function with parameter types and body."
  (let [(name (m/mangleIdent (.-name d)))
        (genStr (emitGenericParams (.-typeVars d)))
        (params (map (fn [(p a/Param)] -> String
                       (let [(pName (m/mangleIdent (.-name p)))
                             (pTy (cgTy/emitTypeStr (.-type p)))]
                         (str pName ": " pTy)))
                     (.-params d)))
        (argsStr (string-join params ", "))
        (retStr (cgTy/emitTypeStr (.-retType d)))
        (bodyStr (ex/emitBodySeq (.-body d) aliases))]
    (str "pub fn " name genStr "(" argsStr ") -> " retStr " {\n    " bodyStr "\n}\n")))

(df hasMainFn? [(defs (List a/TopForm))] -> Bool
  :d "True if declarations contain a top-level function named main."
  (let [(mains (filter (fn [(top a/TopForm)] -> Bool
                         (mt top
                           ((a/topDefun d) (= (.-name d) "main"))
                           (_ false)))
                       defs))]
    (> (list-length mains) 0)))

(df emitHostEntry [(hasMain Bool)] -> String
  :d "Emits standard process entry point if program defines main."
  (if hasMain
      "\nfn main() {\n    let args: Vec<String> = std::env::args().skip(1).collect();\n    std::process::exit(rt::main_exit(main_(args)));\n}\n"
      ""))

(df buildAliasesMap [(imports (List (Pair String String)))] -> (Map String String)
  :d "Constructs alias -> module path lookup map from module imports."
  (fold (fn [(acc (Map String String)) (im (Pair String String))] -> (Map String String)
          (map-set acc (.-second im) (.-first im)))
        (map-empty)
        imports))

(df collectModuleEnums [(m a/ModuleNode)] -> (Map String String)
  :d "Collects all qualified and unqualified enum variant names defined in a module."
  (let [(mPath (.-path m))
        (rMod (m/rustModName mPath))
        (shortMod (m/shortModName mPath))]
    (fold (fn [(acc (Map String String)) (top a/TopForm)] -> (Map String String)
            (mt top
              ((a/topEnum e)
               (let [(eName (m/pascalIdent (.-name e)))
                     (cases (.-cases e))]
                 (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String)
                         (let [(cName (.-name c))
                               (pCname (m/pascalIdent cName))
                               (tgt (str "crate::" rMod "::" eName "::" pCname))
                               (cacc1 (map-set cacc (str mPath "/" cName) tgt))
                               (cacc2 (map-set cacc1 (str shortMod "/" cName) tgt))]
                           (map-set cacc2 cName (str eName "::" pCname))))
                       acc
                       cases)))
              (_ acc)))
          (map-empty)
          (.-defs m))))

(df collectAllEnums [(rootDefs (List a/TopForm)) (deps (List a/TopForm))] -> (Map String String)
  :d "Collects enum variants across root declarations and dependencies."
  (let [(depMaps (map (fn [(top a/TopForm)] -> (Map String String)
                         (mt top
                           ((a/topModule m) (collectModuleEnums m))
                           (_ (map-empty))))
                       deps))
        (rootMap (fold (fn [(acc (Map String String)) (top a/TopForm)] -> (Map String String)
                          (mt top
                            ((a/topEnum e)
                             (let [(eName (m/pascalIdent (.-name e)))
                                   (cases (.-cases e))]
                               (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String)
                                       (let [(cName (.-name c))
                                             (pCname (m/pascalIdent cName))]
                                         (map-set cacc cName (str eName "::" pCname))))
                                     acc
                                     cases)))
                            (_ acc)))
                        (map-empty)
                        rootDefs))]
    (fold (fn [(acc (Map String String)) (m (Map String String))] -> (Map String String)
            (mergeMaps acc m))
          rootMap
          depMaps)))

(df emitModule [(m a/ModuleNode) (allEnums (Map String String))] -> String
  :d "Emits a nested Rust module for a dependency."
  (let [(modname (m/rustModName (.-path m)))
        (modAliases (buildAliasesMap (.-imports m)))
        (mergedAliases (mergeMaps allEnums modAliases))
        (useAliases (map (fn [(im (Pair String String))] -> String
                            (let [(mpath (.-first im))
                                  (alias (.-second im))
                                  (rMod (m/rustModName mpath))]
                              (if (not (= alias rMod))
                                  (str "    #[allow(unused_imports)]\n    pub use crate::" rMod " as " (m/mangleIdent alias) ";\n")
                                  "")))
                          (.-imports m)))
        (body (emitTopForms (.-defs m) mergedAliases allEnums))]
    (str "pub mod " modname " {\n"
         "    #![allow(dead_code, unused_variables, unused_mut, unused_parens)]\n"
         "    #[allow(unused_imports)]\n"
         "    use super::rt;\n"
         (string-join useAliases "")
         "\n"
         body
         "\n}\n")))

(df emitTopForms [(defs (List a/TopForm)) (aliases (Map String String)) (allEnums (Map String String))] -> String
  :d "Emits all top forms declared in a list of TopForm."
  (let [(renderedDefs (map (fn [(top a/TopForm)] -> String
                              (mt top
                                ((a/topSchema s) (emitDefschema s))
                                ((a/topEnum e) (emitDefenum e))
                                ((a/topDefun d) (emitDefun d aliases))
                                ((a/topModule m) (emitModule m allEnums))))
                            defs))]
    (string-join renderedDefs "\n")))

(df extractModuleInfo [(forms (List a/TopForm))] -> (Pair (Map String String) (Pair (List a/TopForm) Bool))
  :d "Extracts aliases, declarations, and has-main flag from forms."
  (if (<= (list-length forms) 0)
      (pair (map-empty) (pair (list) false))
      (let [(firstForm (option-or (list-get forms 0) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt firstForm
          ((a/topModule m)
           (let [(aliases (buildAliasesMap (.-imports m)))
                 (defs (.-defs m))
                 (hm (hasMainFn? defs))]
             (pair aliases (pair defs hm))))
          (_
           (let [(defs forms)
                 (hm (hasMainFn? defs))]
             (pair (map-empty) (pair defs hm))))))))

(df emitUseAlias [(srcMod String) (tgtAlias String)] -> String
  :d "Emits a pub use self statement if alias differs from source module."
  (if (not (= srcMod tgtAlias))
      (str "#[allow(unused_imports)]\npub use self::" srcMod " as " tgtAlias ";\n")
      ""))

(df emitRustProgram [(rootForms (List a/TopForm)) (deps (List a/TopForm))] -> String
  :d "Assembles complete standalone Rust source file with runtime link."
  (let [(header "#![allow(dead_code, unused_variables, unused_mut, unused_parens)]\nmod rt;\n\n")
        (info (extractModuleInfo rootForms))
        (rootAliases (.-first info))
        (defs (.-first (.-second info)))
        (hasMain (.-second (.-second info)))
        (allEnums (collectAllEnums defs deps))
        (mergedRootAliases (mergeMaps allEnums rootAliases))
        (depRendered (if (> (list-length deps) 0)
                          (str (emitTopForms deps (map-empty) allEnums) "\n\n")
                          ""))
        (rootUseAliases (if (> (list-length deps) 0)
                              (let [(useLines (map (fn [(top a/TopForm)] -> String
                                                      (mt top
                                                        ((a/topModule m)
                                                         (let [(rMod (m/rustModName (.-path m)))
                                                               (sMod (m/shortModName (.-path m)))]
                                                           (str "#[allow(unused_imports)]\npub use self::" rMod "::*;\n"
                                                                (emitUseAlias rMod sMod))))
                                                        (_ "")))
                                                    deps))
                                    (aliasLines (map (fn [(p (Pair String String))] -> String
                                                        (emitUseAlias (m/shortModName (.-second p))
                                                                        (m/mangleIdent (.-first p))))
                                                      (map-pairs rootAliases)))]
                                (str (string-join useLines "") (string-join aliasLines "") "\n"))
                              ""))
        (rootBody (emitTopForms defs mergedRootAliases allEnums))
        (entry (emitHostEntry hasMain))]
    (str header depRendered rootUseAliases rootBody entry)))
