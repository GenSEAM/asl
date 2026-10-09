(module asl-target-rs/ast
  :x [RsType RsField RsStructDecl RsEnumCase RsEnumDecl RsParam RsFnDecl RsExpr RsFile makeRsType makeRsField makeRsStruct makeRsEnumCase makeRsEnum makeRsFn]
  :i [])

schema RsType
  name: String
  generics: (List RsType)
  isRef: Bool
  isMut: Bool

schema RsField
  name: String
  type: RsType
  isPub: Bool

schema RsStructDecl
  name: String
  fields: (List RsField)
  derives: (List String)
  isPub: Bool

schema RsEnumCase
  name: String
  payload: (List RsType)

schema RsEnumDecl
  name: String
  cases: (List RsEnumCase)
  derives: (List String)
  isPub: Bool

schema RsParam
  name: String
  type: RsType

enum RsExpr
  (rsLit val: String)
  (rsVar name: String)
  (rsBinOp op: String lhs: String rhs: String)
  (rsCall fnName: String args: (List String))
  (rsLet varName: String val: String)
  (rsIf cond: String thenBranch: String elseBranch: String)
  (rsMatch target: String arms: (List (Pair String String)))

schema RsFnDecl
  name: String
  params: (List RsParam)
  retType: RsType
  body: (List RsExpr)
  isPub: Bool

schema RsFile
  package: String
  imports: (List String)
  structs: (List RsStructDecl)
  enums: (List RsEnumDecl)
  functions: (List RsFnDecl)

fn makeRsType name: String generics: (List RsType) -> RsType
  (RsType :name name :generics generics :isRef false :isMut false)

fn makeRsField name: String type: RsType isPub: Bool -> RsField
  (RsField :name name :type type :isPub isPub)

fn makeRsStruct name: String fields: (List RsField) derives: (List String) isPub: Bool -> RsStructDecl
  (RsStructDecl :name name :fields fields :derives derives :isPub isPub)

fn makeRsEnumCase name: String payload: (List RsType) -> RsEnumCase
  (RsEnumCase :name name :payload payload)

fn makeRsEnum name: String cases: (List RsEnumCase) derives: (List String) isPub: Bool -> RsEnumDecl
  (RsEnumDecl :name name :cases cases :derives derives :isPub isPub)

fn makeRsFn name: String params: (List RsParam) retType: RsType body: (List RsExpr) isPub: Bool -> RsFnDecl
  (RsFnDecl :name name :params params :retType retType :body body :isPub isPub)
