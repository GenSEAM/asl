(module asl-target-js/tests/dtsTest
  :x [runTests]
  :i [(asl-ir/types :a ty) (asl-target-js/main :a js) (tools/fleet/run :a run)])

(schema SplitOut (:f exitCode Int64) (:f stdout String) (:f stderr String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! sh! root: String argv: (List String) timeoutS: Int64 maxDesc: Int64 -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits timeoutS maxDesc))

fn ! splitSh! root: String cmd: String errFile: String timeoutS: Int64 maxDesc: Int64 -> SplitOut
  (let [(d (sh! root (list "/bin/sh" "-c" (str cmd " 2>" (shellQuote errFile))) timeoutS maxDesc))
        (e (resultOr (fileReadString errFile) ""))]
    (SplitOut :exitCode d.exit :stdout d.out :stderr e))

fn consumer -> String
  (stringJoin
    ["import { area, firstOr, mapBoth, describe, origin, label, asl, type Shape, type Pt } from './typed.mjs';"
     "import * as m from './typed.mjs';"
     "const sq: Shape = asl.variant<Shape>('square', 5n);"
     "const xs = asl.list(1n, 2n, 3n);"
     "const strs = mapBoth((n: bigint) => `#${n}`, xs);"
     "const p: Pt = asl.record<Pt>('jsFixtures/typed.Pt', { x: 2n, y: 5n });"
     "const lab = label(sq);"
     "const big: boolean = m['isBig?'](sq);"
     "const first: bigint = firstOr(xs, 0n);"
     "console.log(area(sq), first, asl.toArray(strs).join(','), describe(p), describe(origin()), lab.name === 'some' ? lab.fields[0] : '-', big);"]
    "\n")

fn misuse -> String
  (stringJoin ["import { area, describe } from './typed.mjs';" "area('square');" "describe({ x: 1, y: 2 });"] "\n")

fn ! tool! name: String -> String
  (stringTrim (sh! "." (list "/bin/sh" "-c" (str "command -v " name " 2>/dev/null")) 10 8).out)

fn tscFlags -> String
  " --noEmit --strict --module nodenext --moduleResolution nodenext --target es2022 "

fn ! runTests -> Bool
  (let [(work "/tmp/asl-target-js-dts")
        (built (js/compileWithTypes! "asl/packages/asl-target-js/tests/fixtures/typed.asl"))
        (types (mt built ((ok b) (pairSecond b)) ((err _) "")))]
    (do
      (assert (ok? built) (str "typed fixture compiles with declarations: " (mt built ((ok _) "ok") ((err ds) (js/diagText ds)))))
      (assert (stringContains? types "export interface Pt {\n  readonly x: bigint;\n  readonly y: bigint;\n}") "a schema becomes a readonly interface with bigint Int fields")
      (assert (stringContains? types "| { readonly name: \"circle\"; readonly fields: readonly [bigint] }") "an enum becomes a union tagged by variant name")
      (assert (stringContains? types "export declare function firstOr<T>(xs: AslList<T>, fallback: T): T;") "type variables become generics")
      (assert (stringContains? types "export declare function label(s: Shape): AslOption<string>;") "Option maps to AslOption")
      (assert (stringContains? types "export { asl$isBig$63 as \"isBig?\" };") "a name that is not a JS identifier is exported under its ASL name")
      (sh! "." (list "/bin/sh" "-c" (str "rm -rf " work " && mkdir -p " work)) 15 8)
      (assert (ok? (fileWrite (str work "/typed.mjs") (mt built ((ok b) (pairFirst b)) ((err _) "")))) "writes the module")
      (assert (ok? (fileWrite (str work "/typed.d.mts") types)) "writes the declarations")
      (assert (ok? (fileWrite (str work "/use.mts") (consumer))) "writes a TypeScript consumer")
      (assert (ok? (fileWrite (str work "/bad.mts") (misuse))) "writes a misuse")
      (let [(tsc (tool! "tsc")) (node (tool! "node"))]
        (if (stringEmpty? tsc)
          (do (eprintln "dtsTest: tsc not on PATH; the declaration text was checked, the TypeScript compile was not") true)
          (let [(good (splitSh! work (str (shellQuote tsc) (tscFlags) "use.mts") (str work "/good.stderr") 60 32))
                (bad (splitSh! work (str (shellQuote tsc) (tscFlags) "bad.mts") (str work "/bad.stderr") 60 32))
                (ran (splitSh! work (str (shellQuote node) " --experimental-strip-types --no-warnings use.mts") (str work "/ran.stderr") 20 16))]
            (do
              (assert (= good.exitCode 0) (str "a correct consumer passes tsc --strict: " good.stdout good.stderr))
              (assert (not (= bad.exitCode 0)) "a consumer passing a string for a Shape fails tsc")
              (assert (stringContains? bad.stdout "Type 'number' is not assignable to type 'bigint'") (str "an Int field rejects a JS number: " bad.stdout))
              (assert (= ran.stdout "25n 1n #1,#2,#3 (2, 5) (0, 0) big true\n") (str "the consumer runs against the compiled module: " ran.stdout ran.stderr))
              true))))))
