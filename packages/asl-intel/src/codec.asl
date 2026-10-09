(module aslIntel/codec :x [encodeSymbolAsn encodeEdgeAsn encodeImpactAsn encodeAsnResponse])

fn encodeSymbolAsn name: Str kind: Str loc: Str sig: Str exported: Bool -> Str
  (str "(:s \"" name "\" :" kind " :at \"" loc "\"" (if exported " :x" "") " :sig \"" sig "\")")

fn encodeEdgeAsn src: Str dst: Str kind: Str -> Str
  (str "(:e \"" src "\" :" kind " \"" dst "\")")

fn encodeImpactAsn name: Str file: Str depth: I64 -> Str
  (str "(:i \"" name "\" :at \"" file "\" :d " (stringFromInt64 depth) ")")

fn encodeAsnResponse tag: Str frames: (List Str) -> Str
  (str "(:" tag "\n  " (stringJoin frames "\n  ") "\n)")
