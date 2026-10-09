(module asl-parser/astNativeBuildTest :x [runTests] :i [])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))
        (built (sh (str "asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl build asl/packages/asl-parser/fixtures/nativeAstSuites.asl -o " work "/ast.ll")))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (= built.exitCode 0) (str "asl1 builds the ast suites natively: exit " built.exitCode "; " built.stderr))
        (let [(linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " work "/ast.ll -x none asl/host/out/libaslrt.a -lm -o " work "/ast")))]
          (assert (= linked.exitCode 0) (str "clang links the ast suites: " linked.stderr)))
        (let [(ran (sh (str work "/ast")))]
          (assert (= ran.exitCode 42) (str "the native ast suites pass and exit 42, got " ran.exitCode "; " ran.stderr)))
        (sh (str "rm -rf " work))
        true))
