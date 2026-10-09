(module asl-cli/digest :x [generateAstOutline formatOutlineHelp formatImpactHelp runOutlineCommand!] :i [(asl-parser/ast :a a) (asl-parser/reader :a rd)])

fn formatOutlineHelp -> Str
  (str "Usage: asl outline <file.asl>\n\n" "Extracts structural symbol signatures without internal bodies strictly under sub-80 token SLA.\n\n" "[Teleology] Principle: HighSNROverFullContext (ADR D97)\n" "  \"Outlines deliver maximal decision entropy with zero line numbers and zero body noise.\"\n\n" "[Assistive Ontology] Enforces:\n" "  • Signature Extraction: Function params and return types without expressions\n" "  • Zero-Line-Number Invariant: Symbols addressed strictly by name\n")

fn formatImpactHelp -> Str
  (str "Usage: asl impact <symbol>\n\n" "Analyzes blast radius, direct callers, test dependencies, and type signatures strictly under 80 tokens.\n\n" "Arguments:\n" "  <symbol>    Target function, struct, or type identifier (Module:symbol or symbol)\n\n" "[Teleology] Principle: GroundTruthOverReport (ADR D94)\n" "  \"Codebase hypergraph queries bound perceptual tokens (<80 tokens) with zero line numbers.\"\n")

fn formatParam p: a/Param -> Str
  (str "(" p.name " " p.type ")")

fn formatParamList params: (List a/Param) -> Str
  (if (listEmpty? params) "[]" (let [(inner (fold (fn [(acc Str) (p a/Param)] -> Str (let [(item (formatParam p))] (if (stringEmpty? acc) item (str acc " " item)))) "" params))] (str "[" inner "]")))

fn formatTopFormSignature form: a/TopForm -> Str
  (mt form ((a/topDefun f) (str "(:df " f.name " " (formatParamList f.params) " -> " f.retType ")")) ((a/topSchema s) (str "(:dfs " s.name ")")) ((a/topEnum e) (str "(:dfe " e.name ")")) (_ ""))

fn extractModuleName forms: (List a/TopForm) -> Str
  (fold (fn [(acc Str) (f a/TopForm)] -> Str (mt f ((a/topModule m) m.path) (_ acc))) "unknown" forms)

fn generateAstOutline src: Str path: Str -> (Result Str Str)
  (mt (a/parse src) ((err pe) (err (str "Parse error in outline: " pe.msg))) ((ok forms) (let [(modName (extractModuleName forms)) (sigStrs (fold (fn [(acc (List Str)) (f a/TopForm)] -> (List Str) (let [(sig (formatTopFormSignature f))] (if (stringEmpty? sig) acc (listAppend acc (list sig))))) (list) forms)) (symbolsJoined (fold (fn [(acc Str) (sig Str)] -> Str (if (stringEmpty? acc) sig (str acc "\n    " sig))) "" sigStrs)) (outline (str "(:outline\n" "  :module \"" modName "\"\n" "  :symbols [\n    " symbolsJoined "\n  ])\n"))] (ok outline))))

fn runOutlineCommand! args: (List Str) -> (Result Str Str)
  (if (listEmpty? args) (err "Usage: asl outline <file.asl>") (let [(firstArg (optionOr (listHead args) ""))] (if (or (= firstArg "-h") (= firstArg "--help")) (ok (formatOutlineHelp)) (let [(path firstArg) (readRes (fileRead path))] (mt readRes ((err _) (err (str "Failed to read target file: " path))) ((ok src) (generateAstOutline src path)))))))
