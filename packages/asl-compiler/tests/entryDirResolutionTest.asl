(module asl-compiler/entryDirResolutionTest :x [runTests] :i [(asl-compiler/compiler :a comp)])

fn helperSource pkg: String -> String
  (str "(module " pkg "/helper :x [seven])\n\n(fn seven [] -> Int64 7)\n")

fn mainSource -> String
  "(module p1/main :x [main] :i [(helper :a h)])\n\n(fn main [] -> Int64 (h/seven))\n"

fn ! writeWorkspace! dir: String -> Bool
  (and (= (processRun (str "mkdir -p " dir "/p1/src " dir "/p2/src")).exitCode 0)
       (and (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig)\n"))
       (and (ok? (fileWrite (str dir "/p1/manifest.asn") "(:package p1)\n"))
       (and (ok? (fileWrite (str dir "/p2/manifest.asn") "(:package p2)\n"))
       (and (ok? (fileWrite (str dir "/p1/src/helper.asl") (helperSource "p1")))
       (and (ok? (fileWrite (str dir "/p2/src/helper.asl") (helperSource "p2")))
            (ok? (fileWrite (str dir "/p1/src/main.asl") (mainSource)))))))))

fn unresolved diags: (List String) -> Bool
  (listAny? (fn [(d String)] -> Bool (or (stringContains? d "unresolved") (stringContains? d "no module helper"))) diags)

fn ! testC99ResolvesFromEntryDir dir: String -> Bool
  (mt (comp/compilePackageToC99! (str dir "/p1/src/main.asl") (list dir) false)
    ((err e) (do (assert false (str "compilePackageToC99! returns a result: " e)) false))
    ((ok cr) (do (refute (unresolved cr.diagnostics) (str "the C99 path resolves helper in p1: " (stringJoin cr.diagnostics "; ")))
                 (assert cr.ok (str "the C99 path compiles the entry: " (stringJoin cr.diagnostics "; ")))
                 true)))

fn ! testLlvmResolvesFromEntryDir dir: String -> Bool
  (mt (comp/compilePackageToLlvm! (str dir "/p1/src/main.asl") (list dir))
    ((err e) (do (assert false (str "compilePackageToLlvm! returns a result: " e)) false))
    ((ok cr) (do (refute (unresolved cr.diagnostics) (str "the LLVM path resolves helper in p1: " (stringJoin cr.diagnostics "; ")))
                 (assert cr.ok (str "the LLVM path compiles and links the entry: " (stringJoin cr.diagnostics "; ")))
                 (assert (stringContains? cr.code "p1$2Fhelper") (str "the linked module is p1's helper: " cr.code))
                 true)))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a workspace directory")
        (assert (writeWorkspace! dir) "workspace written")
        (testC99ResolvesFromEntryDir dir)
        (testLlvmResolvesFromEntryDir dir)
        (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "workspace removed")
        true))
