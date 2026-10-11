(module asl-syntax/tests/ts/declTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/ts/types :a ts)
      (asl-syntax/ts/decl :a decl)])

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

fn checkDeclRoundTrip! code: String -> Bool
  (let [(res (decl/parse code))]
    (do
      (mt res
        ((ok _) ())
        ((err msg)
         (println (str "PARSE ERROR: " msg " FOR: " code))))
      (assert (ok? res) (str "decl/parse succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= printed code)
            (println (str "ROUNDTRIP MISMATCH: GOT [" printed "] EXPECTED [" code "]"))
            ())
          (assert (= printed code) (str "decl round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "decl tiling exact: " code))
          (assert (not (treeHasError? root)) (str "no error nodes in parse tree: " code))
          true))))

fn testInterfaces! -> Bool
  (do
    (checkDeclRoundTrip! "interface Point { x: number; y: number; }")
    (checkDeclRoundTrip! "interface User { readonly id: number; name?: string; }")
    (checkDeclRoundTrip! "interface Container<T, U = string> { item: T; extra: U; }")
    (checkDeclRoundTrip! "interface Square extends Shape { side: number; }")
    (checkDeclRoundTrip! "interface Employee extends Person, Identifiable { salary: number; }")
    (checkDeclRoundTrip! "interface Callable { (x: number): string; }")
    (checkDeclRoundTrip! "interface Constructor { new (s: string): Point; }")
    (checkDeclRoundTrip! "interface Greeter { greet<T>(val: T): string; }")
    (checkDeclRoundTrip! "interface Dict { [key: string]: any; readonly [idx: number]: string; }")
    (checkDeclRoundTrip! "interface Mixed { a: number, b: string; c: boolean\n d: any }")
    true)

fn testTypeAliases! -> Bool
  (do
    (checkDeclRoundTrip! "type Str = string;")
    (checkDeclRoundTrip! "type ID = string | number;")
    (checkDeclRoundTrip! "type Combined = A & B;")
    (checkDeclRoundTrip! "type Nullable<T> = T | null;")
    (checkDeclRoundTrip! "type Pair<A, B> = [A, B];")
    (checkDeclRoundTrip! "type Config = { host: string; port: number; };")
    (checkDeclRoundTrip! "type Callback<T> = (data: T) => void;")
    true)

fn testEnums! -> Bool
  (do
    (checkDeclRoundTrip! "enum Direction { Up, Down, Left, Right }")
    (checkDeclRoundTrip! "enum Status { Active = 1, Inactive = 0, Pending = 2 }")
    (checkDeclRoundTrip! "enum Color { Red = \"RED\", Green = \"GREEN\", Blue = \"BLUE\" }")
    (checkDeclRoundTrip! "const enum Mode { Fast = 1, Slow = 2 }")
    (checkDeclRoundTrip! "declare enum Ambient { X, Y }")
    (checkDeclRoundTrip! "declare const enum AmbientConst { A = 1, B = 2 }")
    (checkDeclRoundTrip! "enum Trailing { A, B, }")
    true)

fn testNamespacesAndModules! -> Bool
  (do
    (checkDeclRoundTrip! "namespace MathUtils {\n  export const PI = 3.14;\n}")
    (checkDeclRoundTrip! "namespace App.Services.Auth {\n  export interface Session { token: string; }\n}")
    (checkDeclRoundTrip! "module Utils {\n  export function helper(): void {}\n}")
    (checkDeclRoundTrip! "declare module \"my-lib\" {\n  export function run(): void;\n}")
    (checkDeclRoundTrip! "declare global {\n  interface Window { custom: any; }\n}")
    true)

fn testDeclare! -> Bool
  (do
    (checkDeclRoundTrip! "declare var a: number;")
    (checkDeclRoundTrip! "declare let b: string;")
    (checkDeclRoundTrip! "declare const c: boolean;")
    (checkDeclRoundTrip! "declare function setTimeout(handler: Function, timeout?: number): number;")
    (checkDeclRoundTrip! "declare class Worker {\n  constructor(url: string);\n  postMessage(msg: any): void;\n}")
    (checkDeclRoundTrip! "declare abstract class BaseHandler {\n  abstract handle(): void;\n}")
    (checkDeclRoundTrip! "declare type Callback = () => void;")
    (checkDeclRoundTrip! "declare interface WindowEnv { env: string; }")
    true)

fn testClassesAndModifiers! -> Bool
  (do
    (checkDeclRoundTrip! "class Dog extends Animal implements Pet, CanBark {\n  bark(): string { return \"woof\"; }\n}")
    (checkDeclRoundTrip! "class Stack<T> {\n  private items: T[] = [];\n  push(item: T): void {}\n}")
    (checkDeclRoundTrip! "class User {\n  public static readonly ROLE: string = \"user\";\n  private id: number;\n  protected name: string;\n  public readonly email: string;\n}")
    (checkDeclRoundTrip! "abstract class Shape {\n  abstract getArea(): number;\n  abstract readonly name: string;\n  describe(): string { return \"Shape\"; }\n}")
    (checkDeclRoundTrip! "class Point3D {\n  constructor(public x: number, public readonly y: number, protected z: number = 0, private label?: string) {}\n}")
    (checkDeclRoundTrip! "class Component {\n  element!: HTMLElement;\n  config?: Config;\n}")
    (checkDeclRoundTrip! "class Bank {\n  #balance: number = 0;\n  get balance(): number { return this.#balance; }\n}")
    (checkDeclRoundTrip! "class StringMap {\n  [key: string]: string;\n}")
    (checkDeclRoundTrip! "class ReadonlyReg {\n  readonly [i: number]: any;\n}")
    (checkDeclRoundTrip! "class Person {\n  private _age: number = 0;\n  get age(): number { return this._age; }\n  set age(v: number) { this._age = v; }\n  accessor status: string = \"idle\";\n}")
    true)

fn testOverloads! -> Bool
  (do
    (checkDeclRoundTrip! "function format(val: number): string;\nfunction format(val: string): string;\nfunction format(val: any): string {\n  return String(val);\n}")
    (checkDeclRoundTrip! "class Calc {\n  add(a: number, b: number): number;\n  add(a: string, b: string): string;\n  add(a: any, b: any): any { return a + b; }\n}")
    (checkDeclRoundTrip! "class Buffer {\n  constructor(size: number);\n  constructor(str: string);\n  constructor(arg: any) {}\n}")
    true)

fn testDecorators! -> Bool
  (do
    (checkDeclRoundTrip! "@sealed\n@log\nclass Entity {}")
    (checkDeclRoundTrip! "class Service {\n  @log\n  run() {}\n}")
    (checkDeclRoundTrip! "class State {\n  @observable\n  count: number = 0;\n}")
    (checkDeclRoundTrip! "class Box {\n  @enumerable\n  get size() { return 1; }\n}")
    (checkDeclRoundTrip! "class Ctr {\n  constructor(@inject(\"cfg\") cfg: any) {}\n}")
    (checkDeclRoundTrip! "@Component({ tag: \"my-app\" })\nexport class MyApp {}")
    true)

fn testImportsAndExports! -> Bool
  (do
    (checkDeclRoundTrip! "import type { User, Role as UserRole } from \"./user\";")
    (checkDeclRoundTrip! "import type DefaultUser from \"./user\";")
    (checkDeclRoundTrip! "import type * as Types from \"./types\";")
    (checkDeclRoundTrip! "import { type A, B, type C as D } from \"./mixed\";")
    (checkDeclRoundTrip! "import fs = require(\"fs\");")
    (checkDeclRoundTrip! "export type { User, Role };")
    (checkDeclRoundTrip! "export type { Action } from \"./actions\";")
    (checkDeclRoundTrip! "export { type Reducer, createStore } from \"./store\";")
    (checkDeclRoundTrip! "export = Express;")
    (checkDeclRoundTrip! "export as namespace MyGlobalLib;")
    (checkDeclRoundTrip! "export interface Options { timeout: number; }")
    (checkDeclRoundTrip! "export type ActionType = \"ADD\" | \"REMOVE\";")
    (checkDeclRoundTrip! "export enum LogLevel { DEBUG, INFO }")
    (checkDeclRoundTrip! "export namespace Utils { export const v = 1; }")
    (checkDeclRoundTrip! "export default interface Plugin { name: string; }")
    (checkDeclRoundTrip! "export default abstract class BaseView {}")
    true)

fn findFirstNode elems: (List tr/TreeElement) -> tr/Node
  (if (listEmpty? elems)
    (tr/makeErrorNode 0 0 (list))
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode n) n)
        ((tr/elemToken _) (findFirstNode tl)))))

fn testDeclHelpers -> Bool
  (let [(code "interface Point { x: number; }")
        (res (decl/parse code))
        (root (resultOr res (tr/makeErrorNode 0 0 (list))))
        (kids (tr/nodeChildren root))
        (iface (findFirstNode kids))
        (resType (decl/parse "type ID = string;"))
        (typeNode (findFirstNode (tr/nodeChildren (resultOr resType (tr/makeErrorNode 0 0 (list))))))
        (resEnum (decl/parse "enum Color { Red }"))
        (enumNode (findFirstNode (tr/nodeChildren (resultOr resEnum (tr/makeErrorNode 0 0 (list))))))
        (resClass (decl/parse "class User {}"))
        (classNode (findFirstNode (tr/nodeChildren (resultOr resClass (tr/makeErrorNode 0 0 (list))))))
        (resFn (decl/parse "function greet(): void {}"))
        (fnNode (findFirstNode (tr/nodeChildren (resultOr resFn (tr/makeErrorNode 0 0 (list))))))
        (resNs (decl/parse "namespace App {}"))
        (nsNode (findFirstNode (tr/nodeChildren (resultOr resNs (tr/makeErrorNode 0 0 (list))))))]
    (do
      (assert (decl/isDeclNode root) "root is decl node")
      (assert (= (decl/declKind root) "module") "root kind is module")
      (assert (= (decl/declToSExpr root code) "(module (interface Point))") "module s-expr")
      (assert (decl/isDeclNode iface) "iface is decl node")
      (assert (= (decl/declKind iface) "interfaceDecl") "iface kind is interfaceDecl")
      (assert (= (decl/declToSExpr iface code) "(interface Point)") "iface s-expr")
      (assert (= (decl/declToSExpr typeNode "type ID = string;") "(type ID)") "type s-expr")
      (assert (= (decl/declToSExpr enumNode "enum Color { Red }") "(enum Color)") "enum s-expr")
      (assert (= (decl/declToSExpr classNode "class User {}") "(class User)") "class s-expr")
      (assert (= (decl/declToSExpr fnNode "function greet(): void {}") "(function greet)") "fn s-expr")
      (assert (= (decl/declToSExpr nsNode "namespace App {}") "(namespace App)") "ns s-expr")
      true))

fn testTypeScriptConformanceSubset! -> Bool
  (do
    (checkDeclRoundTrip! "import { EventEmitter } from \"events\";\n\nexport interface ServerConfig {\n  host: string;\n  port: number;\n  ssl?: boolean;\n}\n\nexport type RouteHandler<TReq, TRes> = (req: TReq, res: TRes) => Promise<void>;\n\nexport const enum HttpStatus {\n  OK = 200,\n  NotFound = 404,\n  InternalError = 500,\n}\n\nexport abstract class AbstractServer extends EventEmitter {\n  protected readonly config: ServerConfig;\n  private isRunning: boolean = false;\n\n  constructor(config: ServerConfig) {\n    super();\n    this.config = config;\n  }\n\n  abstract start(): Promise<void>;\n  abstract stop(): Promise<void>;\n\n  get running(): boolean {\n    return this.isRunning;\n  }\n}\n")
    (checkDeclRoundTrip! "namespace Diagnostics.Tracing {\n  export interface SpanContext {\n    traceId: string;\n    spanId: string;\n  }\n\n  export class Tracer {\n    startSpan(name: string): SpanContext {\n      return { traceId: \"t1\", spanId: \"s1\" };\n    }\n  }\n}\n")
    true)


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
        (parseRes (decl/parse content))]
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

fn testUpstreamBabelTs! -> Bool
  (checkBabelTsSuite! "babel-ts" (upstreamBabelFiles) (upstreamBabelExclusions) 0 0 0)

fn ! runTests -> Bool
  (do
    (testDeclHelpers)
    (testInterfaces!)
    (testTypeAliases!)
    (testEnums!)
    (testNamespacesAndModules!)
    (testDeclare!)
    (testClassesAndModifiers!)
    (testOverloads!)
    (testDecorators!)
    (testImportsAndExports!)
    (testTypeScriptConformanceSubset!)
    (assert (testUpstreamBabelTs!) "upstream babel-ts conformance suite")
    true)
