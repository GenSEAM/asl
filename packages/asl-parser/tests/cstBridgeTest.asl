(module asl-parser/cstBridgeTest
  :x [runTests]
  :i [(asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)])

fn allKidsHaveOffsets? kids: (List ast/KidForm) -> Bool
  (fold (fn [(acc Bool) (k ast/KidForm)] -> Bool
          (and acc (and (> k.endOffset k.startOffset)
                        (>= k.startOffset 0))))
        true
        kids)

fn findEnumByName forms: (List ast/TopForm) name: String -> (Option ast/EnumNode)
  (fold (fn [(acc (Option ast/EnumNode)) (f ast/TopForm)] -> (Option ast/EnumNode)
          (mt acc
            ((some _) acc)
            ((none)
             (mt f
               ((ast/topEnum e) (if (= e.name name) (some e) (none)))
               (_ (none))))))
        (none)
        forms)

fn findSchemaByName forms: (List ast/TopForm) name: String -> (Option ast/SchemaNode)
  (fold (fn [(acc (Option ast/SchemaNode)) (f ast/TopForm)] -> (Option ast/SchemaNode)
          (mt acc
            ((some _) acc)
            ((none)
             (mt f
               ((ast/topSchema s) (if (= s.name name) (some s) (none)))
               (_ (none))))))
        (none)
        forms)

fn ! runTests -> Bool
  (let [(unterminatedSrc (str "fn f -> String\n  " "\"" "unterminated\n"))
        (unterminatedRes (ast/parse unterminatedSrc))
        (multilineSrc (str "fn f -> String\n  " "\"" "line1\nline2" "\"" "\n"))
        (multilineRes (ast/parse multilineSrc))
        (parenToks (lx/tokenize "(module foo :x [bar])\n(fn bar [] -> Int64 42)"))
        (kidFormsRes (ast/readKidForms parenToks))]
    (do
      (assert (mt unterminatedRes ((ok _) false) ((err _) true))
              "parseUnterminatedStringIndented rejected")
      (assert (mt multilineRes ((ok _) true) ((err _) false))
              "parseMultilineStringIndented accepted")
      (assert (mt kidFormsRes
                ((ok ks) (allKidsHaveOffsets? ks))
                ((err _) false))
              "KidForm has end offsets")
      (let [(regexPath "asl/packages/asl-regex/src/regex.asl")
            (regexRead (fileReadString regexPath))]
        (mt regexRead
          ((err e) (do (assert false (str regexPath " read error: " e)) false))
          ((ok regexSrc)
           (let [(regexRes (ast/parse regexSrc))]
             (mt regexRes
               ((err e) (do (assert false (str regexPath " parse error: " e.msg)) false))
               ((ok rForms)
                (do
                  (assert (= (listLength rForms) 65)
                          "regex.asl parses to 65 top forms")
                  (mt (findEnumByName rForms "Ast")
                    ((none) (do (assert false "regex.asl enum Ast not found") false))
                    ((some astEnum)
                     (do
                       (assert (= (listLength astEnum.cases) 9)
                               "regex.asl enum Ast has 9 cases")
                       (mt (listHead astEnum.cases)
                         ((none) (do (assert false "regex.asl enum Ast has no cases") false))
                         ((some c1)
                          (do (assert (= c1.name "astChar")
                                  "regex.asl enum Ast first case is astChar") true)))))))))))))
      (let [(yamlPath "asl/packages/asl-transpile/src/yamlTranspile.asl")
            (yamlRead (fileReadString yamlPath))]
        (mt yamlRead
          ((err e) (do (assert false (str yamlPath " read error: " e)) false))
          ((ok yamlSrc)
           (let [(yamlRes (ast/parse yamlSrc))]
             (mt yamlRes
               ((err e) (do (assert false (str yamlPath " parse error: " e.msg)) false))
               ((ok yForms)
                (do
                  (assert (= (listLength yForms) 25)
                          "yamlTranspile.asl parses to 25 top forms")
                  (mt (findEnumByName yForms "YamlLineKind")
                    ((none) (do (assert false "yamlTranspile.asl enum YamlLineKind not found") false))
                    ((some ylEnum)
                     (do
                       (assert (= (listLength ylEnum.cases) 6)
                               "yamlTranspile.asl enum YamlLineKind has 6 cases")
                       (mt (listHead ylEnum.cases)
                         ((none) (do (assert false "yamlTranspile.asl enum YamlLineKind has no cases") false))
                         ((some yc1)
                          (do (assert (= yc1.name "ylkBlank")
                                  "yamlTranspile.asl enum YamlLineKind first case is ylkBlank") true)))))))))))))
      (let [(surfPath "tests/acceptance/r1Host/reader/surfaceTest.asl")
            (surfRead (fileReadString surfPath))]
        (mt surfRead
          ((err e) (do (assert false (str surfPath " read error: " e)) false))
          ((ok surfSrc)
           (let [(surfRes (ast/parse surfSrc))]
             (mt surfRes
               ((err e) (do (assert false (str surfPath " parse error: " e.msg)) false))
               ((ok sForms)
                (do
                  (assert (= (listLength sForms) 8)
                          "surfaceTest.asl parses to 8 top forms")
                  (mt (findSchemaByName sForms "Pt")
                    ((none) (do (assert false "surfaceTest.asl schema Pt not found") false))
                    ((some ptSchema)
                     (do
                       (assert (= (listLength ptSchema.fields) 2)
                               "surfaceTest.asl schema Pt has 2 fields")
                       (mt (listHead ptSchema.fields)
                         ((none) (do (assert false "surfaceTest.asl schema Pt has no fields") false))
                         ((some f1)
                          (do (assert (= f1.name "x")
                                  "surfaceTest.asl schema Pt first field is x") true)))))))))))))
      true))
