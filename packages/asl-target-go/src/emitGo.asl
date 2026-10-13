(module asl-target-go/emitGo :x [emitGoType emitGoHeader emitGoFn emitGoStruct emitGoEnum emitGoProgram] :i [])

fn emitGoType ty: Str -> Str
  (cond ((= ty "I64") "int64") ((= ty "Int") "int64") ((= ty "I32") "int32") ((= ty "Bool") "bool") ((= ty "Str") "string") ((= ty "F64") "float64") ((= ty "Float") "float64") ((= ty "Unit") "") ((= ty "Bytes") "[]byte") ((= ty "List") "[]any") ((= ty "Map") "map[string]any") (else ty))

fn emitGoHeader pkgName: Str -> Str
  (str "package " pkgName "\n\nimport (\n\t\"fmt\"\n)\n\n")

fn emitGoFn name: Str params: Str retTy: Str body: Str isExported: Bool -> Str
  (let [(fnName (if isExported (stringUpper (optionOr (stringSlice name 0 1) "")) name)) (finalName (if isExported (str fnName (optionOr (stringSlice name 1 (stringLength name)) "")) name)) (retClause (if (= retTy "") "" (str " " (emitGoType retTy))))] (str "func " finalName "(" params ")" retClause " {\n\t" body "\n}\n"))

fn emitGoStruct name: Str fields: Str -> Str
  (str "type " name " struct {\n" fields "}\n")

fn emitGoEnum name: Str cases: (List Str) -> Str
  (let [(hdr (str "type " name " int\n\nconst (\n")) (items (map (fn [(c Str)] -> Str (str "\t" name c " " name " = iota\n")) cases)) (body (stringJoin items "")) (ftr ")\n")] (str hdr body ftr))

fn emitGoProgram pkgName: Str structs: Str funcs: Str -> Str
  (let [(hdr (emitGoHeader pkgName))] (str hdr structs "\n" funcs))
