(module asl-syntax/tests/core/nodePredicatesTest :x [runTests] :i [(asl-syntax/core/tree :a tr) (asl-syntax/ts/types :a tt) (asl-syntax/jsx :a jx) (asl-syntax/js/lex :a jl)])

; (:m :ref COVBATCH3 :do "ts isTypeNode, jsx isJsxNode and js commentHasNewline? had no call path from any test")
fn nodeOf kind: String -> tr/Node
  (tr/makeNode kind 0 1 (list))

fn typeKinds -> (List String)
  (list "type" "keywordType" "literalType" "templateLiteralType" "typeRef" "typeArguments" "typeParameters" "typeAnnotation" "arrayType" "tupleType" "tupleElement" "restType" "functionType" "constructorType" "conditionalType" "mappedType" "typeLiteral" "unionType" "intersectionType" "typeOperator" "typeQuery" "inferType" "indexedAccessType" "parenType")

fn jsxKinds -> (List String)
  (list "jsxElement" "jsxFragment" "jsxOpeningElement" "jsxClosingElement" "jsxOpeningFragment" "jsxClosingFragment" "jsxAttribute" "jsxSpreadAttribute" "jsxSpreadChild" "jsxExpressionContainer" "jsxText" "jsxIdentifier" "jsxMemberExpr" "jsxNamespacedName" "jsxEmptyExpr")

fn comment src: String -> Bool
  (jl/commentHasNewline? (stringToBytes src) (tr/makeToken "comment" 0 (stringLength src)))

fn runTests -> Bool
  (do
    (assert (= (listLength (filter (fn [(k String)] -> Bool (tt/isTypeNode (nodeOf k))) (typeKinds))) 24) "every type node kind is a type node")
    (assert (not (tt/isTypeNode (nodeOf "identifier"))) "an expression kind is not a type node")
    (assert (not (tt/isTypeNode (nodeOf ""))) "an empty kind is not a type node")
    (assert (not (tt/isTypeNode (nodeOf "jsxElement"))) "a jsx kind is not a type node")
    (assert (not (tt/isTypeNode (nodeOf "TypeRef"))) "kinds are case sensitive")
    (assert (= (listLength (filter (fn [(k String)] -> Bool (jx/isJsxNode (nodeOf k))) (jsxKinds))) 15) "every jsx node kind is a jsx node")
    (assert (not (jx/isJsxNode (nodeOf "identifier"))) "an expression kind is not a jsx node")
    (assert (not (jx/isJsxNode (nodeOf ""))) "an empty kind is not a jsx node")
    (assert (not (jx/isJsxNode (nodeOf "unionType"))) "a type kind is not a jsx node")
    (assert (not (jx/isJsxNode (nodeOf "JsxElement"))) "kinds are case sensitive")
    (assert (comment "/* a\nb */") "a line feed inside the comment")
    (assert (comment "/* a\rb */") "a carriage return inside the comment")
    (assert (not (comment "/* ab */")) "a one-line comment")
    (assert (not (comment "")) "an empty token")
    (assert (not (jl/commentHasNewline? (stringToBytes "a\nb") (tr/makeToken "comment" 0 1))) "a newline outside the token range is ignored")
    (assert (jl/commentHasNewline? (stringToBytes "a\nb") (tr/makeToken "comment" 1 2)) "a newline at the first byte of the range counts")
    (assert (not (jl/commentHasNewline? (stringToBytes "a\nb") (tr/makeToken "comment" 2 3))) "a range after the newline does not")
    true)
