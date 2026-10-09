(module asl-syntax/tests/ts/symbolsTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/ts/symbols :a tssym)])

fn testSymbolQueries! -> Bool
  (let [(code "function alpha() {\n  return 1;\n}\nconst beta = 2;\nclass Gamma {\n  delta() {\n    return 3;\n  }\n}\n")
        (syms (tssym/extractSymbols! code))
        (alphaSym (tssym/findSymbol syms "alpha"))
        (betaSym (tssym/findSymbol syms "beta"))
        (gammaSym (tssym/findSymbol syms "Gamma"))
        (deltaSym (tssym/findSymbol syms "delta"))
        (nearest (tssym/nearestSymbols "alph" syms 3))
        (s (src/sourceFromString "test.ts" code))
        (items (tssym/tsOutlineItems s syms))
        (receipt (tssym/tsOutlineReceipt! "test.ts" "typescript" code))]
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

fn testBasicTsConstructs! -> Bool
  (let [(code "function greet<T>(val: T): T {\n  return val;\n}\nclass Greeter {\n  public sayHello(): string {\n    return \"hello\";\n  }\n}\ninterface Config {\n  name: string;\n}\nenum Status {\n  Active,\n  Inactive\n}\nnamespace Utils {\n  export function helper(): void {}\n}\ntype StringOrNumber = string | number;\nconst count: number = 42;\n")
        (syms (tssym/extractSymbols! code))
        (greetSym (tssym/findSymbol syms "greet"))
        (greeterSym (tssym/findSymbol syms "Greeter"))
        (sayHelloSym (tssym/findSymbol syms "sayHello"))
        (configSym (tssym/findSymbol syms "Config"))
        (statusSym (tssym/findSymbol syms "Status"))
        (utilsSym (tssym/findSymbol syms "Utils"))
        (aliasSym (tssym/findSymbol syms "StringOrNumber"))
        (countSym (tssym/findSymbol syms "count"))]
    (do
      (assert (= (listLength syms) 9) "extracted 9 symbols from basic TS constructs")
      (assert (some? greetSym) "found greet symbol")
      (assert (some? greeterSym) "found Greeter symbol")
      (assert (some? sayHelloSym) "found sayHello symbol")
      (assert (some? configSym) "found Config symbol")
      (assert (some? statusSym) "found Status symbol")
      (assert (some? utilsSym) "found Utils symbol")
      (assert (some? aliasSym) "found StringOrNumber symbol")
      (assert (some? countSym) "found count symbol")
      (assert (= (tssym/tsSymbolKind (optionOr greetSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "function") "greet is function")
      (assert (= (tssym/tsSymbolKind (optionOr greeterSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "class") "Greeter is class")
      (assert (= (tssym/tsSymbolKind (optionOr sayHelloSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "method") "sayHello is method")
      (assert (= (tssym/tsSymbolKind (optionOr configSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "interface") "Config is interface")
      (assert (= (tssym/tsSymbolKind (optionOr statusSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "interface") "Status is interface")
      (assert (= (tssym/tsSymbolKind (optionOr utilsSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "interface") "Utils is interface")
      (assert (= (tssym/tsSymbolKind (optionOr aliasSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "type") "StringOrNumber is type")
      (assert (= (tssym/tsSymbolKind (optionOr countSym (tssym/makeTsSymbol "" "" 0 0 0 0 0 ""))) "variable") "count is variable")
      true))

fn ! runTests -> Bool
  (do
    (assert (testSymbolQueries!) "testSymbolQueries passes")
    (assert (testBasicTsConstructs!) "testBasicTsConstructs passes")
    true)
