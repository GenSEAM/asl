(module asl-derive/derive :x [FieldDef RecordSchema VariantCaseDef VariantSchema JsonCodec AsnCodec VisitorCode VariantCodec makeField makeRecordSchema makeVariantCase makeVariantSchema deriveJsonCodec deriveAsnCodec deriveRecordVisitor deriveVariantCodec formatRecordToJson formatRecordToAsn parseJsonToFieldPairs parseAsnToFieldPairs] :i [])

(schema FieldDef (:f name Str) (:f typeName Str) (:f isOptional Bool))

(schema RecordSchema (:f name Str) (:f tableName Str) (:f primaryKey (Option Str)) (:f fields (List FieldDef)))

(schema VariantCaseDef (:f tagName Str) (:f payloadType (Option Str)))

(schema VariantSchema (:f name Str) (:f cases (List VariantCaseDef)))

(schema JsonCodec (:f status Str) (:f schemaName Str) (:f encoderSource Str) (:f decoderSource Str))

(schema AsnCodec (:f status Str) (:f schemaName Str) (:f encoderSource Str) (:f decoderSource Str))

(schema VisitorCode (:f status Str) (:f schemaName Str) (:f totalFields Int) (:f fieldNames Str) (:f visitorSource Str))

(schema VariantCodec (:f status Str) (:f schemaName Str) (:f totalCases Int) (:f caseNames Str) (:f encoderSource Str) (:f decoderSource Str))

fn makeField name: Str typeName: Str isOptional: Bool -> FieldDef
  (FieldDef :name name :typeName typeName :isOptional isOptional)

fn makeRecordSchema name: Str tableName: Str primaryKey: (Option Str) fields: (List FieldDef) -> RecordSchema
  (RecordSchema :name name :tableName tableName :primaryKey primaryKey :fields fields)

fn makeVariantCase tagName: Str payloadType: (Option Str) -> VariantCaseDef
  (VariantCaseDef :tagName tagName :payloadType payloadType)

fn makeVariantSchema name: Str cases: (List VariantCaseDef) -> VariantSchema
  (VariantSchema :name name :cases cases)

fn buildJsonFieldExpr f: FieldDef -> Str
  (let [(fName f.name) (tName f.typeName) (opt f.isOptional)] (if opt (str "(mt r." fName " ((some v) (str \"\\\"" fName "\\\": \" (if (= \"" tName "\" \"Str\") (str \"\\\"\" v \"\\\"\") (int-to-string v)))) ((none) \"\\\"" fName "\\\": null\"))") (if (= tName "Str") (str "(str \"\\\"" fName "\\\": \\\"\" r." fName " \"\\\"\")") (if (= tName "Bool") (str "(str \"\\\"" fName "\\\": \" (if r." fName " \"true\" \"false\"))") (str "(str \"\\\"" fName "\\\": \" (int-to-string r." fName "))")))))

fn deriveJsonCodec schema: RecordSchema -> JsonCodec
  (let [(sName schema.name) (fields schema.fields) (fieldExprs (map (fn [(f FieldDef)] (buildJsonFieldExpr f)) fields)) (joinedExprs (stringJoin fieldExprs " \", \" ")) (encSrc (str "fn serialize" sName "ToJson r: " sName " -> Str\n" "  :d \"Generated zero-cost monomorphic JSON serializer for " sName "\"\n" "  (str \"{\" " joinedExprs " \"}\")")) (decFieldLines (map (fn [(f FieldDef)] (str "    :" f.name " (extract" f.typeName " json \"" f.name "\")")) fields)) (decFieldsJoined (stringJoin decFieldLines "\n")) (decSrc (str "fn deserialize" sName "FromJson json: Str -> " sName "\n" "  :d \"Generated zero-cost monomorphic JSON deserializer for " sName "\"\n" "  (" sName "\n" decFieldsJoined ")"))] (JsonCodec :status "ok" :schemaName sName :encoderSource encSrc :decoderSource decSrc))

fn buildAsnFieldExpr f: FieldDef -> Str
  (let [(fName f.name) (tName f.typeName) (opt f.isOptional)] (if opt (str "(mt r." fName " ((some v) (str \":" fName " (some \" (if (= \"" tName "\" \"Str\") (str \"\\\"\" v \"\\\"\") (int-to-string v)) \")\")) ((none) \":" fName " (none)\"))") (if (= tName "Str") (str "(str \":" fName " \\\"\" r." fName " \"\\\"\")") (if (= tName "Bool") (str "(str \":" fName " \" (if r." fName " \"true\" \"false\"))") (str "(str \":" fName " \" (int-to-string r." fName "))")))))

fn deriveAsnCodec schema: RecordSchema -> AsnCodec
  (let [(sName schema.name) (fields schema.fields) (fieldExprs (map (fn [(f FieldDef)] (buildAsnFieldExpr f)) fields)) (joinedExprs (stringJoin fieldExprs " \" \" ")) (encSrc (str "fn serialize" sName "ToAsn r: " sName " -> Str\n" "  :d \"Generated zero-cost monomorphic ASN serializer for " sName "\"\n" "  (str \"(:" sName " \" " joinedExprs " \")\")")) (decFieldLines (map (fn [(f FieldDef)] (str "    :" f.name " (extractAsn" f.typeName " asn \"" f.name "\")")) fields)) (decFieldsJoined (stringJoin decFieldLines "\n")) (decSrc (str "fn deserialize" sName "FromAsn asn: Str -> " sName "\n" "  :d \"Generated zero-cost monomorphic ASN deserializer for " sName "\"\n" "  (" sName "\n" decFieldsJoined ")"))] (AsnCodec :status "ok" :schemaName sName :encoderSource encSrc :decoderSource decSrc))

fn deriveRecordVisitor schema: RecordSchema -> VisitorCode
  (let [(sName schema.name) (fields schema.fields) (fCount (listLength fields)) (fNameList (map (fn [(f FieldDef)] f.name) fields)) (fNamesJoined (stringJoin fNameList ",")) (visitLines (map (fn [(f FieldDef)] (str "    (visitor \"" f.name "\" \"" f.typeName "\" r." f.name ")")) fields)) (visitBodyJoined (stringJoin visitLines "\n")) (visSrc (str "fn visit" sName "Fields r: " sName " visitor: (fn [(Str Str Any)] -> Unit) -> Unit\n" "  :d \"Generated zero-cost monomorphic field visitor for " sName "\"\n" "  (do\n" visitBodyJoined ")"))] (VisitorCode :status "ok" :schemaName sName :totalFields fCount :fieldNames fNamesJoined :visitorSource visSrc))

fn deriveVariantCodec schema: VariantSchema -> VariantCodec
  (let [(vName schema.name) (cases schema.cases) (cCount (listLength cases)) (cNameList (map (fn [(c VariantCaseDef)] c.tagName) cases)) (cNamesJoined (stringJoin cNameList ",")) (encArms (map (fn [(c VariantCaseDef)] (let [(tag c.tagName)] (mt c.payloadType ((some pType) (str "    ((" tag " payload) (str \"(:" tag " \" (serialize" pType " payload) \")\"))")) ((none) (str "    ((" tag ") \"(:" tag ")\")"))))) cases)) (encArmsJoined (stringJoin encArms "\n")) (encSrc (str "fn serialize" vName "ToAsn v: " vName " -> Str\n" "  :d \"Generated zero-cost monomorphic pattern-matching ASN serializer for " vName "\"\n" "  (mt v\n" encArmsJoined ")")) (decArms (map (fn [(c VariantCaseDef)] (let [(tag c.tagName)] (mt c.payloadType ((some pType) (str "    (if (stringStartsWith? asn \"(:" tag " \") (" tag " (deserialize" pType " (extractPayload asn)))")) ((none) (str "    (if (= asn \"(:" tag ")\") (" tag ")"))))) cases)) (decArmsJoined (stringJoin decArms "\n")) (decSrc (str "fn deserialize" vName "FromAsn asn: Str -> " vName "\n" "  :d \"Generated zero-cost monomorphic ASN deserializer for " vName "\"\n" decArmsJoined " (panic \"invalid variant tag\")))))"))] (VariantCodec :status "ok" :schemaName vName :totalCases cCount :caseNames cNamesJoined :encoderSource encSrc :decoderSource decSrc))

fn formatRecordToJson schema: RecordSchema fieldVals: (List (Pair Str Str)) -> Str
  (let [(pairs (map (fn [(p (pair Str Str))] (let [(k (pairFirst p)) (v (pairSecond p))] (if (or (= v "true") (or (= v "false") (or (= v "null") (stringStartsWith? v "\"")))) (str "\"" k "\": " v) (str "\"" k "\": " v)))) fieldVals)) (joined (stringJoin pairs ", "))] (str "{" joined "}"))

fn formatRecordToAsn schema: RecordSchema fieldVals: (List (Pair Str Str)) -> Str
  (let [(pairs (map (fn [(p (pair Str Str))] (let [(k (pairFirst p)) (v (pairSecond p))] (str ":" k " " v))) fieldVals)) (joined (stringJoin pairs " "))] (str "(:" schema.name " " joined ")"))

fn parseJsonToFieldPairs schema: RecordSchema json: Str -> (List (Pair Str Str))
  (let [(fields schema.fields)] (map (fn [(f FieldDef)] (let [(k f.name) (marker (str "\"" k "\":")) (posOpt (stringIndexOf json marker)) (valStr (mt posOpt ((none) "") ((some pos) (let [(rest (optionOr (stringSlice json (+ pos (stringLength marker)) (stringLength json)) "")) (trimmed (stringTrim rest))] (if (stringStartsWith? trimmed "\"") (let [(afterQ (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "")) (qClose (optionOr (stringIndexOf afterQ "\"") 0))] (optionOr (stringSlice afterQ 0 qClose) "")) (let [(stopComma (optionOr (stringIndexOf trimmed ",") (stringLength trimmed))) (stopBrace (optionOr (stringIndexOf trimmed "}") (stringLength trimmed))) (stopIdx (if (< stopComma stopBrace) stopComma stopBrace))] (stringTrim (optionOr (stringSlice trimmed 0 stopIdx) ""))))))))] (pair k valStr))) fields))

fn parseAsnToFieldPairs schema: RecordSchema asn: Str -> (List (Pair Str Str))
  (let [(fields schema.fields)] (map (fn [(f FieldDef)] (let [(k f.name) (marker (str ":" k " ")) (posOpt (stringIndexOf asn marker)) (valStr (mt posOpt ((none) "") ((some pos) (let [(rest (optionOr (stringSlice asn (+ pos (stringLength marker)) (stringLength asn)) "")) (trimmed (stringTrim rest))] (if (stringStartsWith? trimmed "\"") (let [(afterQ (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "")) (qClose (optionOr (stringIndexOf afterQ "\"") 0))] (optionOr (stringSlice afterQ 0 qClose) "")) (if (stringStartsWith? trimmed "(") (let [(pClose (optionOr (stringIndexOf trimmed ")") (stringLength trimmed)))] (optionOr (stringSlice trimmed 0 (+ pClose 1)) "")) (let [(stopSpace (optionOr (stringIndexOf trimmed " ") (stringLength trimmed))) (stopParen (optionOr (stringIndexOf trimmed ")") (stringLength trimmed))) (stopIdx (if (< stopSpace stopParen) stopSpace stopParen))] (stringTrim (optionOr (stringSlice trimmed 0 stopIdx) "")))))))))] (pair k valStr))) fields))
