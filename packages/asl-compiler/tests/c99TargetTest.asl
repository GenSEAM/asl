(module asl/packages/asl-compiler/tests/c99TargetTest :x [testC99CompilerTargetInvariants testC99CliBuildTarget! testC99ManifestAndGrammarInvariants! testC99CompilerDualPolarityRefutations testC99NoDocMainSourceCompiles testC99NoDocMainPackageCompiles! runTests] :i [(../src/compiler :a comp) (../../asl-cli/src/cli :a cli)])

fn sampleMathSource -> String
  (str "(module demo/math\n" "  :x [add is-positive? main]\n" "  :i [])\n\n" "(defschema Counter\n" "  (:field count Int64 \"Counter value\"))\n\n" "(df add [(x Int64) (y Int64)] -> Int64\n" "  (+ x y))\n\n" "(df is-positive? [(n Int64)] -> Bool\n" "  (> n 0))\n\n" "(df main [] -> Int64\n" "  (add 40 2))\n")

fn testC99CompilerTargetInvariants -> Bool
  (let [(src (sampleMathSource)) (rHosted (comp/compileStandaloneTarget src "c99" "demo/math.asl")) (rFree (comp/compileSourceToC99 src "demo/math.asl" true)) (cHosted rHosted.code) (cFree rFree.code)] (assert rHosted.ok "compilation to target c99 must succeed") (assert (listEmpty? rHosted.diagnostics) "diagnostics must be empty on success") (assert (stringContains? cHosted "#include <stdint.h>") "hosted C99 contains stdint") (assert (stringContains? cHosted "struct AslCounter_s {") "hosted C99 contains struct") (assert (stringContains? cHosted "int64_t add(int64_t x, int64_t y);") "hosted C99 contains prototype") (assert (stringContains? cHosted "int64_t add(int64_t x, int64_t y) {") "hosted C99 contains def") (assert (stringContains? cHosted "return ((x) + (y));") "hosted C99 contains return expr") (assert (stringContains? cHosted "int main(int argc, char** argv) {") "hosted C99 contains main") (assert (stringContains? cHosted "return (int)asl_main();") "hosted main calls asl_main") (assert rFree.ok "freestanding C99 compilation must succeed") (assert (stringContains? cFree "void setup(void) {") "freestanding C99 contains setup") (assert (not (stringContains? cFree "<stdio.h>")) "freestanding C99 lacks stdio.h") true)

fn testC99CliBuildTarget! -> Bool
  (let [(res (cli/dispatchCmd "build" (list "--target" "c99" "tests/acceptance/d81/ResolutionSample.asl")))] (mt res ((err msg) (assert false (str "build --target c99 failed: " msg))) ((ok stdout) (do (assert (stringContains? stdout "#include <stdint.h>") "build output contains C99 headers") (assert (stringContains? stdout "asl_string_t") "build output contains asl_string_t") (assert (stringContains? stdout "sampleIdentityValue") "build output contains function") true))))

fn testC99ManifestAndGrammarInvariants! -> Bool
  (let [(mRes (fileRead "asl/packages/asl-codegen/manifest.asn")) (tRes (fileRead "asl/packages/asl-codegen/src/c99Type.asl")) (mgRes (fileRead "asl/packages/asl-codegen/src/c99Mangle.asl")) (eRes (fileRead "asl/packages/asl-codegen/src/c99Expr.asl")) (emRes (fileRead "asl/packages/asl-codegen/src/emitC.asl"))] (mt mRes ((err mErr) (assert false (str "Failed to read manifest.asn: " mErr))) ((ok mSrc) (do (assert (stringContains? mSrc "asl-codegen/c99Type") "manifest declares c99Type") (assert (stringContains? mSrc "asl-codegen/c99Mangle") "manifest declares c99Mangle") (assert (stringContains? mSrc "asl-codegen/c99Expr") "manifest declares c99Expr") (assert (stringContains? mSrc "asl-codegen/c99Emit") "manifest declares c99Emit")))) (mt mgRes ((err gErr) (assert false (str "Failed to read c99Mangle.asl: " gErr))) ((ok gSrc) (assert (stringContains? gSrc "mangleCIdent") "c99Mangle declares mangleCIdent"))) (mt tRes ((err tErr) (assert false (str "Failed to read c99Type.asl: " tErr))) ((ok tSrc) (assert (stringContains? tSrc "c99TypeStr") "c99Type declares c99TypeStr"))) (mt eRes ((err eErr) (assert false (str "Failed to read c99Expr.asl: " eErr))) ((ok eSrc) (assert (stringContains? eSrc "lowerCExpr") "c99Expr declares lowerCExpr"))) (mt emRes ((err emErr) (assert false (str "Failed to read emitC.asl: " emErr))) ((ok emSrc) (assert (stringContains? emSrc "emitCStandalone") "emitC declares emitCStandalone"))) true)

fn testC99CompilerDualPolarityRefutations -> Bool
  (let [(src (sampleMathSource)) (rC99 (comp/compileStandaloneTarget src "c99" "demo/math.asl")) (rBad (comp/compileStandaloneTarget "(df bad [] -> Int64 (+ 1))" "c99" "bad.asl"))] (refute (!= rC99.ok true) "compileStandaloneTarget c99 must not fail for valid source") (refute (= rC99.code "") "code must not be empty on success") (refute (stringContains? rC99.code "undefined") "code must not contain undefined") (refute rBad.ok "invalid arity must fail check") true)

fn noDocMainSource -> String
  (str "(module xplatNoDoc :x [main])\n\n" "fn ! main -> (Result Unit IoError)\n" "  (ok ())\n")

fn testC99NoDocMainSourceCompiles -> Bool
  (let [(src (noDocMainSource)) (r (comp/compileSourceToC99 src "xplatNoDoc.asl" false))]
    (do (assert r.ok (str "compileSourceToC99 succeeds on a no-doc main; diagnostics: " (stringJoin r.diagnostics "; ")))
        (assert (listEmpty? r.diagnostics) "no diagnostics on success")
        true))

fn ! testC99NoDocMainPackageCompiles! -> Bool
  (let [(made (processRun "mktemp -d")) (work (stringTrim made.stdout)) (path (str work "/xplatNoDoc.asl")) (written (fileWrite path (noDocMainSource)))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (ok? written) "xplatNoDoc.asl fixture written")
        (mt (comp/compilePackageToC99! path (list ".") false)
          ((err e) (assert false (str "compilePackageToC99! failed to load: " e)))
          ((ok r) (assert r.ok (str "compilePackageToC99! succeeds on a no-doc main; diagnostics: " (stringJoin r.diagnostics "; ")))))
        (assert (= (processRun (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))

fn ! runTests -> Bool
  (do (assert (testC99CompilerTargetInvariants) "testC99CompilerTargetInvariants must pass") (assert (testC99CliBuildTarget!) "testC99CliBuildTarget must pass") (assert (testC99ManifestAndGrammarInvariants!) "testC99ManifestAndGrammarInvariants must pass") (assert (testC99CompilerDualPolarityRefutations) "testC99CompilerDualPolarityRefutations must pass") (assert (testC99NoDocMainSourceCompiles) "testC99NoDocMainSourceCompiles must pass") (assert (testC99NoDocMainPackageCompiles!) "testC99NoDocMainPackageCompiles! must pass") true)
