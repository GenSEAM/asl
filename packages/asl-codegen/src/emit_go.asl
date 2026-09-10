(module asl-codegen/emit-go
  :d "Idiomatic Go code generator for AgentScript cloud-native platform leaf."
  :x [emit-go-type
      emit-go-header
      emit-go-fn
      emit-go-struct
      emit-go-enum
      emit-go-program]
  :i [])

(df emit-go-type [(ty Str)] -> Str
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

(df emit-go-header [(pkg-name Str)] -> Str
  :d "Emits Go package declaration and standard imports."
  (str "package " pkg-name "\n\nimport (\n\t\"fmt\"\n)\n\n"))

(df emit-go-fn [(name Str) (params Str) (ret-ty Str) (body Str) (is-exported Bool)] -> Str
  :d "Emits an idiomatic Go function declaration."
  (let [(fn-name (if is-exported (string-upper (option-or (string-slice name 0 1) "")) name))
        (final-name (if is-exported (str fn-name (option-or (string-slice name 1 (string-length name)) "")) name))
        (ret-clause (if (= ret-ty "") "" (str " " (emit-go-type ret-ty))))]
    (str "func " final-name "(" params ")" ret-clause " {\n\t" body "\n}\n")))

(df emit-go-struct [(name Str) (fields Str)] -> Str
  :d "Emits a Go struct declaration with public fields."
  (str "type " name " struct {\n" fields "}\n"))

(df emit-go-enum [(name Str) (cases (List Str))] -> Str
  :d "Emits a Go type definition and const block for enum variants."
  (let [(hdr (str "type " name " int\n\nconst (\n"))
        (items (map (fn [(c Str)] -> Str (str "\t" name c " " name " = iota\n")) cases))
        (body (string-join items ""))
        (ftr ")\n")]
    (str hdr body ftr)))

(df emit-go-program [(pkg-name Str) (structs Str) (funcs Str)] -> Str
  :d "Assembles a complete Go package file from headers, structs, and functions."
  (let [(hdr (emit-go-header pkg-name))]
    (str hdr structs "\n" funcs)))
