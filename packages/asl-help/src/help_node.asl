(module asl-help/helpNode
  :d "Canonical HelpNode Schema and Compact CS-Expression Codec"
  :x [HelpNode
      makeHelpNode
      makeEmptyHelpNode
      formatHelpNode
      parseHelpNode
      formatConstraints]
  :i [])

(dfs HelpNode
  (:f sym Str "Symbol identifier, e.g. pmap")
  (:f cat Str "Category taxonomy, e.g. concurrency, memory, eval, effect, help")
  (:f ver Str "Language or runtime version, e.g. 0.3.3")
  (:f sig Str "Canonical function signature")
  (:f desc Str "Operational summary")
  (:f constraints (List Str) "Runtime constraints and behavioral invariants")
  (:f example Str "Idiomatic usage expression")
  (:f costTokens I64 "Approximate token cost in CS-expression format"))

(df makeHelpNode [(sym Str) (cat Str) (ver Str) (sig Str) (desc Str) (constraints (List Str)) (example Str) (costTokens I64)] -> HelpNode
  :d "Constructs a canonical HelpNode record."
  (HelpNode
    :sym sym
    :cat cat
    :ver ver
    :sig sig
    :desc desc
    :constraints constraints
    :example example
    :costTokens costTokens))

(df makeEmptyHelpNode [] -> HelpNode
  :d "Constructs an empty HelpNode record."
  (HelpNode
    :sym ""
    :cat ""
    :ver ""
    :sig ""
    :desc ""
    :constraints (list)
    :example ""
    :costTokens 0))

(df formatConstraints [(cs (List Str))] -> Str
  :d "Formats a list of constraint strings into bracketed vector format."
  (if (list-empty? cs)
      "[]"
      (str "[" (string-join (map (fn [(c Str)] -> Str (str "\"" c "\"")) cs) " ") "]")))

(df formatHelpNode [(node HelpNode)] -> Str
  :d "Serializes a HelpNode record to a compact ASN CS-expression string."
  (str "(:help-node :sym \"" (.-sym node)
       "\" :cat \"" (.-cat node)
       "\" :ver \"" (.-ver node)
       "\" :sig \"" (.-sig node)
       "\" :desc \"" (.-desc node)
       "\" :constraints " (formatConstraints (.-constraints node))
       " :example \"" (.-example node)
       "\" :cost-tokens " (string-from-int64 (.-costTokens node)) ")"))

(df extractBetween [(text Str) (prefix Str) (suffix Str)] -> (Option Str)
  :d "Extracts substring between prefix and subsequent suffix."
  (let [(startIdxOpt (string-index-of text prefix))]
    (if (is-none? startIdxOpt)
        (none)
        (let [(startIdx (option-or startIdxOpt 0))
              (startPos (+ startIdx (string-length prefix)))
              (remaining (option-or (string-slice text startPos (string-length text)) ""))
              (endIdxOpt (string-index-of remaining suffix))]
          (if (is-none? endIdxOpt)
              (none)
              (let [(endIdx (option-or endIdxOpt 0))]
                (string-slice remaining 0 endIdx)))))))

(df parseHelpNode [(cs Str)] -> (Option HelpNode)
  :d "Deserializes a compact ASN CS-expression string into a HelpNode record."
  (let [(trimmed (string-trim cs))]
    (if (or (not (string-starts-with? trimmed "(:help-node"))
            (not (string-ends-with? trimmed ")")))
        (none)
        (let [(symOpt (extractBetween trimmed ":sym \"" "\""))
              (catOpt (extractBetween trimmed ":cat \"" "\""))
              (verOpt (extractBetween trimmed ":ver \"" "\""))
              (sigOpt (extractBetween trimmed ":sig \"" "\""))
              (descOpt (extractBetween trimmed ":desc \"" "\""))
              (exampleOpt (extractBetween trimmed ":example \"" "\""))
              (costStrOpt (extractBetween trimmed ":cost-tokens " ")"))]
          (if (or (is-none? symOpt)
                  (or (is-none? catOpt)
                      (is-none? costStrOpt)))
              (none)
              (let [(symVal (option-or symOpt ""))
                    (catVal (option-or catOpt ""))
                    (verVal (option-or verOpt "0.3.3"))
                    (sigVal (option-or sigOpt ""))
                    (descVal (option-or descOpt ""))
                    (exampleVal (option-or exampleOpt ""))
                    (costRaw (option-or costStrOpt "0"))
                    (costVal (option-or (string-to-int64 (string-trim costRaw)) 0))]
                (some (makeHelpNode symVal catVal verVal sigVal descVal (list) exampleVal costVal))))))))
