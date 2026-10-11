(module asl-syntax/tests/ts/moduleTsTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/ts/module :a tsMod)])

fn treeHasError? node: tr/Node -> Bool
  (if (tr/isErrorNode node)
    true
    (elementsHaveError? (tr/nodeChildren node)))

fn elementsHaveError? elems: (List tr/TreeElement) -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode n) (if (treeHasError? n) true (elementsHaveError? tl)))
        ((tr/elemToken t) (if (tr/isErrorToken t) true (elementsHaveError? tl))))))

fn checkExactRoundTrip! code: String -> Bool
  (let [(res (tsMod/parse code))]
    (do
      (mt res
        ((ok _) ())
        ((err msg)
         (println (str "PARSE ERROR: " msg " FOR: " code))))
      (assert (ok? res) (str "tsMod/parse succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= printed code)
            (println (str "ROUNDTRIP MISMATCH: GOT [" printed "] EXPECTED [" code "]"))
            ())
          (assert (= printed code) (str "tsMod round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "tsMod tiling exact: " code))
          (assert (not (treeHasError? root)) (str "no error nodes in parse tree: " code))
          true))))

fn upstreamBabelFiles -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/abstract-false-positive.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/abstract-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/abstract.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/accessor.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/constructor-with-modifier-names.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/constructor-with-override-modifer-names.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/declare-field-modifiers.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/index-signature.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/members-with-modifier-names.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/method-modifier-name-with-type-parameters.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/method-with-modifiers-asi.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/modifiers-accessors.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/modifiers-methods-async.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/modifiers-override.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/modifiers-properties.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/optional-generator-method-with-modifiers.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/parameter-properties-with-decorators.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/parameter-properties.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/private-fields-modifier-readonly.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/const-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/const.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/destructure.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/eval-dts.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/eval.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/function-rest-trailing-comma.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/interface-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/interface.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/let-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/let.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/pattern-parameters.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/valid-namespace-var.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/var-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/var.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/decorators/type-arguments.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/const.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/declare-const.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/declare-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/declare.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/enum-as-or-satisfies-brackets.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/export-const.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/export-declare-const.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/export.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/members-reserved-words.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/members-strings.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/members-trailing-comma-with-initializer.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/members-trailing-comma.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/enum/members.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/function/overloads.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/call-signature.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/construct-signature.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/export.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/extends-identifier-type-arguments.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/extends.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/function-like-node-1.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/function-like-node-2.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/function-like-node-3.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/function-like-node-4.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/function-like-node-5.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/generic.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/get-set-ambiguous.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/get-set-methods.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/get-set.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/index-signature.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/interface-as-or-satisfies-brackets.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/method-computed.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/method-generic.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/method-optional.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/method-plain.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/modifiers.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/pattern-parameters.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/properties.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/property-computed.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/property-named-public.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/reserved-method-name.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/separators.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/legacy-decorators/abstract-class.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/legacy-decorators/type-arguments.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-declare-export-named-declaration.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-declare-export-named.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-declare.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-export-named-declaration.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-import-equals-internal.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-nested-declare.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body-nested.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/body.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/declare-shorthand.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/global-in-module.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/head-declare.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/head-export.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/head.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/module-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/namespace-as-or-satisfies-brackets.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/module-namespace/namespace-new-line.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/type-alias/declare.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/type-alias/export.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/type-alias/generic-complex-tokens-true.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/type-alias/generic.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/type-alias/plain.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/type-alias/type-as-or-satisfies-equals.ts.sample"
  )

fn upstreamBabelExclusions -> (List (Pair String String))
  (list
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/class/optional-generator-method-with-modifiers.ts.sample" "optional chaining in computed class method name (unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/destructure.ts.sample" "destructuring pattern in variable declaration (unit S3)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/declare/pattern-parameters.ts.sample" "destructuring pattern in parameter list (unit S3)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/function-like-node-2.ts.sample" "generic function type without parameter list (unit TS1)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-ts/interface/pattern-parameters.ts.sample" "destructuring pattern in parameter list (unit S3)")
  )

fn printExclusions! prefix: String cases: (List (Pair String String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair "" "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (str "  " prefix " excluded: " (pairFirst head) " (" (pairSecond head) ")"))
        (printExclusions! prefix tail))))

fn findExclusionReason path: String exclusions: (List (Pair String String)) -> (Option String)
  (if (listEmpty? exclusions)
    (none)
    (let [(head (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (if (= (pairFirst head) path)
        (some (pairSecond head))
        (findExclusionReason path tail))))

fn checkFileExactRoundTrip! path: String content: String -> Bool
  (let [(len (stringLength content))
        (parseRes (tsMod/parse content))]
    (mt parseRes
      ((err msg)
       (do
         (println (str "PARSE ERROR [" path "]: " msg))
         false))
      ((ok root)
       (let [(printed (pr/printTreeString content root))
             (tiled (ok? (tr/checkTiling root len)))
             (hasErr (treeHasError? root))
             (exact (= printed content))]
         (do
           (if (not exact)
             (println (str "ROUNDTRIP MISMATCH [" path "]"))
             ())
           (if (not tiled)
             (println (str "TILING ERROR [" path "]"))
             ())
           (if hasErr
             (println (str "ERROR NODES IN TREE [" path "]"))
             ())
           (and exact (and tiled (not hasErr))))))))

fn checkBabelTsSuite! suiteName: String files: (List String) exclusions: (List (Pair String String)) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str suiteName " suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! suiteName exclusions)
      true)
    (let [(path (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (findExclusionReason path exclusions)
        ((some _)
         (checkBabelTsSuite! suiteName rest exclusions runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (if (not (ok? readRes))
             (do
               (assert false (str "read failed: " path))
               (checkBabelTsSuite! suiteName rest exclusions (+ runCount 1) passCount excludedCount))
             (let [(content (resultOr readRes ""))
                   (pass? (checkFileExactRoundTrip! path content))]
               (do
                 (assert pass? (str "round-trip: " path))
                 (checkBabelTsSuite! suiteName rest exclusions (+ runCount 1) (if pass? (+ passCount 1) passCount) excludedCount)))))))))

fn testTrackedTsFiles! -> Bool
  (let [(cmd (processRun "git ls-files \"*.ts\""))]
    (do
      (assert (= cmd.exitCode 0) "git ls-files *.ts exits 0")
      (let [(stdout (stringTrim cmd.stdout))]
        (if (stringEmpty? stdout)
          (do (assert (= (stringLength stdout) 0) "zero tracked .ts files in repository") true)
          (checkTrackedFilesLoop! (stringLines stdout))))))

fn checkTrackedFilesLoop! files: (List String) -> Bool
  (if (listEmpty? files)
    true
    (let [(path (optionOr (listHead files) ""))
          (tl (optionOr (listTail files) (list)))]
      (if (stringEmpty? path)
        (checkTrackedFilesLoop! tl)
        (let [(readRes (fileReadString path))]
          (if (not (ok? readRes))
            (do
              (assert false (str "read failed on tracked file: " path))
              (checkTrackedFilesLoop! tl))
            (let [(content (resultOr readRes ""))
                  (pass? (checkFileExactRoundTrip! path content))]
              (do
                (assert pass? (str "tracked file round-trip: " path))
                (checkTrackedFilesLoop! tl))))))))

fn testWholeModuleImportsExports! -> Bool
  (do
    (checkExactRoundTrip! "import { a, b as c } from \"./mod\";")
    (checkExactRoundTrip! "import type { T, U as V } from \"./types\";")
    (checkExactRoundTrip! "import * as ns from \"./ns\";")
    (checkExactRoundTrip! "import def, { x } from \"./pkg\";")
    (checkExactRoundTrip! "import x = require(\"./legacy\");")
    (checkExactRoundTrip! "import y = A.B.C;")
    (checkExactRoundTrip! "export { a, c };")
    (checkExactRoundTrip! "export type { T };")
    (checkExactRoundTrip! "export const x = 1;")
    (checkExactRoundTrip! "export default function run() { return 42; }")
    (checkExactRoundTrip! "export default class App { start(): void {} }")
    true)

fn testWholeModuleDeclarations! -> Bool
  (do
    (checkExactRoundTrip! "interface Point { x: number; y: number; }")
    (checkExactRoundTrip! "type ID = string | number;")
    (checkExactRoundTrip! "enum Color { Red, Green, Blue }")
    (checkExactRoundTrip! "const enum Direction { Up = 1, Down }")
    (checkExactRoundTrip! "class Greeter { greeting: string; constructor(msg: string) { this.greeting = msg; } }")
    (checkExactRoundTrip! "abstract class Base { abstract greet(): void; }")
    (checkExactRoundTrip! "function add(a: number, b: number): number { return a + b; }")
    (checkExactRoundTrip! "function fn(x: number): number;\nfunction fn(x: string): string;\nfunction fn(x: any): any { return x; }")
    true)

fn testWholeModuleStatementsAndExpressions! -> Bool
  (do
    (checkExactRoundTrip! "let count: number = 0;")
    (checkExactRoundTrip! "const msg: string = \"hello\";")
    (checkExactRoundTrip! "if (count > 0) { count = 1; }")
    (checkExactRoundTrip! "while (count < 10) { count = count + 1; }")
    (checkExactRoundTrip! "(x as number) + 1;")
    (checkExactRoundTrip! "a satisfies boolean;")
    (checkExactRoundTrip! "f<T>(x);")
    (checkExactRoundTrip! "x!;")
    (checkExactRoundTrip! "<string>val;")
    true)

fn testWholeModuleCombined! -> Bool
  (let [(code "import { Config } from \"./config\";\n\ninterface Service {\n  start(): void;\n}\n\nexport class MyService implements Service {\n  private running: boolean = false;\n  start(): void {\n    this.running = true;\n  }\n}\n\nconst s = new MyService();\ns.start();\nexport default s;\n")]
    (checkExactRoundTrip! code))

fn testModuleHelpers -> Bool
  (let [(res (tsMod/parse "const x: number = 42;"))]
    (do
      (assert (ok? res) "parse returns ok")
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))]
        (do
          (assert (tsMod/isModuleNode root) "root is module node")
          (assert (= (tsMod/moduleKind root) "module") "moduleKind is module")
          true))))

fn ! runTests -> Bool
  (do
    (testWholeModuleImportsExports!)
    (testWholeModuleDeclarations!)
    (testWholeModuleStatementsAndExpressions!)
    (testWholeModuleCombined!)
    (testModuleHelpers)
    (testTrackedTsFiles!)
    (assert (checkBabelTsSuite! "babel-ts" (upstreamBabelFiles) (upstreamBabelExclusions) 0 0 0) "upstream babel-ts suite")
    true)
