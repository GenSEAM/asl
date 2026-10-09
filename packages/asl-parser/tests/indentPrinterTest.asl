(module asl-parser/indentPrinterTest :x [runTests] :i [(indentPrinter :a ipr) (indentParser :a ip) (reader :a rd)])

fn testFormatFunction -> Bool
  (let [(fnAst (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "area") (rd/makeVect (list (rd/makeList (list (rd/makeAtom "s") (rd/makeAtom "Shape"))))) (rd/makeAtom "->") (rd/makeAtom "Float") (rd/makeList (list (rd/makeAtom "match") (rd/makeAtom "s") (rd/makeList (list (rd/makeList (list (rd/makeList (list (rd/makeAtom "Circle") (rd/makeAtom "r"))) (rd/makeList (list (rd/makeAtom "mul") (rd/makeAtom "pi") (rd/makeList (list (rd/makeAtom "mul") (rd/makeAtom "r") (rd/makeAtom "r"))))))))))))))] (let [(printed (ipr/formatIndented fnAst))] (assert (stringContains? printed "fn area s: Shape -> Float") "Must format fn header") (assert (stringContains? printed "match s") "Must format match statement") (assert (stringContains? printed "Circle r -> mul pi (mul r r)") "Must format match arm") true))

fn testFormatDotAccess -> Bool
  (let [(dotAst (rd/makeList (list (rd/makeAtom ".-email") (rd/makeList (list (rd/makeAtom ".-profile") (rd/makeAtom "user"))))))] (let [(printed (ipr/formatIndented dotAst))] (assert (= printed "user.profile.email") (str "Must format as user.profile.email: got " printed)) true))

fn testFormatInterpolatedString -> Bool
  (let [(strAst (rd/makeList (list (rd/makeAtom "str") (rd/makeAtom "\"Hello \"") (rd/makeAtom "name") (rd/makeAtom "\"!\""))))] (let [(printed (ipr/formatIndented strAst)) (reparsed (mt (ip/parseIndented (str printed "\n")) ((ok s) (rd/renderSexpr s)) ((err e) (str "parse error: " e))))] (do (refute (stringContains? printed "{name}") (str "a str call is not printed as a braced string, which the host reads as literal text: got " printed)) (assert (= reparsed (rd/renderSexpr strAst)) (str "a printed str call reads back as the same call: " printed " -> " reparsed)) true)))

fn testFormatInlineList -> Bool
  (let [(listAst (rd/makeList (list (rd/makeAtom "list") (rd/makeAtom "1") (rd/makeAtom "2") (rd/makeAtom "3"))))] (let [(printed (ipr/formatIndented listAst))] (assert (= printed "[1 2 3]") (str "Must format as inline list: got " printed)) true))

fn testFormatSchema -> Bool
  (let [(schemaAst (rd/makeList (list (rd/makeAtom "schema") (rd/makeAtom "Point") (rd/makeList (list (rd/makeAtom ":field") (rd/makeAtom "x") (rd/makeAtom "Int") (rd/makeAtom ""))) (rd/makeList (list (rd/makeAtom ":field") (rd/makeAtom "y") (rd/makeAtom "Int") (rd/makeAtom "\"ordinate\""))))))] (let [(printed (ipr/formatIndented schemaAst))] (assert (stringContains? printed "schema Point") "Must contain schema header") (assert (stringContains? printed "  x: Int") "Must contain field x") (assert (stringContains? printed "  y: Int \"ordinate\"") "Must contain field y with doc") (refute (stringContains? printed "defschema") "Must refute old defschema keyword") true))

fn testFormatEnum -> Bool
  (let [(enumAst (rd/makeList (list (rd/makeAtom "enum") (rd/makeAtom "Color") (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Red") (rd/makeVect (list)) (rd/makeAtom ""))) (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Green") (rd/makeVect (list)) (rd/makeAtom ""))) (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Blue") (rd/makeVect (list)) (rd/makeAtom ""))))))] (let [(printed (ipr/formatIndented enumAst))] (assert (stringContains? printed "enum Color") "Must contain enum header") (assert (stringContains? printed "  Red") "Must contain case Red") (assert (stringContains? printed "  Green") "Must contain case Green") (assert (stringContains? printed "  Blue") "Must contain case Blue") (refute (stringContains? printed "defenum") "Must refute old defenum keyword") true))

fn runTests -> Bool
  (do (assert (testFormatFunction) "testFormatFunction passed") (assert (testFormatDotAccess) "testFormatDotAccess passed") (assert (testFormatInterpolatedString) "testFormatInterpolatedString passed") (assert (testFormatInlineList) "testFormatInlineList passed") (assert (testFormatSchema) "testFormatSchema passed") (assert (testFormatEnum) "testFormatEnum passed") true)
