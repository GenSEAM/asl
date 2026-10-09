(module grammar/densityTest
  :x [runTests])

fn symTokens body: String -> Int64
  (mt (listGet (stringSplit body ":tokens ") 1)
    ((some rest) (mt (listHead (stringSplit rest " ")) ((some word) (optionOr (stringToInt64 (stringTrim word)) 0)) ((none) 0)))
    ((none) 0))

fn symBody entry: String -> String
  (mt (stringIndexOf entry ")")
    ((some i) (optionOr (stringSlice entry 0 i) entry))
    ((none) entry))

fn overBudget? body: String -> Bool
  (and (> (symTokens body) 2) (not (stringContains? body ":rationale")))

fn symBodies text: String -> (List String)
  (map (fn [e] (symBody e)) (optionOr (listTail (stringSplit text "(:sym ")) (list)))

fn grammarText! -> String
  (mt (fileRead "asl/grammar/grammar.asn")
    ((ok text) text)
    ((err e) ""))

fn ! runTests -> Bool
  (let [(bodies (symBodies (grammarText!)))]
    (do
      (assert (= (symTokens ":name \"x\" :kind :fn :tokens 4") 4) "the :tokens value is read")
      (assert (overBudget? ":name \"x\" :kind :fn :tokens 4") "4 tokens without :rationale is over budget")
      (refute (overBudget? ":name \"x\" :kind :fn :tokens 4 :rationale \"why\"") "a :rationale admits it")
      (refute (overBudget? ":name \"x\" :kind :fn :tokens 2") "2 tokens is within budget")
      (assert (= (listLength bodies) 48) "grammar.asn declares 48 symbols")
      (assert (= (listLength (filter (fn [b] (overBudget? b)) bodies)) 0) "no symbol above 2 tokens lacks a :rationale")
      (assert (= (listLength (filter (fn [b] (> (symTokens b) 2)) bodies)) 6) "six symbols cost more than 2 tokens")
      true))
