(module asl-help/helpNode :x [HelpNode makeHelpNode makeEmptyHelpNode formatHelpNode parseHelpNode formatConstraints] :i [(asl-text/text :a txt)])

(schema HelpNode (:f sym Str) (:f cat Str) (:f ver Str) (:f sig Str) (:f desc Str) (:f constraints (List Str)) (:f example Str) (:f costTokens I64))

fn makeHelpNode sym: Str cat: Str ver: Str sig: Str desc: Str constraints: (List Str) example: Str costTokens: I64 -> HelpNode
  (HelpNode :sym sym :cat cat :ver ver :sig sig :desc desc :constraints constraints :example example :costTokens costTokens)

fn makeEmptyHelpNode -> HelpNode
  (HelpNode :sym "" :cat "" :ver "" :sig "" :desc "" :constraints (list) :example "" :costTokens 0)

fn formatConstraints cs: (List Str) -> Str
  (if (listEmpty? cs) "[]" (str "[" (stringJoin (map (fn [(c Str)] -> Str (str "\"" c "\"")) cs) " ") "]"))

fn formatHelpNode node: HelpNode -> Str
  (str "(:help-node :sym \"" node.sym "\" :cat \"" node.cat "\" :ver \"" node.ver "\" :sig \"" node.sig "\" :desc \"" node.desc "\" :constraints " (formatConstraints node.constraints) " :example \"" node.example "\" :cost-tokens " (stringFromInt64 node.costTokens) ")")

fn parseHelpNode cs: Str -> (Option HelpNode)
  (let [(trimmed (stringTrim cs))] (if (or (not (stringStartsWith? trimmed "(:help-node")) (not (stringEndsWith? trimmed ")"))) (none) (let [(symOpt (txt/extractBetween trimmed ":sym \"" "\"")) (catOpt (txt/extractBetween trimmed ":cat \"" "\"")) (verOpt (txt/extractBetween trimmed ":ver \"" "\"")) (sigOpt (txt/extractBetween trimmed ":sig \"" "\"")) (descOpt (txt/extractBetween trimmed ":desc \"" "\"")) (exampleOpt (txt/extractBetween trimmed ":example \"" "\"")) (costStrOpt (txt/extractBetween trimmed ":cost-tokens " ")"))] (if (or (none? symOpt) (or (none? catOpt) (none? costStrOpt))) (none) (let [(symVal (optionOr symOpt "")) (catVal (optionOr catOpt "")) (verVal (optionOr verOpt "0.3.3")) (sigVal (optionOr sigOpt "")) (descVal (optionOr descOpt "")) (exampleVal (optionOr exampleOpt "")) (costRaw (optionOr costStrOpt "0")) (costVal (optionOr (stringToInt64 (stringTrim costRaw)) 0))] (some (makeHelpNode symVal catVal verVal sigVal descVal (list) exampleVal costVal)))))))
