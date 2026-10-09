(module asl-syntax/tests/ts/typesTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/ts/types :a ts)])

fn checkType! code: String expectedSExpr: String -> Bool
  (let [(res (ts/parseType code))]
    (do
      (assert (ok? res) (str "parseType succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (unwrapped (ts/unwrapTypeNode root))
            (sexpr (ts/typeToSExpr unwrapped code))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= sexpr expectedSExpr)
            (println (str "TYPE MISMATCH for " code "\n  GOT:      " sexpr "\n  EXPECTED: " expectedSExpr))
            ())
          (assert (= sexpr expectedSExpr) (str "type sexpr matches: " code))
          (do (if (!= printed code) (println (str "ROUNDTRIP MISMATCH: GOT [" printed "] EXPECTED [" code "]")) ())
          (assert (= printed code) (str "type round-trip exact: " code)))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "type tiling exact: " code))
          true))))

fn checkTypeErr code: String expectedOffset: Int64 -> Bool
  (let [(res (ts/parseType code))]
    (mt res
      ((ok _)
       (assert false (str "expected error for: " code)))
      ((err msg)
       (let [(expectedMsg (str "Parse error at offset " (stringFromInt64 expectedOffset)))]
         (do
           (assert (= msg expectedMsg) (str "parse error offset matches for: " code))
           true)))))

fn checkTsExpr! code: String expectedSExpr: String -> Bool
  (let [(res (ts/parseTs code))]
    (do
      (assert (ok? res) (str "parseTs succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (sexpr (ts/tsToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= sexpr expectedSExpr)
            (println (str "EXPR MISMATCH for " code "\n  GOT:      " sexpr "\n  EXPECTED: " expectedSExpr))
            ())
          (assert (= sexpr expectedSExpr) (str "expr sexpr matches: " code))
          (assert (= printed code) (str "expr round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "expr tiling exact: " code))
          true))))

fn checkTypeAnnotation! code: String expectedSExpr: String -> Bool
  (let [(tokens (lx/tokenize code))
        (res (ts/parseTypeAnnotation tokens code))
        (root res.node)]
    (do
      (assert (!= (tr/nodeKind root) "error") (str "parseTypeAnnotation succeeds: " code))
      (let [(sexpr (ts/typeToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= sexpr expectedSExpr)
            (println (str "ANNOT MISMATCH for " code "\n  GOT:      " sexpr "\n  EXPECTED: " expectedSExpr))
            ())
          (assert (= sexpr expectedSExpr) (str "annot sexpr matches: " code))
          (assert (= printed code) (str "annot round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "annot tiling exact: " code))
          true))))

fn checkTypeParameters! code: String expectedSExpr: String -> Bool
  (let [(tokens (lx/tokenize code))
        (res (ts/parseTypeParameters tokens code))
        (root res.node)]
    (do
      (assert (!= (tr/nodeKind root) "error") (str "parseTypeParameters succeeds: " code))
      (let [(sexpr (ts/typeToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= sexpr expectedSExpr)
            (println (str "TYPEPARAMS MISMATCH for " code "\n  GOT:      " sexpr "\n  EXPECTED: " expectedSExpr))
            ())
          (assert (= sexpr expectedSExpr) (str "typeParams sexpr matches: " code))
          (assert (= printed code) (str "typeParams round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "typeParams tiling exact: " code))
          true))))

fn testPrimitivesAndLiterals! -> Bool
  (do
    (assert (checkType! "string" "string") "primitive string")
    (assert (checkType! "number" "number") "primitive number")
    (assert (checkType! "boolean" "boolean") "primitive boolean")
    (assert (checkType! "any" "any") "primitive any")
    (assert (checkType! "unknown" "unknown") "primitive unknown")
    (assert (checkType! "void" "void") "primitive void")
    (assert (checkType! "never" "never") "primitive never")
    (assert (checkType! "undefined" "undefined") "primitive undefined")
    (assert (checkType! "null" "null") "primitive null")
    (assert (checkType! "bigint" "bigint") "primitive bigint")
    (assert (checkType! "symbol" "symbol") "primitive symbol")
    (assert (checkType! "object" "object") "primitive object")
    (assert (checkType! "\"hello\"" "\"hello\"") "literal string")
    (assert (checkType! "42" "42") "literal number")
    (assert (checkType! "true" "true") "literal true")
    (assert (checkType! "false" "false") "literal false")
    true)

fn testTypeReferences! -> Bool
  (do
    (assert (checkType! "T" "T") "simple type ref")
    (assert (checkType! "Array<T>" "(typeRef Array T)") "generic Array")
    (assert (checkType! "Promise<string>" "(typeRef Promise string)") "generic Promise")
    (assert (checkType! "Map<string, number>" "(typeRef Map string number)") "generic Map")
    (assert (checkType! "A.B.C<T>" "(typeRef A.B.C T)") "qualified generic")
    true)

fn testUnionsAndIntersections! -> Bool
  (do
    (assert (checkType! "string | number" "(| string number)") "union 2")
    (assert (checkType! "A | B | C" "(| A B C)") "union 3")
    (assert (checkType! "| A | B" "(| A B)") "leading pipe union")
    (assert (checkType! "A & B" "(& A B)") "intersection 2")
    (assert (checkType! "& A & B" "(& A B)") "leading amp intersection")
    (assert (checkType! "A | B & C" "(| A (& B C))") "intersection precedence")
    true)

fn testArraysAndTuples! -> Bool
  (do
    (assert (checkType! "number[]" "(arrayType number)") "array type")
    (assert (checkType! "string[][]" "(arrayType (arrayType string))") "nested array type")
    (assert (checkType! "T[K]" "(indexedAccess T K)") "indexed access")
    (assert (checkType! "[string, number]" "(tupleType string number)") "tuple 2")
    (assert (checkType! "[]" "(tupleType)") "empty tuple")
    (assert (checkType! "[x: string, y: number]" "(tupleType (elem x string) (elem y number))") "labeled tuple")
    (assert (checkType! "[x: string, y?: number]" "(tupleType (elem x string) (elem y? number))") "optional labeled tuple")
    (assert (checkType! "[string, ...number[]]" "(tupleType string (... (arrayType number)))") "rest tuple")
    (assert (checkType! "[...T]" "(tupleType (... T))") "rest type param tuple")
    (assert (checkType! "readonly [string, number]" "(readonly (tupleType string number))") "readonly tuple")
    (assert (checkType! "[string, ...number[], boolean]" "(tupleType string (... (arrayType number)) boolean)") "tuple rest middle")
    true)

fn testFunctionAndConstructorTypes! -> Bool
  (do
    (assert (checkType! "() => void" "(fnType (params) void)") "fn zero params")
    (assert (checkType! "(x: number, y: string) => boolean" "(fnType (params (param x number) (param y string)) boolean)") "fn two params")
    (assert (checkType! "(x: number, y?: string) => boolean" "(fnType (params (param x number) (param y? string)) boolean)") "fn optional param")
    (assert (checkType! "(...args: any[]) => void" "(fnType (params (... (param args (arrayType any)))) void)") "fn rest param")
    (assert (checkType! "new (x: string) => Foo" "(ctorType (params (param x string)) Foo)") "constructor type")
    true)

fn testConditionalTypes! -> Bool
  (do
    (assert (checkType! "T extends U ? X : Y" "(? (extends T U) X Y)") "conditional type simple")
    (assert (checkType! "T extends string ? true : false" "(? (extends T string) true false)") "conditional boolean")
    (assert (checkType! "T extends string ? 1 : T extends number ? 2 : 3" "(? (extends T string) 1 (? (extends T number) 2 3))") "conditional chained")
    (assert (checkType! "T extends Promise<infer R> ? R : T" "(? (extends T (typeRef Promise (infer R))) R T)") "conditional infer")
    true)

fn testMappedTypes! -> Bool
  (do
    (assert (checkType! "{[K in keyof T]: T[K]}" "(mappedType K (in (keyof T)) (indexedAccess T K))") "mapped simple")
    (assert (checkType! "{[K in keyof T]?: T[K]}" "(mappedType K (in (keyof T)) ? (indexedAccess T K))") "mapped optional")
    (assert (checkType! "{-readonly [K in keyof T]+?: T[K]}" "(mappedType -readonly K (in (keyof T)) +? (indexedAccess T K))") "mapped modifiers")
    (assert (checkType! "{[K in keyof T as NewKey]: T[K]}" "(mappedType K (in (keyof T)) (as NewKey) (indexedAccess T K))") "mapped as remapping")
    (assert (checkType! "{[K in keyof T as Capitalize<string & K>]: T[K]}" "(mappedType K (in (keyof T)) (as (typeRef Capitalize (& string K))) (indexedAccess T K))") "mapped key remapping")
    true)

fn testTemplateLiteralTypes! -> Bool
  (do
    (assert (checkType! "`head_${T}_tail`" "(templateType T)") "template literal type")
    (assert (checkType! "`a_${T}_b_${U}_c`" "(templateType T U)") "template multiple params")
    true)

fn testTypeQueriesAndOperators! -> Bool
  (do
    (assert (checkType! "typeof x" "(typeof x)") "type query simple")
    (assert (checkType! "keyof T" "(keyof T)") "keyof operator")
    (assert (checkType! "infer U" "(infer U)") "infer simple")
    (assert (checkType! "infer U extends string" "(infer U (extends string))") "infer with constraint")
    true)

fn testTypeLiterals! -> Bool
  (do
    (assert (checkType! "{ a: string; b: number }" "(typeLiteral (prop a string) (prop b number))") "type literal semi")
    (assert (checkType! "{ a: string, b: number }" "(typeLiteral (prop a string) (prop b number))") "type literal comma")
    (assert (checkType! "{ [k: string]: any }" "(typeLiteral (index [k string] any))") "index signature")
    true)

fn testTsExpressions! -> Bool
  (do
    (assert (checkTsExpr! "x as number" "(as x number)") "as expression")
    (assert (checkTsExpr! "x + y as number" "(as (+ x y) number)") "as with add")
    (assert (checkTsExpr! "x as number == y" "(== (as x number) y)") "as with equality")
    (assert (checkTsExpr! "y == x as number" "(== y (as x number))") "as on right of comparison")
    (assert (checkTsExpr! "x satisfies string" "(satisfies x string)") "satisfies expression")
    (assert (checkTsExpr! "y == x satisfies number" "(== y (satisfies x number))") "satisfies on right of comparison")
    (assert (checkTsExpr! "a + b as T" "(as (+ a b) T)") "as with lower precedence than plus")
    (assert (checkTsExpr! "a + b satisfies T" "(satisfies (+ a b) T)") "satisfies with lower precedence than plus")
    (assert (checkTsExpr! "x!" "(! x)") "non-null simple")
    (assert (checkTsExpr! "x!.y" "(. (! x) y)") "non-null member")
    (assert (checkTsExpr! "x!()" "(call (! x))") "non-null call")
    (assert (checkTsExpr! "<number>x" "(typeAssert number x)") "angle type assertion")
    (assert (checkTsExpr! "x as T satisfies U" "(satisfies (as x T) U)") "as satisfies chained")
    true)

fn testGenericCallDisambiguation! -> Bool
  (do
    (assert (checkTsExpr! "f<T>(x)" "(call (typeArgs T) f x)") "generic call f<T>(x)")
    (assert (checkTsExpr! "a < b > c" "(> (< a b) c)") "comparison a < b > c")
    (assert (checkTsExpr! "f<T, U>(x, y)" "(call (typeArgs T U) f x y)") "generic call f<T, U>(x, y)")
    (assert (checkTsExpr! "f<T>()" "(call (typeArgs T) f)") "generic call f<T>()")
    (assert (checkTsExpr! "obj.method<T>(x)" "(call (typeArgs T) (. obj method) x)") "method generic call")
    (assert (checkTsExpr! "a < b, c > d" "(, (< a b) (> c d))") "comparison a < b, c > d")
    (assert (checkTsExpr! "a < b && c > d" "(&& (< a b) (> c d))") "comparison a < b && c > d")
    (assert (checkTsExpr! "1 + f<T>(x)" "(+ 1 (call (typeArgs T) f x))") "add generic call")
    true)

fn testTypeAnnotationsAndParameters! -> Bool
  (do
    (assert (checkTypeAnnotation! ": string" "(: string)") "annot string")
    (assert (checkTypeAnnotation! ": number[]" "(: (arrayType number))") "annot array")
    (assert (checkTypeAnnotation! ": (x: number) => void" "(: (fnType (params (param x number)) void))") "annot fn")
    (assert (checkTypeParameters! "<T>" "(typeParams T)") "typeParams single")
    (assert (checkTypeParameters! "<T, U>" "(typeParams T U)") "typeParams multi")
    (assert (checkTypeParameters! "<T extends string>" "(typeParams (extends T string))") "typeParams extends")
    (assert (checkTypeParameters! "<T = number>" "(typeParams (= T number))") "typeParams default")
    (assert (checkTypeParameters! "<T extends Record<string, any> = {}>" "(typeParams (= (extends T (typeRef Record string any)) (typeLiteral)))") "typeParams both")
    true)

fn testMalformedTypes -> Bool
  (do
    (assert (checkTypeErr "Promise<string" 14) "unclosed type arguments")
    (assert (checkTypeErr "(string" 7) "unclosed paren type")
    (assert (checkTypeErr "[string" 7) "unclosed tuple type")
    (assert (checkTypeErr "[string, number" 15) "unclosed tuple type multi")
    (assert (checkTypeErr "string |" 8) "dangling union pipe")
    (assert (checkTypeErr "string &" 8) "dangling intersection amp")
    (assert (checkTypeErr "T extends U : X" 11) "conditional missing question")
    (assert (checkTypeErr "T extends U ? X" 15) "conditional missing colon")
    (assert (checkTypeErr "{[K in keyof T: string}" 14) "mapped type missing close bracket")
    (assert (checkTypeErr "{ [K in keyof T: number }" 15) "mapped type missing bracket with space")
    (assert (checkTypeErr "T extends" 9) "extends with no type at eof")
    (assert (checkTypeErr "T extends ? X : Y" 10) "extends with question")
    (assert (checkTypeErr "`hello" 6) "unterminated template literal no sub")
    (assert (checkTypeErr "`head_${T}" 10) "unterminated template literal with sub")
    true)

fn ! runTests -> Bool
  (do
    (assert (testMalformedTypes) "malformed types")
    (assert (testPrimitivesAndLiterals!) "primitives and literals")
    (assert (testTypeReferences!) "type references")
    (assert (testUnionsAndIntersections!) "unions and intersections")
    (assert (testArraysAndTuples!) "arrays and tuples")
    (assert (testFunctionAndConstructorTypes!) "function and constructor types")
    (assert (testConditionalTypes!) "conditional types")
    (assert (testMappedTypes!) "mapped types")
    (assert (testTemplateLiteralTypes!) "template literal types")
    (assert (testTypeQueriesAndOperators!) "type queries and operators")
    (assert (testTypeLiterals!) "type literals")
    (assert (testTsExpressions!) "ts expressions")
    (assert (testGenericCallDisambiguation!) "generic call disambiguation")
    (assert (testTypeAnnotationsAndParameters!) "type annotations and parameters")
    true)
