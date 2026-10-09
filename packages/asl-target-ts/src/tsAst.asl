(module asl-target-ts/tsAst
  :x [TsType TsField TsInterfaceDecl TsTypeAliasDecl TsParam TsExpr TsFnDecl TsFile makeTsType makeTsField makeTsInterface makeTsTypeAlias makeTsParam makeTsFn makeTsFile]
  :i [])

schema TsType
  name: String
  generics: (List TsType)
  isArray: Bool
  isUnion: Bool
  unionMembers: (List TsType)

schema TsField
  name: String
  type: TsType
  isOptional: Bool
  isReadonly: Bool

schema TsInterfaceDecl
  name: String
  fields: (List TsField)
  isExported: Bool

schema TsTypeAliasDecl
  name: String
  type: TsType
  isExported: Bool

schema TsParam
  name: String
  type: TsType
  isOptional: Bool

enum TsExpr
  (tsLit val: String)
  (tsVar name: String)
  (tsMember target: String prop: String)
  (tsBinOp op: String lhs: String rhs: String)
  (tsCall fnName: String args: (List String))
  (tsLet varName: String val: String)
  (tsIf cond: String thenBranch: String elseBranch: String)
  (tsArray items: (List String))
  (tsObject fields: (List (Pair String String)))

schema TsFnDecl
  name: String
  params: (List TsParam)
  retType: TsType
  body: (List TsExpr)
  isExported: Bool
  isAsync: Bool

schema TsFile
  path: String
  imports: (List String)
  interfaces: (List TsInterfaceDecl)
  typeAliases: (List TsTypeAliasDecl)
  functions: (List TsFnDecl)

fn makeTsType name: String generics: (List TsType) -> TsType
  (TsType :name name :generics generics :isArray false :isUnion false :unionMembers (list))

fn makeTsField name: String type: TsType isOptional: Bool -> TsField
  (TsField :name name :type type :isOptional isOptional :isReadonly false)

fn makeTsInterface name: String fields: (List TsField) isExported: Bool -> TsInterfaceDecl
  (TsInterfaceDecl :name name :fields fields :isExported isExported)

fn makeTsTypeAlias name: String type: TsType isExported: Bool -> TsTypeAliasDecl
  (TsTypeAliasDecl :name name :type type :isExported isExported)

fn makeTsParam name: String type: TsType -> TsParam
  (TsParam :name name :type type :isOptional false)

fn makeTsFn name: String params: (List TsParam) retType: TsType body: (List TsExpr) isExported: Bool -> TsFnDecl
  (TsFnDecl :name name :params params :retType retType :body body :isExported isExported :isAsync false)

fn makeTsFile path: String -> TsFile
  (TsFile :path path :imports (list) :interfaces (list) :typeAliases (list) :functions (list))
