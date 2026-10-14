(module asl-target-ts/tests/emitTsTest
  :x [testTypeMapping testMangleIdent testSchemaEmission testEnumEmission testDefunEmission testFullModuleEmission runTests]
  :i [(asl-target-ts/types :a ty)
      (asl-target-ts/emitTs :a em)
      (asl-parser/ast :a a)
      (asl-parser/reader :a rd)])

fn testTypeMapping -> Bool
  (do
    (assert (= (ty/emitTsType "Int64") "bigint") "Int64 maps to bigint")
    (assert (= (ty/emitTsType "Float64") "number") "Float64 maps to number")
    (assert (= (ty/emitTsType "String") "string") "String maps to string")
    (assert (= (ty/emitTsType "Bool") "boolean") "Bool maps to boolean")
    (assert (= (ty/emitTsType "Unit") "void") "Unit maps to void")
    (assert (= (ty/emitTsType "(List Str)") "Array<string>") "(List Str) maps to Array<string>")
    (assert (= (ty/emitTsType "(Option Int64)") "bigint | null") "(Option Int64) maps to bigint | null")
    (assert (stringContains? (ty/emitTsType "(Result Unit Str)") "ok: true") "Result ok branch")
    (assert (stringContains? (ty/emitTsType "(Result Unit Str)") "ok: false") "Result err branch")
    true)

fn testMangleIdent -> Bool
  (do
    (assert (= (ty/tsMangleIdent "user-id") "userId") "kebab-case converts to camelCase")
    (assert (= (ty/tsMangleIdent "is-valid?") "isValid") "predicate trailing question mark removed")
    (assert (= (ty/tsMangleIdent "delete") "delete_") "JS keyword delete mangled to delete_")
    (assert (= (ty/tsMangleIdent "class") "class_") "JS keyword class mangled to class_")
    (assert (= (ty/tsMangleIdent "function") "function_") "JS keyword function mangled to function_")
    true)

fn testSchemaEmission -> Bool
  (let [(f1 (a/AstField :name "id" :type "Int64" :docstring "" :default (none) :json (none)))
        (f2 (a/AstField :name "username" :type "Str" :docstring "" :default (none) :json (none)))
        (sch (a/SchemaNode :name "UserProfile" :typeVars (list) :fields (list f1 f2) :jsonCase (none)))
        (code (em/emitTsSchema sch))]
    (do
      (assert (stringContains? code "export interface UserProfile") "interface declaration")
      (assert (stringContains? code "id: bigint;") "field id typed bigint")
      (assert (stringContains? code "username: string;") "field username typed string")
      true))

fn testEnumEmission -> Bool
  (let [(c1 (a/EnumCase :name "circle" :fields (list (a/Param :name "radius" :type "Float64")) :docstring ""))
        (c2 (a/EnumCase :name "square" :fields (list (a/Param :name "side" :type "Float64")) :docstring ""))
        (enm (a/EnumNode :name "Shape" :typeVars (list) :cases (list c1 c2)))
        (code (em/emitTsEnum enm))]
    (do
      (assert (stringContains? code "export type Shape =") "enum union type")
      (assert (stringContains? code "tag: \"circle\"") "variant circle tag")
      (assert (stringContains? code "radius: number") "variant circle payload")
      (assert (stringContains? code "tag: \"square\"") "variant square tag")
      (assert (stringContains? code "export function makeShapeCircle") "constructor makeShapeCircle")
      (assert (stringContains? code "export function makeShapeSquare") "constructor makeShapeSquare")
      true))

fn testDefunEmission -> Bool
  (let [(p1 (a/Param :name "a" :type "Int64"))
        (p2 (a/Param :name "b" :type "Int64"))
        (bodyExpr (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "a") (rd/sexprAtom "b"))))
        (fnNode (a/DefunNode :name "add-numbers" :typeVars (list) :isExported true :effect false :params (list p1 p2) :retType "Int64" :docstring "" :body (list bodyExpr)))
        (code (em/emitTsDefun fnNode))]
    (do
      (assert (stringContains? code "export function addNumbers(a: bigint, b: bigint): bigint") "function signature")
      (assert (stringContains? code "return (a + b);") "binary addition expression")
      true))

fn testElseKeywordNotWildcard -> Bool
  (let [(elseArm (rd/sexprList (list (rd/sexprAtom ":else") (rd/sexprAtom "1"))))
        (bareArm (rd/sexprList (list (rd/sexprAtom "else") (rd/sexprAtom "1"))))
        (elseExpr (rd/sexprList (list (rd/sexprAtom "mt") (rd/sexprAtom "x") elseArm)))
        (bareExpr (rd/sexprList (list (rd/sexprAtom "mt") (rd/sexprAtom "x") bareArm)))
        (elseCode (em/emitTsExpr (list) elseExpr))
        (bareCode (em/emitTsExpr (list) bareExpr))]
    (do
      (assert (stringContains? bareCode "1") "bare else arm still reaches its body")
      (assert (not (= elseCode bareCode)) "ASL1-elseKeywordPatternParity: (:else ...) must not emit the same unconditional wildcard shortcut as bare else/_")
      true))

fn testFullModuleEmission -> Bool
  (let [(p1 (a/Param :name "msg" :type "Str"))
        (bodyExpr (rd/sexprList (list (rd/sexprAtom "println") (rd/sexprAtom "msg"))))
        (fnNode (a/DefunNode :name "greet" :typeVars (list) :isExported true :effect false :params (list p1) :retType "Unit" :docstring "" :body (list bodyExpr)))
        (forms (list (a/topDefun fnNode)))
        (code (em/emitTsModule forms))]
    (do
      (assert (stringContains? code "Generated by AgentSlang (ASL) TypeScript Target") "header banner")
      (assert (stringContains? code "export function aslFloorDiv") "runtime helpers included")
      (assert (stringContains? code "export function greet(msg: string): void") "greet function emitted")
      (assert (stringContains? code "console.log(msg)") "println lowered to console.log")
      true))

fn runTests -> Bool
  (do
    (assert (testTypeMapping) "testTypeMapping")
    (assert (testMangleIdent) "testMangleIdent")
    (assert (testSchemaEmission) "testSchemaEmission")
    (assert (testEnumEmission) "testEnumEmission")
    (assert (testDefunEmission) "testDefunEmission")
    (assert (testElseKeywordNotWildcard) "testElseKeywordNotWildcard")
    (assert (testFullModuleEmission) "testFullModuleEmission")
    true)
