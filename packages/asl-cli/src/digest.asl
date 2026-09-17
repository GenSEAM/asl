(module asl-cli/digest
  :d "Pure ASL CLI Outline and High-SNR Perceptual Digest Subcommand Handler under ADR D97, D94."
  :x [generateAstOutline
      formatOutlineHelp
      formatImpactHelp
      runOutlineCommand]
  :i [(asl-parser/ast :a a)
      (asl-parser/reader :a rd)])

(df formatOutlineHelp [] -> Str
  :d "Formats usage manual for asl outline subcommand under ADR D97."
  (str "Usage: asl outline <file.asl>\n\n"
       "Extracts structural symbol signatures without internal bodies strictly under sub-80 token SLA.\n\n"
       "[Teleology] Principle: HighSNROverFullContext (ADR D97)\n"
       "  \"Outlines deliver maximal decision entropy with zero line numbers and zero body noise.\"\n\n"
       "[Assistive Ontology] Enforces:\n"
       "  • Signature Extraction: Function params and return types without expressions\n"
       "  • Zero-Line-Number Invariant: Symbols addressed strictly by name\n"))

(df formatImpactHelp [] -> Str
  :d "Formats usage manual for asl impact subcommand under ADR D94."
  (str "Usage: asl impact <symbol>\n\n"
       "Analyzes blast radius, direct callers, test dependencies, and type signatures strictly under 80 tokens.\n\n"
       "Arguments:\n"
       "  <symbol>    Target function, struct, or type identifier (Module:symbol or symbol)\n\n"
       "[Teleology] Principle: GroundTruthOverReport (ADR D94)\n"
       "  \"Codebase hypergraph queries bound perceptual tokens (<80 tokens) with zero line numbers.\"\n"))

(df formatParam [(p a/Param)] -> Str
  (str "(" (.-name p) " " (.-type p) ")"))

(df formatParamList [(params (List a/Param))] -> Str
  (if (list-empty? params)
      "[]"
      (let [(inner (fold (fn [(acc Str) (p a/Param)] -> Str
                           (let [(item (formatParam p))]
                             (if (string-empty? acc)
                                 item
                                 (str acc " " item))))
                         ""
                         params))]
        (str "[" inner "]"))))

(df formatTopFormSignature [(form a/TopForm)] -> Str
  (mt form
    ((a/topDefun f)
     (str "(:df " (.-name f) " " (formatParamList (.-params f)) " -> " (.-retType f) ")"))
    ((a/topSchema s)
     (str "(:dfs " (.-name s) ")"))
    ((a/topEnum e)
     (str "(:dfe " (.-name e) ")"))
    (_ "")))

(df extractModuleName [(forms (List a/TopForm))] -> Str
  (fold (fn [(acc Str) (f a/TopForm)] -> Str
          (mt f
            ((a/topModule m) (.-path m))
            (_ acc)))
        "unknown"
        forms))

(df generateAstOutline [(src Str) (path Str)] -> (Result Str Str)
  :d "Extracts structural symbol signatures without function bodies, adhering to Zero-Line-Number Invariant."
  (mt (a/parse src)
    ((err pe)
     (err (str "Parse error in outline: " (.-msg pe))))
    ((ok forms)
     (let [(modName (extractModuleName forms))
           (sigStrs (fold (fn [(acc (List Str)) (f a/TopForm)] -> (List Str)
                            (let [(sig (formatTopFormSignature f))]
                              (if (string-empty? sig)
                                  acc
                                  (list-append acc (list sig)))))
                          (list)
                          forms))
           (symbolsJoined (fold (fn [(acc Str) (sig Str)] -> Str
                                  (if (string-empty? acc)
                                      sig
                                      (str acc "\n    " sig)))
                                ""
                                sigStrs))
           (outline (str "(:outline\n"
                         "  :module \"" modName "\"\n"
                         "  :symbols [\n    "
                         symbolsJoined
                         "\n  ])\n"))]
       (ok outline)))))

(df runOutlineCommand [(args (List Str))] -> (Result Str Str)
  :d "Dispatches asl outline subcommand on target file."
  (if (list-empty? args)
      (err "Usage: asl outline <file.asl>")
      (let [(firstArg (option-or (list-head args) ""))]
        (if (or (= firstArg "-h") (= firstArg "--help"))
            (ok (formatOutlineHelp))
            (let [(path firstArg)
                  (readRes (file-read path))]
              (mt readRes
                ((err _) (err (str "Failed to read target file: " path)))
                ((ok src) (generateAstOutline src path))))))))
