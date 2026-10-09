(module aslHarness/promptCache :x [PromptPrefix freezeSystemPrefix assembleCachedPrompt verifyPrefixStability] :i [])

(schema PromptPrefix (:f axiomsHash Str) (:f toolsHash Str) (:f canonicalPrefix Str))

fn insertStr item: Str sorted: (List Str) -> (List Str)
  (if (listEmpty? sorted) (list item) (let [(headS (optionOr (listHead sorted) "")) (tailS (optionOr (listTail sorted) (list)))] (if (<= item headS) (cons item sorted) (cons headS (insertStr item tailS)))))

fn sortStrListLoop unsorted: (List Str) sorted: (List Str) -> (List Str)
  (if (listEmpty? unsorted) sorted (let [(item (optionOr (listHead unsorted) "")) (rest (optionOr (listTail unsorted) (list)))] (sortStrListLoop rest (insertStr item sorted))))

fn sortStrings strings: (List Str) -> (List Str)
  (sortStrListLoop strings (list))

fn charVal ch: Str -> I64
  (let [(charset "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ !\"#$%&'()*+,-./:<=>?@[\\]^_`{|}~\t\n\r")] (mt (stringIndexOf charset ch) ((none) 127) ((some idx) (+ idx 32))))

fn fastStrHash text: Str -> Str
  (stringFromInt64 (fnv1a64 text))

fn freezeSystemPrefix axioms: (List Str) tools: (List Str) -> PromptPrefix
  (let [(sortedAxioms (sortStrings axioms)) (sortedTools (sortStrings tools)) (axBody (stringJoin sortedAxioms "\n")) (tlBody (stringJoin sortedTools "\n")) (axHash (fastStrHash axBody)) (tlHash (fastStrHash tlBody)) (prefixStr (str "(:system-prefix\n  :axioms [\n" (if (listEmpty? sortedAxioms) "" (str "    \"" (stringJoin sortedAxioms "\"\n    \"") "\"\n")) "  ]\n  :tools [\n" (if (listEmpty? sortedTools) "" (str "    \"" (stringJoin sortedTools "\"\n    \"") "\"\n")) "  ])\n(:dynamic-turn-marker)\n"))] (PromptPrefix :axiomsHash axHash :toolsHash tlHash :canonicalPrefix prefixStr))

fn assembleCachedPrompt prefix: PromptPrefix dynamicTurns: (List Str) -> Str
  (let [(frozen prefix.canonicalPrefix) (turnsStr (stringJoin dynamicTurns "\n"))] (str frozen turnsStr))

fn extractFrozenPrefix prompt: Str -> Str
  (let [(marker "(:dynamic-turn-marker)") (parts (stringSplit prompt marker))] (optionOr (listHead parts) prompt))

fn verifyPrefixStability p1: Str p2: Str -> Bool
  (let [(pref1 (extractFrozenPrefix p1)) (pref2 (extractFrozenPrefix p2))] (= pref1 pref2))
