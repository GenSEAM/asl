(module asl-gates/grammarGate :x [SymbolKind SymbolEntry GrammarRegistry symFn symType symVal symMacro makeSymbolEntry countKebabTokens auditSymbolDensity isRegistered? getRegisteredSymbol] :i [])

(enum SymbolKind (:c symFn [] "Function or closure symbol") (:c symType [] "Struct or enum type symbol") (:c symVal [] "Constant value symbol") (:c symMacro [] "Syntactic macro symbol"))

(schema SymbolEntry (:f name Str) (:f kind SymbolKind) (:f tokens I64) (:f hasRationale Bool) (:f rationale Str))

(schema GrammarRegistry (:f package Str) (:f baseline I64) (:f symbols (List SymbolEntry)))

fn makeSymbolEntry name: Str kind: SymbolKind tokens: I64 hasRationale: Bool rationale: Str -> SymbolEntry
  (SymbolEntry :name name :kind kind :tokens tokens :hasRationale hasRationale :rationale rationale)

fn countKebabTokens sym: Str -> I64
  (let [(parts (stringSplit sym "-"))] (max 1 (listLength parts)))

fn auditSymbolDensity entry: SymbolEntry baseline: I64 -> Bool
  (if (<= entry.tokens baseline) true (and entry.hasRationale (> (stringLength entry.rationale) 0)))

fn isRegistered? symName: Str registry: (List SymbolEntry) -> Bool
  (let [(matches (filter (fn [(e SymbolEntry)] -> Bool (= e.name symName)) registry))] (not (listEmpty? matches)))

fn getRegisteredSymbol symName: Str registry: (List SymbolEntry) -> (Option SymbolEntry)
  (let [(matches (filter (fn [(e SymbolEntry)] -> Bool (= e.name symName)) registry))] (listHead matches))
