(module asl-syntax/tests/js/exprTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)])

fn testArithmeticAndPrecedence -> Bool
  (do
    (let [(code "1 + 2 * 3")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(+ 1 (* 2 3))") "precedence of * over + sexpr")
      (assert (= printed code) "precedence of * over + round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "precedence of * over + tiling"))
    (let [(code "1 * 2 + 3")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(+ (* 1 2) 3)") "precedence of * before + sexpr")
      (assert (= printed code) "precedence of * before + round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "precedence of * before + tiling"))
    (let [(code "1 + 2 + 3")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(+ (+ 1 2) 3)") "left associativity of + sexpr")
      (assert (= printed code) "left associativity of + round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "left associativity of + tiling"))
    (let [(code "1 * 2 / 3 % 4")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(% (/ (* 1 2) 3) 4)") "left associativity of * / % sexpr")
      (assert (= printed code) "left associativity of * / % round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "left associativity of * / % tiling"))
    (let [(code "10 - 4 - 2")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(- (- 10 4) 2)") "left associativity of - sexpr")
      (assert (= printed code) "left associativity of - round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "left associativity of - tiling"))
    (let [(code "2 + 3 * 4 + 5")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(+ (+ 2 (* 3 4)) 5)") "mixed + and * left associative sexpr")
      (assert (= printed code) "mixed + and * left associative round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "mixed + and * left associative tiling"))
    true)

fn testExponentiation -> Bool
  (do
    (let [(code "2 ** 3 ** 4")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(** 2 (** 3 4))") "right associativity of ** sexpr")
      (assert (= printed code) "right associativity of ** round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "right associativity of ** tiling"))
    (let [(code "2 * 3 ** 4")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(* 2 (** 3 4))") "precedence of ** over * sexpr")
      (assert (= printed code) "precedence of ** over * round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "precedence of ** over * tiling"))
    (let [(code "(2 ** 3) ** 4")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(** (** 2 3) 4)") "parentheses override ** right assoc sexpr")
      (assert (= printed code) "parentheses override ** right assoc round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "parentheses override ** right assoc tiling"))
    true)

fn testRelationalAndEquality -> Bool
  (do
    (let [(code "a < b == c > d")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(== (< a b) (> c d))") "relational binds tighter than equality sexpr")
      (assert (= printed code) "relational binds tighter than equality round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "relational binds tighter than equality tiling"))
    (let [(code "a === b !== c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(!== (=== a b) c)") "equality left associativity sexpr")
      (assert (= printed code) "equality left associativity round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "equality left associativity tiling"))
    (let [(code "x instanceof Y && a in b")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(&& (instanceof x Y) (in a b))") "instanceof and in bind tighter than && sexpr")
      (assert (= printed code) "instanceof and in bind tighter than && round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "instanceof and in bind tighter than && tiling"))
    (let [(code "a <= b != c >= d")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(!= (<= a b) (>= c d))") "<= and >= tighter than != sexpr")
      (assert (= printed code) "<= and >= tighter than != round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "<= and >= tighter than != tiling"))
    true)

fn testBitwiseAndShift -> Bool
  (do
    (let [(code "a | b ^ c & d")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(| a (^ b (& c d)))") "bitwise & > ^ > | sexpr")
      (assert (= printed code) "bitwise & > ^ > | round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "bitwise & > ^ > | tiling"))
    (let [(code "a << 2 + 1")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(<< a (+ 2 1))") "+ binds tighter than shift << sexpr")
      (assert (= printed code) "+ binds tighter than shift << round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "+ binds tighter than shift << tiling"))
    (let [(code "a >> 1 << 2")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(<< (>> a 1) 2)") "shift left associative sexpr")
      (assert (= printed code) "shift left associative round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "shift left associative tiling"))
    (let [(code "a >>> 2")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(>>> a 2)") "unsigned right shift sexpr")
      (assert (= printed code) "unsigned right shift round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "unsigned right shift tiling"))
    true)

fn testLogicalAndNullish -> Bool
  (do
    (let [(code "a || b && c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(|| a (&& b c))") "&& binds tighter than || sexpr")
      (assert (= printed code) "&& binds tighter than || round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "&& binds tighter than || tiling"))
    (let [(code "(a ?? b) || c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(|| (?? a b) c)") "parenthesized nullish with || sexpr")
      (assert (= printed code) "parenthesized nullish with || round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "parenthesized nullish with || tiling"))
    (let [(code "a && b || c && d")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(|| (&& a b) (&& c d))") "&& tighter than || on both sides sexpr")
      (assert (= printed code) "&& tighter than || on both sides round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "&& tighter than || on both sides tiling"))
    true)

fn testConditionalTernary -> Bool
  (do
    (let [(code "a ? b : c ? d : e")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(? a b (? c d e))") "ternary right associativity sexpr")
      (assert (= printed code) "ternary right associativity round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "ternary right associativity tiling"))
    (let [(code "a ? b ? c : d : e")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(? a (? b c d) e)") "nested ternary condition sexpr")
      (assert (= printed code) "nested ternary condition round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "nested ternary condition tiling"))
    (let [(code "x + 1 ? y * 2 : z - 3")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(? (+ x 1) (* y 2) (- z 3))") "arithmetic inside ternary sexpr")
      (assert (= printed code) "arithmetic inside ternary round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "arithmetic inside ternary tiling"))
    true)

fn testAssignmentOperators -> Bool
  (do
    (let [(code "a = b = c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(= a (= b c))") "assignment right associativity sexpr")
      (assert (= printed code) "assignment right associativity round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "assignment right associativity tiling"))
    (let [(code "a += b *= c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(+= a (*= b c))") "compound assignment right associativity sexpr")
      (assert (= printed code) "compound assignment right associativity round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "compound assignment right associativity tiling"))
    (let [(code "a = b + c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(= a (+ b c))") "assignment lower precedence than + sexpr")
      (assert (= printed code) "assignment lower precedence than + round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "assignment lower precedence than + tiling"))
    (let [(code "a = b ? c : d")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(= a (? b c d))") "assignment lower precedence than ternary sexpr")
      (assert (= printed code) "assignment lower precedence than ternary round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "assignment lower precedence than ternary tiling"))
    true)

fn testSequenceComma -> Bool
  (do
    (let [(code "a, b, c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(, (, a b) c)") "sequence left associativity sexpr")
      (assert (= printed code) "sequence left associativity round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "sequence left associativity tiling"))
    (let [(code "x = (1, 2)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(= x (, 1 2))") "sequence inside parentheses sexpr")
      (assert (= printed code) "sequence inside parentheses round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "sequence inside parentheses tiling"))
    true)

fn testUnaryAndUpdates -> Bool
  (do
    (let [(code "!a && b")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(&& (! a) b)") "prefix ! tighter than && sexpr")
      (assert (= printed code) "prefix ! tighter than && round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "prefix ! tighter than && tiling"))
    (let [(code "-a * b")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(* (- a) b)") "prefix - tighter than * sexpr")
      (assert (= printed code) "prefix - tighter than * round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "prefix - tighter than * tiling"))
    (let [(code "typeof x === \"string\"")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(=== (typeof x) \"string\")") "typeof tighter than === sexpr")
      (assert (= printed code) "typeof tighter than === round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "typeof tighter than === tiling"))
    (let [(code "void 0")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(void 0)") "void operator sexpr")
      (assert (= printed code) "void operator round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "void operator tiling"))
    (let [(code "delete obj.prop")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(delete (. obj prop))") "delete operator sexpr")
      (assert (= printed code) "delete operator round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "delete operator tiling"))
    (let [(code "++x * y")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(* (++ x) y)") "prefix ++ tighter than * sexpr")
      (assert (= printed code) "prefix ++ tighter than * round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "prefix ++ tighter than * tiling"))
    (let [(code "x++ * y")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(* (post++ x) y)") "postfix ++ tighter than * sexpr")
      (assert (= printed code) "postfix ++ tighter than * round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "postfix ++ tighter than * tiling"))
    (let [(code "!x++")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(! (post++ x))") "postfix ++ tighter than prefix ! sexpr")
      (assert (= printed code) "postfix ++ tighter than prefix ! round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "postfix ++ tighter than prefix ! tiling"))
    true)

fn testMemberAndCall -> Bool
  (do
    (let [(code "a.b.c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(. (. a b) c)") "chained member access sexpr")
      (assert (= printed code) "chained member access round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "chained member access tiling"))
    (let [(code "a[b][c]")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(index (index a b) c)") "chained bracket access sexpr")
      (assert (= printed code) "chained bracket access round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "chained bracket access tiling"))
    (let [(code "a.b(c)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(call (. a b) c)") "method call sexpr")
      (assert (= printed code) "method call round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "method call tiling"))
    (let [(code "a(b)(c)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(call (call a b) c)") "chained calls sexpr")
      (assert (= printed code) "chained calls round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "chained calls tiling"))
    (let [(code "a[b](c)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(call (index a b) c)") "call of indexed property sexpr")
      (assert (= printed code) "call of indexed property round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "call of indexed property tiling"))
    (let [(code "obj.#field")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(. obj #field)") "private identifier member access sexpr")
      (assert (= printed code) "private identifier member access round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "private identifier member access tiling"))
    true)

fn testNewExpressions -> Bool
  (do
    (let [(code "new a.b(c)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(new (. a b) c)") "new with arguments on member sexpr")
      (assert (= printed code) "new with arguments on member round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "new with arguments on member tiling"))
    (let [(code "new a().b")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(. (new a) b)") "member on new call sexpr")
      (assert (= printed code) "member on new call round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "member on new call tiling"))
    (let [(code "new Foo")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(new Foo)") "new without arguments sexpr")
      (assert (= printed code) "new without arguments round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "new without arguments tiling"))
    (let [(code "new.target")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "new.target") "meta property new.target sexpr")
      (assert (= printed code) "meta property new.target round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "meta property new.target tiling"))
    (let [(code "import.meta")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "import.meta") "meta property import.meta sexpr")
      (assert (= printed code) "meta property import.meta round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "meta property import.meta tiling"))
    true)

fn testOptionalChaining -> Bool
  (do
    (let [(code "a?.b")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(?. a b)") "optional property access sexpr")
      (assert (= printed code) "optional property access round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "optional property access tiling"))
    (let [(code "a?.[b]")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(?index a b)") "optional bracket access sexpr")
      (assert (= printed code) "optional bracket access round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "optional bracket access tiling"))
    (let [(code "a?.(b)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(?call a b)") "optional call sexpr")
      (assert (= printed code) "optional call round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "optional call tiling"))
    (let [(code "a?.b?.c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(?. (?. a b) c)") "chained optional property sexpr")
      (assert (= printed code) "chained optional property round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "chained optional property tiling"))
    (let [(code "a?.b.c")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(. (?. a b) c)") "dot access after optional chain sexpr")
      (assert (= printed code) "dot access after optional chain round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "dot access after optional chain tiling"))
    true)

fn testLiterals -> Bool
  (do
    (let [(code "42")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "42") "integer literal sexpr")
      (assert (= printed code) "integer literal round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "integer literal tiling"))
    (let [(code "3.14")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "3.14") "float literal sexpr")
      (assert (= printed code) "float literal round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "float literal tiling"))
    (let [(code "\"hello\"")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "\"hello\"") "string literal sexpr")
      (assert (= printed code) "string literal round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "string literal tiling"))
    (let [(code "true")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "true") "boolean true sexpr")
      (assert (= printed code) "boolean true round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "boolean true tiling"))
    (let [(code "false")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "false") "boolean false sexpr")
      (assert (= printed code) "boolean false round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "boolean false tiling"))
    (let [(code "null")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "null") "null literal sexpr")
      (assert (= printed code) "null literal round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "null literal tiling"))
    (let [(code "/abc/g")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "/abc/g") "regex literal sexpr")
      (assert (= printed code) "regex literal round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "regex literal tiling"))
    (let [(code "this")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "this") "this keyword sexpr")
      (assert (= printed code) "this keyword round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "this keyword tiling"))
    (let [(code "super")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "super") "super keyword sexpr")
      (assert (= printed code) "super keyword round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "super keyword tiling"))
    true)

fn testArrayAndObjectLiterals -> Bool
  (do
    (let [(code "[1, 2, 3]")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(array 1 2 3)") "array literal with elements sexpr")
      (assert (= printed code) "array literal with elements round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "array literal with elements tiling"))
    (let [(code "[]")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(array)") "empty array literal sexpr")
      (assert (= printed code) "empty array literal round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "empty array literal tiling"))
    (let [(code "[1, , 3]")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(array 1 3)") "array literal with hole sexpr")
      (assert (= printed code) "array literal with hole round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "array literal with hole tiling"))
    (let [(code "fn(...args)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(call fn (... args))") "call with spread argument sexpr")
      (assert (= printed code) "call with spread argument round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "call with spread argument tiling"))
    (let [(code "{ a: 1, b: 2 }")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(object (:prop a 1) (:prop b 2))") "object literal with properties sexpr")
      (assert (= printed code) "object literal with properties round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "object literal with properties tiling"))
    (let [(code "{ x, y }")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(object (:prop x x) (:prop y y))") "shorthand object properties sexpr")
      (assert (= printed code) "shorthand object properties round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "shorthand object properties tiling"))
    (let [(code "{ [k]: v }")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(object (:prop [k] v))") "computed property name sexpr")
      (assert (= printed code) "computed property name round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "computed property name tiling"))
    (let [(code "{ ...a, b: 2 }")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(object (... a) (:prop b 2))") "object spread property sexpr")
      (assert (= printed code) "object spread property round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "object spread property tiling"))
    true)

fn testTemplateLiterals -> Bool
  (do
    (let [(code "`hello`")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(template \"hello\")") "untagged template no sub sexpr")
      (assert (= printed code) "untagged template no sub round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "untagged template no sub tiling"))
    (let [(code "`hello ${name}!`")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(template \"hello \" name \"!\")") "template with substitution sexpr")
      (assert (= printed code) "template with substitution round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "template with substitution tiling"))
    (let [(code "tag`hello`")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(tagged tag (template \"hello\"))") "tagged template sexpr")
      (assert (= printed code) "tagged template round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "tagged template tiling"))
    true)

fn testMultilineAndComments -> Bool
  (do
    (let [(code "/* lead */\nfoo(\n  1 + 2, // comment\n  bar[index]\n)")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "(call foo (+ 1 2) (index bar index))") "multiline call with comments and indent sexpr")
      (assert (= printed code) "multiline call with comments and indent round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "multiline call with comments and indent tiling"))
    (let [(code "x\n++")
          (node (expr/parseExpr code))
          (sexpr (expr/exprToSExpr node code))
          (printed (pr/printTreeString code node))]
      (assert (= sexpr "x") "newline before ++ prevents postfix update sexpr")
      (assert (= printed code) "newline before ++ prevents postfix update round-trip")
      (assert (ok? (tr/checkTiling node (stringLength code))) "newline before ++ prevents postfix update tiling"))
    true)

fn checkParseError code: String expectedOffset: Int64 label: String -> Bool
  (let [(res (expr/parse code))]
    (mt res
      ((ok _) (do (assert false (str label " expected parse error, got ok")) false))
      ((err msg)
       (do
         (assert (stringContains? msg "syntax error") (str label " error message mentions syntax error"))
         (assert (stringContains? msg "offset") (str label " error message mentions offset"))
         (assert (stringContains? msg (stringFromInt64 expectedOffset)) (str label " error message contains expected offset"))
         true))))

fn testMalformedExpressions -> Bool
  (let [(c0 (checkParseError "(1 + 2" 0 "unclosed paren"))
        (c1 (checkParseError "   (x" 3 "unclosed paren with indent"))
        (c2 (checkParseError "[1, 2" 0 "unclosed bracket"))
        (c3 (checkParseError "arr[0" 3 "unclosed member bracket"))
        (c4 (checkParseError "{a: 1" 0 "unclosed brace"))
        (c5 (checkParseError "1 +" 2 "dangling plus"))
        (c6 (checkParseError "x * " 2 "dangling star"))
        (c7 (checkParseError "a?.1" 3 "questionDot followed by digit"))
        (c8 (checkParseError "foo?.0" 5 "questionDot followed by zero"))
        (c9 (checkParseError "new" 0 "new with no callee"))
        (c10 (checkParseError "new   " 0 "new with whitespace and no callee"))
        (c11 (checkParseError "`hello" 0 "unterminated template"))
        (c12 (checkParseError "`a${1}" 0 "unterminated template with substitution"))
        (c13 (checkParseError "1 = 2" 0 "assignment to number literal"))
        (c14 (checkParseError "\"str\" = 2" 0 "assignment to string literal"))
        (c15 (checkParseError "f(1, 2" 1 "unclosed call paren"))
        (c16 (checkParseError "a ? b" 2 "conditional missing colon"))
        (c17 (checkParseError "1 + 2)" 5 "unexpected trailing rparen"))
        (c18 (checkParseError "x =" 2 "dangling assignment"))
        (c19 (checkParseError "+" 0 "dangling prefix operator"))
        (c20 (checkParseError ")" 0 "unexpected token at start"))]
    (and c0 (and c1 (and c2 (and c3 (and c4 (and c5 (and c6 (and c7 (and c8 (and c9 (and c10 (and c11 (and c12 (and c13 (and c14 (and c15 (and c16 (and c17 (and c18 (and c19 c20)))))))))))))))))))))

fn checkCoverOp code: String expectedSExpr: String -> Bool
  (let [(res (cv/parse code))]
    (do
      (assert (ok? res) (str "cover parse ok: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (sexpr (cv/coverToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (assert (= sexpr expectedSExpr) (str "cover sexpr matches: " code))
          (assert (= printed code) (str "cover round-trip: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "cover tiling: " code))
          true))))

fn testCoverOperatorTokens -> Bool
  (do
    (assert (checkCoverOp "!a" "(! a)") "! in cover")
    (assert (checkCoverOp "a !== b" "(!== a b)") "!== in cover")
    (assert (checkCoverOp "a != b" "(!= a b)") "!= in cover")
    (assert (checkCoverOp "a <= b" "(<= a b)") "<= in cover")
    (assert (checkCoverOp "a >= b" "(>= a b)") ">= in cover")
    (assert (checkCoverOp "a << b" "(<< a b)") "<< in cover")
    (assert (checkCoverOp "a >> b" "(>> a b)") ">> in cover")
    (assert (checkCoverOp "a >>> b" "(>>> a b)") ">>> in cover")
    (assert (checkCoverOp "a <<= b" "(<<= a b)") "<<= in cover")
    (assert (checkCoverOp "a >>= b" "(>>= a b)") ">>= in cover")
    (assert (checkCoverOp "a >>>= b" "(>>>= a b)") ">>>= in cover")
    true)

fn checkFnExpr code: String expectedSExpr: String -> Bool
  (let [(res (expr/parse code))]
    (do
      (assert (ok? res) (str "expr parse ok: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (sexpr (expr/exprToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (assert (= sexpr expectedSExpr) (str "expr sexpr matches: " code))
          (assert (= printed code) (str "expr round-trip: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "expr tiling: " code))
          true))))

fn testFunctionExpressions -> Bool
  (do
    (assert (checkFnExpr "function() {}" "(function (params) (block))") "anonymous fn expr")
    (assert (checkFnExpr "function f(x) {}" "(function f (params x) (block))") "named fn expr")
    (assert (checkFnExpr "function*(x) {}" "(generator (params x) (block))") "generator fn expr")
    (assert (checkFnExpr "async function(x) {}" "(asyncFunction (params x) (block))") "async fn expr")
    (assert (checkFnExpr "async function*(x) {}" "(asyncGenerator (params x) (block))") "async generator fn expr")
    (assert (checkFnExpr "(function() {})()" "(call (function (params) (block)))") "IIFE")
    (assert (checkFnExpr "foo(function() {})" "(call foo (function (params) (block)))") "call arg fn expr")
    (assert (checkFnExpr "({ f: function() {} })" "(object (:prop f (function (params) (block))))") "obj prop fn expr")
    true)

fn runTests -> Bool
  (let [(r0 (testArithmeticAndPrecedence)) (r1 (testExponentiation)) (r2 (testRelationalAndEquality)) (r3 (testBitwiseAndShift)) (r4 (testLogicalAndNullish)) (r5 (testConditionalTernary)) (r6 (testAssignmentOperators)) (r7 (testSequenceComma)) (r8 (testUnaryAndUpdates)) (r9 (testMemberAndCall)) (r10 (testNewExpressions)) (r11 (testOptionalChaining)) (r12 (testLiterals)) (r13 (testArrayAndObjectLiterals)) (r14 (testTemplateLiterals)) (r15 (testMultilineAndComments)) (r16 (testMalformedExpressions)) (r17 (testCoverOperatorTokens)) (r18 (testFunctionExpressions))]
    (and r0 (and r1 (and r2 (and r3 (and r4 (and r5 (and r6 (and r7 (and r8 (and r9 (and r10 (and r11 (and r12 (and r13 (and r14 (and r15 (and r16 (and r17 r18)))))))))))))))))))
