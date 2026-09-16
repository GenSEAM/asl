(module asl-parser/indentPrinterTest
  :d "Falsifiable gate for pure ASL v0.4 Canonical Formatter (Item 2.1, Task T21_CANONICAL_FORMATTER_V04)."
  :x [runTests]
  :i [(indentPrinter :a ipr) (reader :a rd)])

(df testFormatFunction [] -> Bool
  :d "Verifies canonical indented printing of function definition and match arm."
  (let [(fnAst (rd/makeList (list (rd/makeAtom "df")
                                  (rd/makeAtom "area")
                                  (rd/makeVect (list (rd/makeList (list (rd/makeAtom "s") (rd/makeAtom "Shape")))))
                                  (rd/makeAtom "->")
                                  (rd/makeAtom "Float")
                                  (rd/makeList (list (rd/makeAtom "match")
                                                     (rd/makeAtom "s")
                                                     (rd/makeList (list (rd/makeList (list (rd/makeList (list (rd/makeAtom "Circle") (rd/makeAtom "r")))
                                                                                           (rd/makeList (list (rd/makeAtom "mul")
                                                                                                              (rd/makeAtom "pi")
                                                                                                              (rd/makeList (list (rd/makeAtom "mul")
                                                                                                                                 (rd/makeAtom "r")
                                                                                                                                 (rd/makeAtom "r"))))))))))))))]
    (let [(printed (ipr/formatIndented fnAst))]
      (assert (string-contains? printed "fn area s: Shape -> Float") "Must format fn header")
      (assert (string-contains? printed "match s") "Must format match statement")
      (assert (string-contains? printed "Circle r -> mul pi (mul r r)") "Must format match arm")
      true)))

(df testFormatDotAccess [] -> Bool
  :d "Verifies canonical formatting of (.-field target) into target.field."
  (let [(dotAst (rd/makeList (list (rd/makeAtom ".-email")
                                   (rd/makeList (list (rd/makeAtom ".-profile") (rd/makeAtom "user"))))))]
    (let [(printed (ipr/formatIndented dotAst))]
      (assert (= printed "user.profile.email") (str "Must format as user.profile.email: got " printed))
      true)))

(df testFormatInterpolatedString [] -> Bool
  :d "Verifies canonical formatting of (str ...) into \"...{expr}...\"."
  (let [(strAst (rd/makeList (list (rd/makeAtom "str")
                                   (rd/makeAtom "\"Hello \"")
                                   (rd/makeAtom "name")
                                   (rd/makeAtom "\"!\""))))]
    (let [(printed (ipr/formatIndented strAst))]
      (assert (= printed "\"Hello {name}!\"") (str "Must format as interpolated string: got " printed))
      true)))

(df testFormatInlineList [] -> Bool
  :d "Verifies canonical formatting of (list 1 2 3) into [1 2 3]."
  (let [(listAst (rd/makeList (list (rd/makeAtom "list")
                                    (rd/makeAtom "1")
                                    (rd/makeAtom "2")
                                    (rd/makeAtom "3"))))]
    (let [(printed (ipr/formatIndented listAst))]
      (assert (= printed "[1 2 3]") (str "Must format as inline list: got " printed))
      true)))

(df runTests [] -> Bool
  :d "Runs all canonical formatter tests."
  (assert (testFormatFunction) "testFormatFunction passed")
  (assert (testFormatDotAccess) "testFormatDotAccess passed")
  (assert (testFormatInterpolatedString) "testFormatInterpolatedString passed")
  (assert (testFormatInlineList) "testFormatInlineList passed")
  true)
