(module asl-gates/grammarGate
  :d "Pure AgentScript ASN grammar registry and token density verification gate."
  :x [SymbolKind SymbolEntry GrammarRegistry
      symFn symType symVal symMacro
      makeSymbolEntry countKebabTokens auditSymbolDensity
      isRegistered? getRegisteredSymbol]
  :i [])

(dfe SymbolKind
  (:c symFn [] "Function or closure symbol")
  (:c symType [] "Struct or enum type symbol")
  (:c symVal [] "Constant value symbol")
  (:c symMacro [] "Syntactic macro symbol"))

(dfs SymbolEntry
  (:f name Str "Exported symbol name identifier")
  (:f kind SymbolKind "Symbol category")
  (:f tokens I64 "Token count based on hyphen segments")
  (:f hasRationale Bool "True if explicit :rationale is provided")
  (:f rationale Str "Architectural justification for multi-token symbols"))

(dfs GrammarRegistry
  (:f package Str "Package identifier e.g. asl-codec")
  (:f baseline I64 "Baseline token ceiling (default: 1)")
  (:f symbols (List SymbolEntry) "List of registered symbols"))

(df makeSymbolEntry [(name Str) (kind SymbolKind) (tokens I64) (hasRationale Bool) (rationale Str)] -> SymbolEntry
  (SymbolEntry
    :name name
    :kind kind
    :tokens tokens
    :hasRationale hasRationale
    :rationale rationale))

(df countKebabTokens [(sym Str)] -> I64
  :d "Calculates token density by counting kebab-case hyphen-separated segments."
  (let [(parts (string-split sym "-"))]
    (max 1 (list-length parts))))

(df auditSymbolDensity [(entry SymbolEntry) (baseline I64)] -> Bool
  :d "Enforces token density policy: symbols > baseline must carry verified :rationale."
  (if (<= (.-tokens entry) baseline)
      true
      (and (.-hasRationale entry)
           (> (string-length (.-rationale entry)) 0))))

(df isRegistered? [(symName Str) (registry (List SymbolEntry))] -> Bool
  :d "Checks if a symbol is present in the registered grammar registry."
  (let [(matches (filter (fn [(e SymbolEntry)] -> Bool (= (.-name e) symName)) registry))]
    (not (list-empty? matches))))

(df getRegisteredSymbol [(symName Str) (registry (List SymbolEntry))] -> (Option SymbolEntry)
  :d "Retrieves a registered SymbolEntry by name."
  (let [(matches (filter (fn [(e SymbolEntry)] -> Bool (= (.-name e) symName)) registry))]
    (list-head matches)))
