(module asl-syntax/tests/asl/fromJsonTest
  :x [runTests]
  :i [(asl-syntax/asl/fromJson :a fj)
      (asl-parser/ast :a a)
      (asl-parser/astConverter :a cv)
      (asl-parser/astPrinter :a ap)
      (asl-parser/reader :a rd)
      (asl-json/json :a j)
      (asl-syntax/asl/astSchema :a asch)])

fn hasDigit? s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (or acc (stringContains? "0123456789" c))) false (stringChars s))

fn isFloatAtom? s: String -> Bool
  (and (hasDigit? s) (stringContains? s "."))

fn floatAtomsEquivalent? a: String b: String -> Bool
  (let [(fa (stringToFloat64 a)) (fb (stringToFloat64 b))]
    (or (= a b) (and (some? fa) (= fa fb))))

fn atomEquivalent? a: String b: String -> Bool
  (or (= a b)
      (and (isFloatAtom? a) (and (isFloatAtom? b) (floatAtomsEquivalent? a b))))

fn itemsEquivalent? xs: (List rd/SExpr) ys: (List rd/SExpr) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (fold (fn [(acc Bool) (p (Pair rd/SExpr rd/SExpr))] -> Bool
            (and acc (sexprEquivalent? (pairFirst p) (pairSecond p))))
          true (zip xs ys)))

fn dropListHead items: (List rd/SExpr) -> (Option (List rd/SExpr))
  (mt (listHead items)
    ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) "list")) (some (optionOr (listTail items) (list))) (none)))
    ((none) (none)))

fn vectListEquivalent? vItems: (List rd/SExpr) lItems: (List rd/SExpr) -> Bool
  (mt (dropListHead lItems)
    ((some rest) (itemsEquivalent? vItems rest))
    ((none) false))

fn sexprEquivalent? x: rd/SExpr y: rd/SExpr -> Bool
  (mt x
    ((rd/sexprAtom vx)
     (mt y
       ((rd/sexprAtom vy) (atomEquivalent? vx vy))
       (_ false)))
    ((rd/sexprList lx)
     (mt y
       ((rd/sexprList ly) (itemsEquivalent? lx ly))
       ((rd/sexprVect vy) (vectListEquivalent? vy lx))
       (_ false)))
    ((rd/sexprVect vx)
     (mt y
       ((rd/sexprVect vy) (itemsEquivalent? vx vy))
       ((rd/sexprList ly) (vectListEquivalent? vx ly))
       (_ false))))

fn topFormEffectEquivalent? x: a/TopForm y: a/TopForm -> Bool
  (mt x
    ((a/topDefun dx) (mt y ((a/topDefun dy) (= dx.effect dy.effect)) (_ false)))
    ((a/topModule mx) (mt y ((a/topModule my) (topFormsEffectsEquivalent? mx.defs my.defs)) (_ false)))
    (_ true))

fn topFormsEffectsEquivalent? xs: (List a/TopForm) ys: (List a/TopForm) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (fold (fn [(acc Bool) (p (Pair a/TopForm a/TopForm))] -> Bool
            (and acc (topFormEffectEquivalent? (pairFirst p) (pairSecond p))))
          true (zip xs ys)))

fn topFormsEquivalent? xs: (List a/TopForm) ys: (List a/TopForm) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (and (topFormsEffectsEquivalent? xs ys)
         (fold (fn [(acc Bool) (p (Pair a/TopForm a/TopForm))] -> Bool
                 (and acc (sexprEquivalent? (cv/topFormToSexpr (pairFirst p)) (cv/topFormToSexpr (pairSecond p)))))
               true (zip xs ys))))

fn loadAstSchema! -> (Result j/Json String)
  (mt (fileRead "asl/grammar/aslAst.schema.json")
    ((err e) (err (str "Failed reading aslAst.schema.json: " e)))
    ((ok text)
     (mt (j/jsonParse text)
       ((err e) (err (str "Failed parsing aslAst.schema.json: " e)))
       ((ok root) (ok root)))))

fn validateTopFormJson! j: j/Json -> (Result Bool String)
  (mt (loadAstSchema!)
    ((err e) (err e))
    ((ok root) (asch/validateTopFormWithSchema root j)))

fn testLiteralsRoundtrip! -> Bool
  (let [(lInt (a/litInt 42))
        (lFloat (a/litFloat 3.14))
        (lStr (a/litString "hello world"))
        (lBool (a/litBool true))
        (lUnit (a/litUnit))
        (jInt (fj/litToJson lInt))
        (jFloat (fj/litToJson lFloat))
        (jStr (fj/litToJson lStr))
        (jBool (fj/litToJson lBool))
        (jUnit (fj/litToJson lUnit))]
    (do
      (assert (ok? (fj/parseAstLit jInt)) "parseAstLit int succeeds")
      (assert (ok? (fj/parseAstLit jFloat)) "parseAstLit float succeeds")
      (assert (ok? (fj/parseAstLit jStr)) "parseAstLit string succeeds")
      (assert (ok? (fj/parseAstLit jBool)) "parseAstLit bool succeeds")
      (assert (ok? (fj/parseAstLit jUnit)) "parseAstLit unit succeeds")
      (let [(vLit (validateTopFormJson! (fj/topFormToJson (a/topDefun (a/DefunNode :name "valFn" :typeVars (list) :isExported false :effect false :params (list) :retType "Int64" :docstring "" :body (list (cv/lower (a/exprLit lInt))) :bodyPos (list))))))]
        (assert (mt vLit ((ok b) b) ((err _) false)) (str "defun with literal satisfies schema topForm shape: " (mt vLit ((ok _) "ok") ((err e) e)))))
      true))

fn testExpressionsRoundtrip -> Bool
  (let [(eIdent (a/exprIdent "myVar"))
        (eCall (a/exprCall (a/exprIdent "+") (list (a/exprIdent "a") (a/exprLit (a/litInt 10)))))
        (eMember (a/exprMember (a/exprIdent "user") "name"))
        (eLet (a/exprLet (list (pair (a/patVar "x") (a/exprLit (a/litInt 1)))) (list (a/exprIdent "x"))))
        (eIf (a/exprIf (a/exprIdent "cond") (a/exprLit (a/litInt 1)) (a/exprLit (a/litInt 2))))
        (eMatch (a/exprMatch (a/exprIdent "opt") (list (a/matchArm (a/patCtor "some" (some (a/patVar "v"))) (a/exprIdent "v")) (a/matchArm (a/patCtor "none" (none)) (a/exprLit (a/litInt 0))))))
        (eTry (a/exprTry (a/exprCall (a/exprIdent "fetch") (list))))
        (eBlock (a/exprBlock (list (a/exprLit (a/litInt 1)) (a/exprLit (a/litInt 2)))))
        (eCond (a/exprCond (list (pair (a/exprIdent "a") (list (a/exprLit (a/litInt 1)))) (pair (a/exprIdent "else") (list (a/exprLit (a/litInt 2)))))))
        (eLambda (a/exprLambda (list (a/Param :name "x" :type "Int64")) (some "Int64") (list (a/exprCall (a/exprIdent "+") (list (a/exprIdent "x") (a/exprLit (a/litInt 1))))) (rd/makeList (list))))
        (jIdent (fj/exprToJson eIdent))
        (jCall (fj/exprToJson eCall))
        (jMember (fj/exprToJson eMember))
        (jLet (fj/exprToJson eLet))
        (jIf (fj/exprToJson eIf))
        (jMatch (fj/exprToJson eMatch))
        (jTry (fj/exprToJson eTry))
        (jBlock (fj/exprToJson eBlock))
        (jCond (fj/exprToJson eCond))
        (jLambda (fj/exprToJson eLambda))]
    (do
      (assert (ok? (fj/parseAstExpr jIdent)) "parseAstExpr ident succeeds")
      (assert (ok? (fj/parseAstExpr jCall)) "parseAstExpr call succeeds")
      (assert (ok? (fj/parseAstExpr jMember)) "parseAstExpr member succeeds")
      (assert (ok? (fj/parseAstExpr jLet)) "parseAstExpr let succeeds")
      (assert (ok? (fj/parseAstExpr jIf)) "parseAstExpr if succeeds")
      (assert (ok? (fj/parseAstExpr jMatch)) "parseAstExpr match succeeds")
      (assert (ok? (fj/parseAstExpr jTry)) "parseAstExpr try succeeds")
      (assert (ok? (fj/parseAstExpr jBlock)) "parseAstExpr block succeeds")
      (assert (ok? (fj/parseAstExpr jCond)) "parseAstExpr cond succeeds")
      (assert (ok? (fj/parseAstExpr jLambda)) "parseAstExpr lambda succeeds")
      (let [(aslRes (fj/fromJsonToAsl (fj/exprToJsonString eCall)))]
        (do
          (assert (ok? aslRes) "fromJsonToAsl for call expression succeeds")
          (assert (= (resultOr aslRes "") "+ a 10") "call expression serializes to canonical + a 10")))
      true))

fn testDeclarationsRoundtrip! -> Bool
  (let [(dFn (a/topDefun (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false :params (list (a/Param :name "x" :type "Int64") (a/Param :name "y" :type "Int64")) :retType "Int64" :docstring "" :body (list (cv/lower (a/exprCall (a/exprIdent "+") (list (a/exprIdent "x") (a/exprIdent "y"))))) :bodyPos (list))))
        (dSchema (a/topSchema (a/SchemaNode :name "Point" :typeVars (list) :fields (list (a/AstField :name "x" :type "Int64" :docstring "\"X\"" :default (none) :json (none)) (a/AstField :name "y" :type "Int64" :docstring "\"Y\"" :default (none) :json (none))) :jsonCase (none))))
        (dEnum (a/topEnum (a/EnumNode :name "Color" :typeVars (list) :cases (list (a/EnumCase :name "red" :fields (list (a/Param :name "shade" :type "Int64")) :docstring "\"Red\"") (a/EnumCase :name "green" :fields (list) :docstring "\"Green\"")))))
        (dModule (a/topModule (a/ModuleNode :path "demo/pkg" :docstring "" :exported (list "add" "Point") :imports (list (pair "other/lib" "lib")) :defs (list dFn dSchema dEnum))))
        (jFn (fj/topFormToJson dFn))
        (jSchema (fj/topFormToJson dSchema))
        (jEnum (fj/topFormToJson dEnum))
        (jModule (fj/topFormToJson dModule))]
    (do
      (let [(vFn (validateTopFormJson! jFn))
            (vSchema (validateTopFormJson! jSchema))
            (vEnum (validateTopFormJson! jEnum))
            (vModule (validateTopFormJson! jModule))]
        (do
          (assert (mt vFn ((ok b) b) ((err _) false)) (str "defun json satisfies topForm schema: " (mt vFn ((ok _) "ok") ((err e) e))))
          (assert (mt vSchema ((ok b) b) ((err _) false)) (str "schema json satisfies topForm schema: " (mt vSchema ((ok _) "ok") ((err e) e))))
          (assert (mt vEnum ((ok b) b) ((err _) false)) (str "enum json satisfies topForm schema: " (mt vEnum ((ok _) "ok") ((err e) e))))
          (assert (mt vModule ((ok b) b) ((err _) false)) (str "module json satisfies topForm schema: " (mt vModule ((ok _) "ok") ((err e) e))))))
      (let [(aslFnRes (fj/fromJsonToAsl (fj/topFormToJsonString dFn)))]
        (do
          (assert (ok? aslFnRes) "defun serializes to canonical asl")
          (let [(reparsed (a/parse (resultOr aslFnRes "")))]
            (assert (ok? reparsed) "reparsed defun parses cleanly")
            (assert (topFormsEquivalent? (list dFn) (resultOr reparsed (list))) "reparsed defun equivalent to original"))))
      (let [(aslSchemaRes (fj/fromJsonToAsl (fj/topFormToJsonString dSchema)))]
        (do
          (assert (ok? aslSchemaRes) "schema serializes to canonical asl")
          (let [(reparsed (a/parse (resultOr aslSchemaRes "")))]
            (assert (ok? reparsed) "reparsed schema parses cleanly")
            (assert (topFormsEquivalent? (list dSchema) (resultOr reparsed (list))) "reparsed schema equivalent to original"))))
      (let [(aslEnumRes (fj/fromJsonToAsl (fj/topFormToJsonString dEnum)))]
        (do
          (assert (ok? aslEnumRes) "enum serializes to canonical asl")
          (let [(reparsed (a/parse (resultOr aslEnumRes "")))]
            (assert (ok? reparsed) "reparsed enum parses cleanly")
            (assert (topFormsEquivalent? (list dEnum) (resultOr reparsed (list))) "reparsed enum equivalent to original"))))
      (let [(aslModuleRes (fj/fromJsonToAsl (fj/topFormToJsonString dModule)))]
        (do
          (assert (ok? aslModuleRes) "module serializes to canonical asl")
          (let [(reparsed (a/parse (resultOr aslModuleRes "")))]
            (assert (ok? reparsed) "reparsed module parses cleanly")
            (assert (topFormsEquivalent? (list dModule dFn dSchema dEnum) (resultOr reparsed (list))) "reparsed module defs equivalent to original"))))
      true))

fn verifySingleTopForm! path: String idx: Int64 tf: a/TopForm -> Bool
  (let [(jVal (fj/topFormToJson tf))
        (vVal (validateTopFormJson! jVal))]
    (do
      (assert (mt vVal ((ok b) b) ((err _) false)) (str path " form " (stringFromInt64 idx) " validates against TopForm schema: " (mt vVal ((ok _) "ok") ((err e) e))))
      (let [(jsonStr (fj/topFormToJsonString tf))]
        (mt (fj/fromJsonToAsl jsonStr)
          ((err e)
           (do
             (assert false (str path " form " (stringFromInt64 idx) " fromJsonToAsl: " e))
             false))
          ((ok aslText)
           (mt (a/parse aslText)
             ((err e)
              (do
               (assert false (str path " form " (stringFromInt64 idx) " reparse: " e.msg))
               false))
             ((ok reparsedForms)
              (let [(expectedForms (mt tf
                                      ((a/topModule m)
                                       (if (listEmpty? m.defs) (list tf) (cons tf m.defs)))
                                      (_ (list tf))))
                    (equiv (topFormsEquivalent? expectedForms reparsedForms))]
                (do
                  (if (not equiv)
                    (print (str "DIFF in " path " form " (stringFromInt64 idx) ":\n  ORIG: " (rd/renderSexpr (cv/topFormToSexpr tf)) "\n  REPARSED: " (mt (listHead reparsedForms) ((some rf) (rd/renderSexpr (cv/topFormToSexpr rf))) ((none) "<empty>")) "\n  ASL:\n" aslText "\n"))
                    ())
                  (assert equiv (str path " form " (stringFromInt64 idx) " roundtrip equivalence"))
                  equiv)))))))))

fn verifyTopFormsList! path: String idx: Int64 forms: (List a/TopForm) -> Bool
  (mt (listHead forms)
    ((none) true)
    ((some tf)
     (let [(ok1 (verifySingleTopForm! path idx tf))
           (rest (optionOr (listTail forms) (list)))
           (okRest (verifyTopFormsList! path (+ idx 1) rest))]
       (and ok1 okRest))))

fn verifyCorpusFile! path: String -> Bool
  (mt (fileRead path)
    ((err e)
     (do
       (assert false (str path " read error: " e))
       false))
    ((ok src)
     (mt (a/parse src)
       ((err e)
        (do
          (assert false (str path " initial parse error: " e.msg))
          false))
       ((ok origForms)
        (let [(formsOk (verifyTopFormsList! path 0 origForms))
              (jsonAll (mt (listHead origForms)
                         ((some tf0)
                          (mt tf0
                            ((a/topModule _) (fj/topFormToJsonString tf0))
                            (_ (fj/topFormsToJsonString origForms))))
                         ((none) (fj/topFormsToJsonString origForms))))]
          (mt (fj/fromJsonToAsl jsonAll)
            ((err e)
             (do
               (assert false (str path " whole-file fromJsonToAsl: " e))
               false))
            ((ok aslText)
             (mt (a/parse aslText)
              ((err e)
               (do
                 (assert false (str path " whole-file reparse: " e.msg))
                 false))
              ((ok reparsedForms)
               (let [(equiv (topFormsEquivalent? origForms reparsedForms))]
                 (do
                   (assert equiv (str path " whole-file JSON roundtrip equivalence"))
                   (and formsOk equiv))))))))))))

fn verifyCorpusFiles! files: (List String) -> Bool
  (mt (listHead files)
    ((none) true)
    ((some f)
     (let [(fOk (verifyCorpusFile! f))
           (rest (optionOr (listTail files) (list)))
           (restOk (verifyCorpusFiles! rest))]
       (and fOk restOk))))

fn testSchemaValidationRefutations -> Bool
  (let [(badKind (fj/fromJsonTopForm "{\"kind\":\"unknownType\",\"node\":{}}"))
        (badSyntax (fj/fromJsonTopForm "{malformed json"))
        (badDefun (fj/fromJsonTopForm "{\"kind\":\"topDefun\",\"node\":{\"name\":\"f\"}}"))]
    (do
      (refute (ok? badKind) "unknown kind refutes topForm parsing")
      (refute (ok? badSyntax) "malformed json refutes parsing")
      (refute (ok? badDefun) "defun missing required params and retType refutes parsing")
      true))

fn testMutantGuards -> Bool
  (let [(f1 (a/topDefun (a/DefunNode :name "a" :typeVars (list) :isExported false :effect false :params (list) :retType "Int64" :docstring "" :body (list (cv/lower (a/exprLit (a/litInt 1)))) :bodyPos (list))))
        (f2 (a/topDefun (a/DefunNode :name "b" :typeVars (list) :isExported false :effect false :params (list) :retType "Int64" :docstring "" :body (list (cv/lower (a/exprLit (a/litInt 1)))) :bodyPos (list))))
        (f3 (a/topDefun (a/DefunNode :name "a" :typeVars (list) :isExported false :effect false :params (list) :retType "Int64" :docstring "" :body (list (cv/lower (a/exprLit (a/litInt 2)))) :bodyPos (list))))
        (f4 (a/topDefun (a/DefunNode :name "a" :typeVars (list) :isExported false :effect true :params (list) :retType "Int64" :docstring "" :body (list (cv/lower (a/exprLit (a/litInt 1)))) :bodyPos (list))))
        (module1 (a/topModule (a/ModuleNode :path "demo/pkg" :docstring "" :exported (list) :imports (list) :defs (list f1))))
        (module2 (a/topModule (a/ModuleNode :path "demo/pkg" :docstring "" :exported (list) :imports (list) :defs (list f4))))]
    (do
      (assert (topFormsEquivalent? (list f1) (list f1)) "topFormsEquivalent accepts identical forms")
      (refute (topFormsEquivalent? (list f1) (list f2)) "topFormsEquivalent refutes name mismatch")
      (refute (topFormsEquivalent? (list f1) (list f3)) "topFormsEquivalent refutes body mismatch")
      (refute (topFormsEquivalent? (list f1) (list f4)) "topFormsEquivalent refutes effect marker mismatch")
      (refute (topFormsEquivalent? (list module1) (list module2)) "topFormsEquivalent refutes module def effect marker mismatch")
      (refute (topFormsEquivalent? (list f1) (list)) "topFormsEquivalent refutes length mismatch")
      true))

fn testBoundsCheckMutants -> Bool
  (let [(emptyArr (j/jarr (list)))
        (oneArrImport (j/jarr (list (j/jstr "foo"))))
        (twoArrImport (j/jarr (list (j/jstr "foo") (j/jstr "bar"))))
        (threeArrImport (j/jarr (list (j/jstr "foo") (j/jstr "bar") (j/jstr "baz"))))
        (resImport0 (fj/parseImportEntry emptyArr))
        (resImport1 (fj/parseImportEntry oneArrImport))
        (resImport2 (fj/parseImportEntry twoArrImport))
        (resImport3 (fj/parseImportEntry threeArrImport))
        (patNode (j/jobj (list (pair "kind" (j/jstr "patWildcard")))))
        (exprNode (j/jobj (list (pair "kind" (j/jstr "exprLit")) (pair "lit" (j/jobj (list (pair "kind" (j/jstr "litInt")) (pair "val" (j/jint 1))))))))
        (oneArrLet (j/jarr (list patNode)))
        (twoArrLet (j/jarr (list patNode exprNode)))
        (threeArrLet (j/jarr (list patNode exprNode (j/jint 42))))
        (resLet0 (fj/parseLetBinding emptyArr))
        (resLet1 (fj/parseLetBinding oneArrLet))
        (resLet2 (fj/parseLetBinding twoArrLet))
        (resLet3 (fj/parseLetBinding threeArrLet))]
    (do
      (assert (= resImport0 (err "ImportEntry array too short")) "parseImportEntry refutes empty array")
      (assert (= resImport1 (err "ImportEntry array too short")) "parseImportEntry refutes 1-element array")
      (assert (ok? resImport2) "parseImportEntry accepts 2-element array")
      (assert (ok? resImport3) "parseImportEntry accepts 3-element array")
      (assert (= resLet0 (err "LetBinding array too short")) "parseLetBinding refutes empty array")
      (assert (= resLet1 (err "LetBinding array too short")) "parseLetBinding refutes 1-element array")
      (assert (ok? resLet2) "parseLetBinding accepts 2-element array")
      (assert (ok? resLet3) "parseLetBinding accepts 3-element array")
      true))

fn inScopeCorpusFiles -> (List String)
  (list "asl/grammar/corpus/valid/01-basics.asl"
        "asl/grammar/corpus/valid/02-match.asl"
        "asl/grammar/corpus/valid/03-strings.asl"
        "asl/grammar/corpus/valid/05-constructors.asl"
        "asl/grammar/corpus/valid/08-io.asl"
        "asl/grammar/corpus/valid/16-recursive-schema.asl"
        "asl/grammar/corpus/valid/20-option-result-ctors.asl"
        "asl/grammar/corpus/valid/22-boolean-algebra.asl"
        "asl/grammar/corpus/valid/26-map-lifecycle.asl"
        "asl/packages/asl-derive/src/main.asl"
        "asl/packages/asl-agent-bus/src/ambient.asl"
        "asl/packages/asl-agent-bus/src/asnlRing.asl"
        "asl/packages/asl-agent-bus/src/bridge.asl"
        "asl/packages/asl-syntax/src/core/bytesText.asl"
        "asl/packages/asl-search/src/commonCrawl.asl"
        "asl/packages/asl-syntax/src/core/outline.asl")

fn ! runTests -> Bool
  (do
    (assert (testSchemaValidationRefutations) "schema refutes malformed forms")
    (assert (testMutantGuards) "mutant guards refute non-equivalent forms")
    (assert (testBoundsCheckMutants) "bounds-check mutants in parseImportEntry and parseLetBinding refuted")
    (assert (testLiteralsRoundtrip!) "literal roundtrips pass")
    (assert (testExpressionsRoundtrip) "expression roundtrips pass")
    (assert (testDeclarationsRoundtrip!) "declaration roundtrips pass")
    (assert (verifyCorpusFiles! (inScopeCorpusFiles)) "valid corpus forms roundtrip through JSON")
    true)

