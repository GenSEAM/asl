(module asl-syntax/tests/js/moduleTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/stmt :a stmt)
      (asl-syntax/js/module :a jsm)
      (asl-syntax/js/symbols :a jssym)])

fn checkModuleRoundTrip! code: String label: String -> Bool
  (let [(parseRes (jsm/parseModule code))]
    (do
      (if (ok? parseRes) () (println (str "PARSE FAIL " label ": " parseRes)))
      (assert (ok? parseRes) (str "module parses ok: " label))
      (let [(root (resultOr parseRes (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString code root))]
        (do
          (assert (= printed code) (str "module round-trip exact: " label))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "module tiling exact: " label))
          true))))

fn testImportForms! -> Bool
  (do
    (checkModuleRoundTrip! "import 'module-name';\n" "side-effect import")
    (checkModuleRoundTrip! "import defaultExport from 'module-name';\n" "default import")
    (checkModuleRoundTrip! "import * as name from 'module-name';\n" "namespace import")
    (checkModuleRoundTrip! "import { export1, export2 as alias2 } from 'module-name';\n" "named import")
    (checkModuleRoundTrip! "import defaultExport, { export1 } from 'module-name';\n" "default and named import")
    (checkModuleRoundTrip! "import defaultExport, * as name from 'module-name';\n" "default and namespace import")
    (checkModuleRoundTrip! "import data from './data.json' with { type: 'json' };\n" "import attributes with")
    (checkModuleRoundTrip! "import data from './data.json' assert { type: 'json' };\n" "import attributes assert")
    (checkModuleRoundTrip! "const mod = await import('./mod.js');\n" "dynamic import")
    (checkModuleRoundTrip! "const url = import.meta.url;\n" "import.meta")
    true)

fn testExportForms! -> Bool
  (do
    (checkModuleRoundTrip! "export default function foo() {\n  return 1;\n}\n" "export default function")
    (checkModuleRoundTrip! "export default class Bar {\n}\n" "export default class")
    (checkModuleRoundTrip! "export default 42;\n" "export default expr")
    (checkModuleRoundTrip! "export { name1, name2 as alias2 };\n" "export named")
    (checkModuleRoundTrip! "export * from 'mod';\n" "export all")
    (checkModuleRoundTrip! "export * as ns from 'mod';\n" "export namespace")
    (checkModuleRoundTrip! "export { x } from 'mod';\n" "export re-export")
    (checkModuleRoundTrip! "export { x } from 'mod' with { type: 'json' };\n" "export re-export with attributes")
    (checkModuleRoundTrip! "export const x = 1;\n" "export const")
    (checkModuleRoundTrip! "export let y = 2;\n" "export let")
    (checkModuleRoundTrip! "export var z = 3;\n" "export var")
    (checkModuleRoundTrip! "export function f() {\n}\n" "export function")
    (checkModuleRoundTrip! "export class C {\n}\n" "export class")
    (checkModuleRoundTrip! "export async function af() {\n}\n" "export async function")
    true)

fn testTrackedWebFiles! -> Bool
  (let [(res1 (fileRead "asl/packages/asl-syntax/tests/fixtures/js/tailwind.config.js.sample"))
        (res2 (fileRead "asl/packages/asl-syntax/tests/fixtures/js/vite.config.js.sample"))]
    (do
      (assert (ok? res1) "tailwind.config.js reads ok")
      (assert (ok? res2) "vite.config.js reads ok")
      (checkModuleRoundTrip! (resultOr res1 "") "tailwind.config.js")
      (checkModuleRoundTrip! (resultOr res2 "") "vite.config.js")
      true))

fn testSymbolQueries! -> Bool
  (let [(code "function alpha() {\n  return 1;\n}\nconst beta = 2;\nclass Gamma {\n  delta() {\n    return 3;\n  }\n}\n")
        (syms (jssym/extractSymbols! code))
        (alphaSym (jssym/findSymbol syms "alpha"))
        (betaSym (jssym/findSymbol syms "beta"))
        (gammaSym (jssym/findSymbol syms "Gamma"))
        (deltaSym (jssym/findSymbol syms "delta"))
        (nearest (jssym/nearestSymbols "alph" syms 3))
        (s (src/sourceFromString "test.js" code))
        (items (jssym/jsOutlineItems s syms))
        (receipt (jssym/jsOutlineReceipt! "test.js" "javascript" code))]
    (do
      (assert (= (listLength syms) 4) "extracted 4 symbols from test code")
      (assert (some? alphaSym) "found alpha symbol")
      (assert (some? betaSym) "found beta symbol")
      (assert (some? gammaSym) "found Gamma symbol")
      (assert (some? deltaSym) "found delta symbol")
      (assert (> (listLength nearest) 0) "nearest symbols found")
      (assert (= (optionOr (listHead nearest) "") "alpha") "nearest symbol to alph is alpha")
      (assert (= (listLength items) 4) "4 outline items generated")
      (assert (stringContains? receipt "(:item :name \"alpha\"") "receipt contains alpha item")
      (assert (stringContains? receipt "(:item :name \"beta\"") "receipt contains beta item")
      (assert (stringContains? receipt "(:item :name \"Gamma\"") "receipt contains Gamma item")
      (assert (stringContains? receipt "(:item :name \"delta\"") "receipt contains delta item")
      true))

fn checkModuleErr! code: String expectedOffset: Int64 label: String -> Bool
  (let [(res (jsm/parseModule code))]
    (mt res
      ((ok _)
       (do
         (println (str "EXPECTED ERROR BUT GOT OK FOR: " label " -> " code))
         (assert false (str "expected parse error for: " label))))
      ((err msg)
       (let [(expectedMsg (str "Parse error at offset " (stringFromInt64 expectedOffset)))]
         (do
           (if (!= msg expectedMsg)
             (do
               (println (str "OFFSET MISMATCH for " label))
               (println (str "  GOT:      " msg))
               (println (str "  EXPECTED: " expectedMsg)))
             ())
           (assert (= msg expectedMsg) (str "parse error offset matches for: " label))
           true)))))

fn checkImportDeclErr code: String expectedOffset: Int64 label: String -> Bool
  (let [(toks (lx/tokenize code))
        (res (jsm/parseImportDecl toks code))]
    (mt res
      ((ok _)
       (assert false (str "expected parseImportDecl error for: " label)))
      ((err msg)
       (let [(expectedMsg (str "Parse error at offset " (stringFromInt64 expectedOffset)))]
         (do
           (assert (= msg expectedMsg) (str "parseImportDecl error offset matches for: " label))
           true)))))

fn checkExportDeclErr code: String expectedOffset: Int64 label: String -> Bool
  (let [(toks (lx/tokenize code))
        (res (jsm/parseExportDecl toks code))]
    (mt res
      ((ok _)
       (assert false (str "expected parseExportDecl error for: " label)))
      ((err msg)
       (let [(expectedMsg (str "Parse error at offset " (stringFromInt64 expectedOffset)))]
         (do
           (assert (= msg expectedMsg) (str "parseExportDecl error offset matches for: " label))
           true)))))

fn testTreeShapes -> Bool
  (do
    (let [(code "import data from \x27./data.json\x27 with { type: \x27json\x27 };\n")
          (res (jsm/parseModule code))]
      (do
        (assert (ok? res) "import attributes parses ok")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (modKids (stmt/findChildNodes (tr/nodeChildren root)))
              (importNode (optionOr (listHead modKids) (tr/makeErrorNode 0 0 (list))))
              (declKids (stmt/findChildNodes (tr/nodeChildren importNode)))
              (attrNode (optionOr (listHead declKids) (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (tr/nodeKind root) "module") "root is module")
            (assert (= (listLength modKids) 1) "module has 1 child node")
            (assert (= (tr/nodeKind importNode) "importDecl") "child is importDecl")
            (assert (= (listLength declKids) 1) "importDecl has 1 child node for attributes")
            (assert (= (tr/nodeKind attrNode) "importAttributes") "attribute node kind is importAttributes")
            (assert (> (listLength (tr/nodeChildren attrNode)) 0) "importAttributes has children")))))
    (let [(code "import(x);\n")
          (res (jsm/parseModule code))]
      (do
        (assert (ok? res) "dynamic import(x) parses ok")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (modKids (stmt/findChildNodes (tr/nodeChildren root)))
              (stmtNode (optionOr (listHead modKids) (tr/makeErrorNode 0 0 (list))))
              (stmtKids (stmt/findChildNodes (tr/nodeChildren stmtNode)))
              (callNode (optionOr (listHead stmtKids) (tr/makeErrorNode 0 0 (list))))
              (callKids (stmt/findChildNodes (tr/nodeChildren callNode)))
              (callee (optionOr (listHead callKids) (tr/makeErrorNode 0 0 (list))))
              (arg0 (optionOr (listGet callKids 1) (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (tr/nodeKind stmtNode) "exprStmt") "dynamic import stmt is exprStmt")
            (assert (= (tr/nodeKind callNode) "callExpr") "dynamic import expr is callExpr")
            (assert (= (listLength callKids) 2) "callExpr has 2 children: callee and 1 arg")
            (assert (= (tr/nodeKind callee) "ident") "dynamic import callee is ident")
            (assert (= (tr/nodeKind arg0) "ident") "dynamic import arg0 is ident")))))
    (let [(code "import(x, opts);\n")
          (res (jsm/parseModule code))]
      (do
        (assert (ok? res) "dynamic import(x, opts) parses ok")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (modKids (stmt/findChildNodes (tr/nodeChildren root)))
              (stmtNode (optionOr (listHead modKids) (tr/makeErrorNode 0 0 (list))))
              (stmtKids (stmt/findChildNodes (tr/nodeChildren stmtNode)))
              (callNode (optionOr (listHead stmtKids) (tr/makeErrorNode 0 0 (list))))
              (callKids (stmt/findChildNodes (tr/nodeChildren callNode)))
              (callee (optionOr (listHead callKids) (tr/makeErrorNode 0 0 (list))))
              (arg0 (optionOr (listGet callKids 1) (tr/makeErrorNode 0 0 (list))))
              (arg1 (optionOr (listGet callKids 2) (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (tr/nodeKind stmtNode) "exprStmt") "dynamic import opts stmt is exprStmt")
            (assert (= (tr/nodeKind callNode) "callExpr") "dynamic import opts expr is callExpr")
            (assert (= (listLength callKids) 3) "callExpr has 3 children: callee and 2 args")
            (assert (= (tr/nodeKind callee) "ident") "callee is ident")
            (assert (= (tr/nodeKind arg0) "ident") "arg0 is ident")
            (assert (= (tr/nodeKind arg1) "ident") "arg1 is ident")))))
    (let [(code "import.meta;\n")
          (res (jsm/parseModule code))]
      (do
        (assert (ok? res) "import.meta parses ok")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (modKids (stmt/findChildNodes (tr/nodeChildren root)))
              (stmtNode (optionOr (listHead modKids) (tr/makeErrorNode 0 0 (list))))
              (stmtKids (stmt/findChildNodes (tr/nodeChildren stmtNode)))
              (metaNode (optionOr (listHead stmtKids) (tr/makeErrorNode 0 0 (list))))
              (metaLeaves (tr/nodeLeaves metaNode))]
          (do
            (assert (= (tr/nodeKind stmtNode) "exprStmt") "import.meta stmt is exprStmt")
            (assert (= (tr/nodeKind metaNode) "metaProperty") "import.meta expr is metaProperty")
            (assert (= (listLength metaLeaves) 3) "metaProperty has 3 leaf tokens")))))
    true)

fn testNegativeCases! -> Bool
  (do
    (assert (checkModuleErr! "import a;\n" 8 "import without from with semi") "import without from semi")
    (assert (checkImportDeclErr "import a;\n" 8 "import without from with semi") "importDecl without from semi")
    (assert (checkModuleErr! "import { a, from \"x\";\n" 12 "import { a, from x") "import unclosed brace with from")
    (assert (checkImportDeclErr "import { a, from \"x\";\n" 12 "import { a, from x") "importDecl unclosed brace with from")
    (assert (checkModuleErr! "export { a as } from \"x\";\n" 14 "export { a as } from x") "export missing alias")
    (assert (checkExportDeclErr "export { a as } from \"x\";\n" 14 "export { a as } from x") "exportDecl missing alias")
    (assert (checkModuleErr! "export default;\n" 14 "export default with nothing") "export default nothing semi")
    (assert (checkExportDeclErr "export default;\n" 14 "export default with nothing") "exportDecl default nothing semi")
    (assert (checkModuleErr! "export default" 14 "export default EOF") "export default EOF")
    (assert (checkExportDeclErr "export default" 14 "export default EOF") "exportDecl default EOF")
    (assert (checkModuleErr! "import \"x\" with { type: };\n" 24 "import with empty attribute value") "import with empty attr value")
    (assert (checkImportDeclErr "import \"x\" with { type: };\n" 24 "import with empty attribute value") "importDecl with empty attr value")
    (assert (checkModuleErr! "import.foo;\n" 7 "import.foo") "import.foo rejected")
    (assert (checkImportDeclErr "import.foo;\n" 7 "import.foo") "importDecl import.foo rejected")
    true)

fn ! runTests -> Bool
  (and (testImportForms!)
  (and (testTreeShapes)
  (and (testNegativeCases!)
  (and (testExportForms!)
  (and (testTrackedWebFiles!)
       (testSymbolQueries!))))))
