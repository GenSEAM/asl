(module asl-forms/foreignBlock
  :x [ForeignVerdict foreignAliases checkForeignBlocks]
  :i [(asl-forms/check :a chk)
      (asl-syntax/asl/asn :a asn)])

(schema ForeignVerdict
  (:f language String)
  (:f status String)
  (:f message String))

fn blockTags -> (List String)
  (list "js" "py" "sh" "sql" "html" "css" "llvm" "c")

fn checkerPath language: String -> String
  (cond
    ((= language "js") "foreign.js")
    ((= language "css") "foreign.css")
    ((= language "html") "foreign.html")
    (else ""))

fn foreignAliases imports: (List (Pair String String)) -> (List String)
  (map (fn [(entry (Pair String String))] -> String (pairSecond entry))
       (filter (fn [(entry (Pair String String))] -> Bool (= (pairFirst entry) "asl-foreign/block")) imports))

fn skippedVerdict language: String -> ForeignVerdict
  (ForeignVerdict :language language :status "skipped" :message (str "no local checker for " language))

fn checkLiteral language: String body: String -> ForeignVerdict
  (let [(path (checkerPath language))]
    (if (stringEmpty? path)
      (skippedVerdict language)
      (let [(verdict (chk/foreignSyntax path body))]
        (ForeignVerdict :language language :status verdict.status :message verdict.message))))

fn checkCase aliases: (List String) name: String args: (List asn/AsnValue) -> (Option ForeignVerdict)
  (let [(parts (stringSplit name "/"))
        (language (optionOr (listGet parts 1) ""))]
    (if (and (= (listLength parts) 2)
             (and (listContains? aliases (optionOr (listHead parts) ""))
                  (listContains? (blockTags) language)))
      (mt (listGet args 0)
        ((some body)
         (mt (asn/asnStringValue body)
           ((some text) (some (checkLiteral language text)))
           ((none) (none))))
        ((none) (none)))
      (none)))

fn fieldsVerdicts aliases: (List String) fields: (List asn/AsnField) -> (List ForeignVerdict)
  (mt (listHead fields)
    ((some field)
     (listAppend (valueVerdicts aliases field.val)
                 (fieldsVerdicts aliases (optionOr (listTail fields) (list)))))
    ((none) (list)))

fn entriesVerdicts aliases: (List String) entries: (List asn/AsnEntry) -> (List ForeignVerdict)
  (mt (listHead entries)
    ((some entry)
     (listAppend (listAppend (valueVerdicts aliases entry.key) (valueVerdicts aliases entry.val))
                 (entriesVerdicts aliases (optionOr (listTail entries) (list)))))
    ((none) (list)))

fn valuesVerdicts aliases: (List String) values: (List asn/AsnValue) -> (List ForeignVerdict)
  (mt (listHead values)
    ((some value)
     (listAppend (valueVerdicts aliases value)
                 (valuesVerdicts aliases (optionOr (listTail values) (list)))))
    ((none) (list)))

fn valueVerdicts aliases: (List String) value: asn/AsnValue -> (List ForeignVerdict)
  (mt value
    ((asn/asnCase name args)
     (listAppend
       (mt (checkCase aliases name args)
         ((some verdict) (list verdict))
         ((none) (list)))
       (valuesVerdicts aliases args)))
    ((asn/asnVec values) (valuesVerdicts aliases values))
    ((asn/asnMap entries) (entriesVerdicts aliases entries))
    ((asn/asnRec fields) (fieldsVerdicts aliases fields))
    ((asn/asnCtor _ fields) (fieldsVerdicts aliases fields))
    ((asn/asnRows _ rows) (valuesVerdicts aliases rows))
    ((asn/asnTable columns rows) (listAppend (valuesVerdicts aliases columns) (valuesVerdicts aliases rows)))
    ((asn/asnPair key item) (listAppend (valueVerdicts aliases key) (valueVerdicts aliases item)))
    (_ (list)))

fn checkForeignBlocks imports: (List (Pair String String)) forms: (List asn/AsnValue) -> (List ForeignVerdict)
  (valuesVerdicts (foreignAliases imports) forms)
