(module asl-gates/grammar-gate
  :d "Pure AgentScript ASN grammar registry and token density verification gate."
  :x [SymbolKind SymbolEntry GrammarRegistry
      sym-fn sym-type sym-val sym-macro
      make-symbol-entry count-kebab-tokens audit-symbol-density
      is-registered? get-registered-symbol]
  :i [])

(dfe SymbolKind
  (:c sym-fn [] "Function or closure symbol")
  (:c sym-type [] "Struct or enum type symbol")
  (:c sym-val [] "Constant value symbol")
  (:c sym-macro [] "Syntactic macro symbol"))

(dfs SymbolEntry
  (:f name Str "Exported symbol name identifier")
  (:f kind SymbolKind "Symbol category")
  (:f tokens I64 "Token count based on hyphen segments")
  (:f has-rationale Bool "True if explicit :rationale is provided")
  (:f rationale Str "Architectural justification for multi-token symbols"))

(dfs GrammarRegistry
  (:f package Str "Package identifier e.g. asl-codec")
  (:f baseline I64 "Baseline token ceiling (default: 1)")
  (:f symbols (List SymbolEntry) "List of registered symbols"))

(df make-symbol-entry [(name Str) (kind SymbolKind) (tokens I64) (has-rationale Bool) (rationale Str)] -> SymbolEntry
  (SymbolEntry
    :name name
    :kind kind
    :tokens tokens
    :has-rationale has-rationale
    :rationale rationale))

(df count-kebab-tokens [(sym Str)] -> I64
  :d "Calculates token density by counting kebab-case hyphen-separated segments."
  (let [(parts (string-split sym "-"))]
    (max 1 (list-length parts))))

(df audit-symbol-density [(entry SymbolEntry) (baseline I64)] -> Bool
  :d "Enforces token density policy: symbols > baseline must carry verified :rationale."
  (if (<= (.-tokens entry) baseline)
      true
      (and (.-has-rationale entry)
           (> (string-length (.-rationale entry)) 0))))

(df is-registered? [(sym-name Str) (registry (List SymbolEntry))] -> Bool
  :d "Checks if a symbol is present in the registered grammar registry."
  (let [(matches (filter (fn [(e SymbolEntry)] -> Bool (= (.-name e) sym-name)) registry))]
    (not (list-empty? matches))))

(df get-registered-symbol [(sym-name Str) (registry (List SymbolEntry))] -> (Option SymbolEntry)
  :d "Retrieves a registered SymbolEntry by name."
  (let [(matches (filter (fn [(e SymbolEntry)] -> Bool (= (.-name e) sym-name)) registry))]
    (list-head matches)))
