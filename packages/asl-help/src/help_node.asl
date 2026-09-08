(module asl-help/help-node
  :d "Canonical HelpNode Schema and Compact CS-Expression Codec"
  :x [HelpNode
      make-help-node
      make-empty-help-node
      format-help-node
      parse-help-node
      format-constraints]
  :i [])

(dfs HelpNode
  (:f sym Str "Symbol identifier, e.g. pmap")
  (:f cat Str "Category taxonomy, e.g. concurrency, memory, eval, effect, help")
  (:f ver Str "Language or runtime version, e.g. 0.3.3")
  (:f sig Str "Canonical function signature")
  (:f desc Str "Operational summary")
  (:f constraints (List Str) "Runtime constraints and behavioral invariants")
  (:f example Str "Idiomatic usage expression")
  (:f cost-tokens I64 "Approximate token cost in CS-expression format"))

(df make-help-node [(sym Str) (cat Str) (ver Str) (sig Str) (desc Str) (constraints (List Str)) (example Str) (cost-tokens I64)] -> HelpNode
  :d "Constructs a canonical HelpNode record."
  (HelpNode
    :sym sym
    :cat cat
    :ver ver
    :sig sig
    :desc desc
    :constraints constraints
    :example example
    :cost-tokens cost-tokens))

(df make-empty-help-node [] -> HelpNode
  :d "Constructs an empty HelpNode record."
  (HelpNode
    :sym ""
    :cat ""
    :ver ""
    :sig ""
    :desc ""
    :constraints (list)
    :example ""
    :cost-tokens 0))

(df format-constraints [(cs (List Str))] -> Str
  :d "Formats a list of constraint strings into bracketed vector format."
  (if (list-empty? cs)
      "[]"
      (str "[" (string-join (map (fn [(c Str)] -> Str (str "\"" c "\"")) cs) " ") "]")))

(df format-help-node [(node HelpNode)] -> Str
  :d "Serializes a HelpNode record to a compact ASN CS-expression string."
  (str "(:help-node :sym \"" (.-sym node)
       "\" :cat \"" (.-cat node)
       "\" :ver \"" (.-ver node)
       "\" :sig \"" (.-sig node)
       "\" :desc \"" (.-desc node)
       "\" :constraints " (format-constraints (.-constraints node))
       " :example \"" (.-example node)
       "\" :cost-tokens " (string-from-int64 (.-cost-tokens node)) ")"))

(df extract-between [(text Str) (prefix Str) (suffix Str)] -> (Option Str)
  :d "Extracts substring between prefix and subsequent suffix."
  (let [(start-idx-opt (string-index-of text prefix))]
    (if (is-none? start-idx-opt)
        (none)
        (let [(start-idx (option-or start-idx-opt 0))
              (start-pos (+ start-idx (string-length prefix)))
              (remaining (option-or (string-slice text start-pos (string-length text)) ""))
              (end-idx-opt (string-index-of remaining suffix))]
          (if (is-none? end-idx-opt)
              (none)
              (let [(end-idx (option-or end-idx-opt 0))]
                (string-slice remaining 0 end-idx)))))))

(df parse-help-node [(cs Str)] -> (Option HelpNode)
  :d "Deserializes a compact ASN CS-expression string into a HelpNode record."
  (let [(trimmed (string-trim cs))]
    (if (or (not (string-starts-with? trimmed "(:help-node"))
            (not (string-ends-with? trimmed ")")))
        (none)
        (let [(sym-opt (extract-between trimmed ":sym \"" "\""))
              (cat-opt (extract-between trimmed ":cat \"" "\""))
              (ver-opt (extract-between trimmed ":ver \"" "\""))
              (sig-opt (extract-between trimmed ":sig \"" "\""))
              (desc-opt (extract-between trimmed ":desc \"" "\""))
              (example-opt (extract-between trimmed ":example \"" "\""))
              (cost-str-opt (extract-between trimmed ":cost-tokens " ")"))]
          (if (or (is-none? sym-opt)
                  (or (is-none? cat-opt)
                      (is-none? cost-str-opt)))
              (none)
              (let [(sym-val (option-or sym-opt ""))
                    (cat-val (option-or cat-opt ""))
                    (ver-val (option-or ver-opt "0.3.3"))
                    (sig-val (option-or sig-opt ""))
                    (desc-val (option-or desc-opt ""))
                    (example-val (option-or example-opt ""))
                    (cost-raw (option-or cost-str-opt "0"))
                    (cost-val (option-or (string-to-int64 (string-trim cost-raw)) 0))]
                (some (make-help-node sym-val cat-val ver-val sig-val desc-val (list) example-val cost-val))))))))
