(module asl-derive/derive
  :d "Pure AgentScript Zero-Cost Schema, Codec, and Monomorphic Serializer Generation Engine"
  :x [FieldDef RecordSchema VariantCaseDef VariantSchema
      JsonCodec AsnCodec VisitorCode VariantCodec
      makeField makeRecordSchema makeVariantCase makeVariantSchema
      deriveJsonCodec deriveAsnCodec deriveRecordVisitor deriveVariantCodec
      formatRecordToJson formatRecordToAsn
      parseJsonToFieldPairs parseAsnToFieldPairs]
  :i [])

(dfs FieldDef
  (:f name Str "Field identifier")
  (:f typeName Str "Declared field type (Int, Str, Bool, Float)")
  (:f isOptional Bool "True if field is wrapped in Option"))

(dfs RecordSchema
  (:f name Str "Schema identifier name")
  (:f tableName Str "Target database table name")
  (:f primaryKey (Option Str) "Primary key field name if applicable")
  (:f fields (List FieldDef) "List of declared field definitions"))

(dfs VariantCaseDef
  (:f tagName Str "Variant case constructor tag name")
  (:f payloadType (Option Str) "Optional payload type (none if unit case)"))

(dfs VariantSchema
  (:f name Str "Variant sum type identifier name")
  (:f cases (List VariantCaseDef) "List of variant cases"))

(dfs JsonCodec
  (:f status Str "ok or error status string")
  (:f schemaName Str "Name of target schema")
  (:f encoderSource Str "Generated ASL/IR serializer function source")
  (:f decoderSource Str "Generated ASL/IR deserializer function source"))

(dfs AsnCodec
  (:f status Str "ok or error status string")
  (:f schemaName Str "Name of target schema")
  (:f encoderSource Str "Generated ASL/IR ASN serializer function source")
  (:f decoderSource Str "Generated ASL/IR ASN deserializer function source"))

(dfs VisitorCode
  (:f status Str "ok or error status string")
  (:f schemaName Str "Name of target schema")
  (:f totalFields Int "Count of fields traversed")
  (:f fieldNames Str "Comma-separated list of traversed field names")
  (:f visitorSource Str "Generated ASL visitor function source"))

(dfs VariantCodec
  (:f status Str "ok or error status string")
  (:f schemaName Str "Name of target variant schema")
  (:f totalCases Int "Count of variant arm cases")
  (:f caseNames Str "Comma-separated list of variant arm tags")
  (:f encoderSource Str "Generated ASL/IR variant serializer function source")
  (:f decoderSource Str "Generated ASL/IR variant deserializer function source"))

(df makeField [(name Str) (typeName Str) (isOptional Bool)] -> FieldDef
  :d "Constructs a FieldDef descriptor."
  (FieldDef :name name :typeName typeName :isOptional isOptional))

(df makeRecordSchema [(name Str) (tableName Str) (primaryKey (Option Str)) (fields (List FieldDef))] -> RecordSchema
  :d "Constructs a RecordSchema descriptor."
  (RecordSchema :name name :tableName tableName :primaryKey primaryKey :fields fields))

(df makeVariantCase [(tagName Str) (payloadType (Option Str))] -> VariantCaseDef
  :d "Constructs a VariantCaseDef descriptor."
  (VariantCaseDef :tagName tagName :payloadType payloadType))

(df makeVariantSchema [(name Str) (cases (List VariantCaseDef))] -> VariantSchema
  :d "Constructs a VariantSchema descriptor."
  (VariantSchema :name name :cases cases))

(df buildJsonFieldExpr [(f FieldDef)] -> Str
  :d "Generates monomorphic direct field access expression for JSON serialization."
  (let [(fName (.-name f))
        (tName (.-typeName f))
        (opt (.-isOptional f))]
    (if opt
      (str "(mt (.-" fName " r) ((some v) (str \"\\\"" fName "\\\": \" (if (= \"" tName "\" \"Str\") (str \"\\\"\" v \"\\\"\") (int-to-string v)))) ((none) \"\\\"" fName "\\\": null\"))")
      (if (= tName "Str")
        (str "(str \"\\\"" fName "\\\": \\\"\" (.-" fName " r) \"\\\"\")")
        (if (= tName "Bool")
          (str "(str \"\\\"" fName "\\\": \" (if (.-" fName " r) \"true\" \"false\"))")
          (str "(str \"\\\"" fName "\\\": \" (int-to-string (.-" fName " r)))"))))))

(df deriveJsonCodec [(schema RecordSchema)] -> JsonCodec
  :d "Generates a monomorphic zero-cost JSON serializer and deserializer codec from schema."
  (let [(sName (.-name schema))
        (fields (.-fields schema))
        (fieldExprs (list-map (fn [(f FieldDef)] (buildJsonFieldExpr f)) fields))
        (joinedExprs (string-join fieldExprs " \", \" "))
        (encSrc (str "(df serialize" sName "ToJson [(r " sName ")] -> Str\n"
                     "  :d \"Generated zero-cost monomorphic JSON serializer for " sName "\"\n"
                     "  (str \"{\" " joinedExprs " \"}\"))"))
        (decFieldLines (list-map (fn [(f FieldDef)] (str "    :" (.-name f) " (extract" (.-typeName f) " json \"" (.-name f) "\")")) fields))
        (decFieldsJoined (string-join decFieldLines "\n"))
        (decSrc (str "(df deserialize" sName "FromJson [(json Str)] -> " sName "\n"
                     "  :d \"Generated zero-cost monomorphic JSON deserializer for " sName "\"\n"
                     "  (" sName "\n" decFieldsJoined "))"))]
    (JsonCodec
      :status "ok"
      :schemaName sName
      :encoderSource encSrc
      :decoderSource decSrc)))

(df buildAsnFieldExpr [(f FieldDef)] -> Str
  :d "Generates monomorphic direct field access expression for ASN serialization."
  (let [(fName (.-name f))
        (tName (.-typeName f))
        (opt (.-isOptional f))]
    (if opt
      (str "(mt (.-" fName " r) ((some v) (str \":" fName " (some \" (if (= \"" tName "\" \"Str\") (str \"\\\"\" v \"\\\"\") (int-to-string v)) \")\")) ((none) \":" fName " (none)\"))")
      (if (= tName "Str")
        (str "(str \":" fName " \\\"\" (.-" fName " r) \"\\\"\")")
        (if (= tName "Bool")
          (str "(str \":" fName " \" (if (.-" fName " r) \"true\" \"false\"))")
          (str "(str \":" fName " \" (int-to-string (.-" fName " r)))"))))))

(df deriveAsnCodec [(schema RecordSchema)] -> AsnCodec
  :d "Generates a monomorphic zero-cost ASN serializer and deserializer codec from schema."
  (let [(sName (.-name schema))
        (fields (.-fields schema))
        (fieldExprs (list-map (fn [(f FieldDef)] (buildAsnFieldExpr f)) fields))
        (joinedExprs (string-join fieldExprs " \" \" "))
        (encSrc (str "(df serialize" sName "ToAsn [(r " sName ")] -> Str\n"
                     "  :d \"Generated zero-cost monomorphic ASN serializer for " sName "\"\n"
                     "  (str \"(:" sName " \" " joinedExprs " \")\"))"))
        (decFieldLines (list-map (fn [(f FieldDef)] (str "    :" (.-name f) " (extractAsn" (.-typeName f) " asn \"" (.-name f) "\")")) fields))
        (decFieldsJoined (string-join decFieldLines "\n"))
        (decSrc (str "(df deserialize" sName "FromAsn [(asn Str)] -> " sName "\n"
                     "  :d \"Generated zero-cost monomorphic ASN deserializer for " sName "\"\n"
                     "  (" sName "\n" decFieldsJoined "))"))]
    (AsnCodec
      :status "ok"
      :schemaName sName
      :encoderSource encSrc
      :decoderSource decSrc)))

(df deriveRecordVisitor [(schema RecordSchema)] -> VisitorCode
  :d "Generates a monomorphic field visitor dispatch routine without reflection dictionaries."
  (let [(sName (.-name schema))
        (fields (.-fields schema))
        (fCount (list-length fields))
        (fNameList (list-map (fn [(f FieldDef)] (.-name f)) fields))
        (fNamesJoined (string-join fNameList ","))
        (visitLines (list-map
                      (fn [(f FieldDef)]
                        (str "    (visitor \"" (.-name f) "\" \"" (.-typeName f) "\" (.-" (.-name f) " r))"))
                      fields))
        (visitBodyJoined (string-join visitLines "\n"))
        (visSrc (str "(df visit" sName "Fields [(r " sName ") (visitor (fn [(Str Str Any)] -> Unit))] -> Unit\n"
                     "  :d \"Generated zero-cost monomorphic field visitor for " sName "\"\n"
                     "  (do\n" visitBodyJoined "))"))]
    (VisitorCode
      :status "ok"
      :schemaName sName
      :totalFields fCount
      :fieldNames fNamesJoined
      :visitorSource visSrc)))

(df deriveVariantCodec [(schema VariantSchema)] -> VariantCodec
  :d "Generates monomorphic pattern-matching codecs for sum types."
  (let [(vName (.-name schema))
        (cases (.-cases schema))
        (cCount (list-length cases))
        (cNameList (list-map (fn [(c VariantCaseDef)] (.-tagName c)) cases))
        (cNamesJoined (string-join cNameList ","))
        (encArms (list-map
                   (fn [(c VariantCaseDef)]
                     (let [(tag (.-tagName c))]
                       (mt (.-payloadType c)
                         ((some pType) (str "    ((" tag " payload) (str \"(:" tag " \" (serialize" pType " payload) \")\"))"))
                         ((none) (str "    ((" tag ") \"(:" tag ")\")")))))
                   cases))
        (encArmsJoined (string-join encArms "\n"))
        (encSrc (str "(df serialize" vName "ToAsn [(v " vName ")] -> Str\n"
                     "  :d \"Generated zero-cost monomorphic pattern-matching ASN serializer for " vName "\"\n"
                     "  (mt v\n" encArmsJoined "))"))
        (decArms (list-map
                   (fn [(c VariantCaseDef)]
                     (let [(tag (.-tagName c))]
                       (mt (.-payloadType c)
                         ((some pType) (str "    (if (string-starts-with? asn \"(:" tag " \") (" tag " (deserialize" pType " (extractPayload asn)))"))
                         ((none) (str "    (if (= asn \"(:" tag ")\") (" tag ")")))))
                   cases))
        (decArmsJoined (string-join decArms "\n"))
        (decSrc (str "(df deserialize" vName "FromAsn [(asn Str)] -> " vName "\n"
                     "  :d \"Generated zero-cost monomorphic ASN deserializer for " vName "\"\n"
                     decArmsJoined " (panic \"invalid variant tag\"))))))"))]
    (VariantCodec
      :status "ok"
      :schemaName vName
      :totalCases cCount
      :caseNames cNamesJoined
      :encoderSource encSrc
      :decoderSource decSrc)))

(df formatRecordToJson [(schema RecordSchema) (fieldVals (List (Pair Str Str)))] -> Str
  :d "Formats record key-value pairs into valid JSON string."
  (let [(pairs (list-map
                 (fn [(p (Pair Str Str))]
                   (let [(k (pair-first p))
                         (v (pair-second p))]
                     (if (or (= v "true") (or (= v "false") (or (= v "null") (string-starts-with? v "\""))))
                       (str "\"" k "\": " v)
                       (str "\"" k "\": " v))))
                 fieldVals))
        (joined (string-join pairs ", "))]
    (str "{" joined "}")))

(df formatRecordToAsn [(schema RecordSchema) (fieldVals (List (Pair Str Str)))] -> Str
  :d "Formats record key-value pairs into valid ASN S-expression string."
  (let [(pairs (list-map
                 (fn [(p (Pair Str Str))]
                   (let [(k (pair-first p))
                         (v (pair-second p))]
                     (str ":" k " " v)))
                 fieldVals))
        (joined (string-join pairs " "))]
    (str "(:" (.-name schema) " " joined ")")))

(df parseJsonToFieldPairs [(schema RecordSchema) (json Str)] -> (List (Pair Str Str))
  :d "Parses JSON string into field key-value pairs without runtime reflection."
  (let [(fields (.-fields schema))]
    (list-map
      (fn [(f FieldDef)]
        (let [(k (.-name f))
              (marker (str "\"" k "\":"))
              (posOpt (string-index-of json marker))
              (valStr (mt posOpt
                        ((none) "")
                        ((some pos)
                         (let [(rest (option-or (string-slice json (+ pos (string-length marker)) (string-length json)) ""))
                               (trimmed (string-trim rest))]
                           (if (string-starts-with? trimmed "\"")
                             (let [(afterQ (option-or (string-slice trimmed 1 (string-length trimmed)) ""))
                                   (qClose (option-or (string-index-of afterQ "\"") 0))]
                               (option-or (string-slice afterQ 0 qClose) ""))
                             (let [(stopComma (option-or (string-index-of trimmed ",") (string-length trimmed)))
                                   (stopBrace (option-or (string-index-of trimmed "}") (string-length trimmed)))
                                   (stopIdx (if (< stopComma stopBrace) stopComma stopBrace))]
                               (string-trim (option-or (string-slice trimmed 0 stopIdx) ""))))))))]
          (pair k valStr)))
      fields)))

(df parseAsnToFieldPairs [(schema RecordSchema) (asn Str)] -> (List (Pair Str Str))
  :d "Parses ASN S-expression text into field key-value pairs without runtime reflection."
  (let [(fields (.-fields schema))]
    (list-map
      (fn [(f FieldDef)]
        (let [(k (.-name f))
              (marker (str ":" k " "))
              (posOpt (string-index-of asn marker))
              (valStr (mt posOpt
                        ((none) "")
                        ((some pos)
                         (let [(rest (option-or (string-slice asn (+ pos (string-length marker)) (string-length asn)) ""))
                               (trimmed (string-trim rest))]
                           (if (string-starts-with? trimmed "\"")
                             (let [(afterQ (option-or (string-slice trimmed 1 (string-length trimmed)) ""))
                                   (qClose (option-or (string-index-of afterQ "\"") 0))]
                               (option-or (string-slice afterQ 0 qClose) ""))
                             (if (string-starts-with? trimmed "(")
                               (let [(pClose (option-or (string-index-of trimmed ")") (string-length trimmed)))]
                                 (option-or (string-slice trimmed 0 (+ pClose 1)) ""))
                               (let [(stopSpace (option-or (string-index-of trimmed " ") (string-length trimmed)))
                                     (stopParen (option-or (string-index-of trimmed ")") (string-length trimmed)))
                                     (stopIdx (if (< stopSpace stopParen) stopSpace stopParen))]
                                 (string-trim (option-or (string-slice trimmed 0 stopIdx) "")))))))))]
          (pair k valStr)))
      fields)))
