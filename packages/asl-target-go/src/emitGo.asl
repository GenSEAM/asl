(module asl-target-go/emitGo
  :d "Standalone Go emitter backend for AgentScript."
  :x [emitGoType
      emitGoHeader
      emitGoFn
      emitGoStruct
      emitGoEnum
      emitGoProgram]
  :i [])

(df emitGoType [(ty Str)] -> Str
  :d "Maps AgentScript type to idiomatic Go type."
  (cond
    ((= ty "I64") "int64")
    ((= ty "Int") "int64")
    ((= ty "I32") "int32")
    ((= ty "Bool") "bool")
    ((= ty "Str") "string")
    ((= ty "F64") "float64")
    ((= ty "Float") "float64")
    ((= ty "Unit") "")
    (:else ty)))

(df emitGoHeader [(pkgName Str)] -> Str
  :d "Emits Go package declaration and standard imports."
  (str "package " pkgName "\n\nimport (\n\t\"fmt\"\n)\n\n"))

(df emitGoFn [(name Str) (params Str) (retTy Str) (body Str) (isExported Bool)] -> Str
  :d "Emits an idiomatic Go function declaration."
  (let [(fnName (if isExported (string-upper (option-or (string-slice name 0 1) "")) name))
        (finalName (if isExported (str fnName (option-or (string-slice name 1 (string-length name)) "")) name))
        (retClause (if (= retTy "") "" (str " " (emitGoType retTy))))]
    (str "func " finalName "(" params ")" retClause " {\n\t" body "\n}\n")))

(df emitGoStruct [(name Str) (fields Str)] -> Str
  :d "Emits a Go struct declaration with public fields."
  (str "type " name " struct {\n" fields "}\n"))

(df emitGoEnum [(name Str) (cases (List Str))] -> Str
  :d "Emits a Go type definition and const block for enum variants."
  (let [(hdr (str "type " name " int\n\nconst (\n"))
        (items (map (fn [(c Str)] -> Str (str "\t" name c " " name " = iota\n")) cases))
        (body (string-join items ""))
        (ftr ")\n")]
    (str hdr body ftr)))

(df emitGoProgram [(pkgName Str) (structs Str) (funcs Str)] -> Str
  :d "Assembles a complete Go package file from headers, structs, and functions."
  (let [(hdr (emitGoHeader pkgName))]
    (str hdr structs "\n" funcs)))
