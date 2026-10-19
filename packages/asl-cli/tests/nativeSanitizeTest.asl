(module asl-cli/tests/nativeSanitizeTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/asl1Cache :a cache)
      (asl/packages/asl-cli/src/nativeBuild :a nb)
      (tools/fleet/run :a run)])


fn uafFixture -> String
  (stringJoin (list
    "declare ptr @malloc(i64)"
    "declare void @free(ptr)"
    ""
    "define i32 @main() #0 {"
    "entry:"
    "  %p = call ptr @malloc(i64 8)"
    "  call void @free(ptr %p)"
    "  store i64 42, ptr %p"
    "  ret i32 0"
    "}"
    ""
    "attributes #0 = { sanitize_address noinline optnone }"
    "") "\n")

fn ! runOf argv: (List String) cwd: String -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv (list))) (run/limits 60 16))

fn ! okMsg r: (Result String String) label: String -> Bool
  (mt r
    ((ok _) true)
    ((err e) (do (eprintln (str label ": " e)) false)))

fn cliFixtureSource -> String
  (stringJoin (list
    "(module tests/acceptance/sanBuildFixture :x [main] :i [])"
    ""
    "fn main args: (List String) -> (Result Int64 String)"
    "  (ok 0)"
    "") "\n")

; (:m :ref HL-FIX3 :do "end-to-end gate for the ASan runtime wired into bin/asl build's own link step (build.asl effectiveLibAndFlags!/variantLib!): builds the same tiny .asl program twice through the real CLI, once plain and once under the flag, and checks the resulting Mach-O binary's own symbol table rather than tripping real UB (nm's __asan family only ever appears when clang actually linked against an ASan-instrumented runtime with -fsanitize=address)")
; (:m :ref SANITIZE-CONFIG :do "the ASan build is selected by :native (:rc :asan) in the .asl.config.asn above the source; the retired ASL_NATIVE_SANITIZE=1 is passed to one build only to prove it is no longer read")
fn ! cliBuild! bin: String src: String out: String cwd: String env: (List String) -> run/Done
  (run/runOneLimited (run/job (list bin "build" src "-o" out) cwd (run/childEnv env)) (run/limits 240 24))

; (:m :ref RC-DEFAULT :do "the work dir (fixtures, binaries, dSYM bundles, the ASan runtime cache) is removed in the let, before the asserts, so a failing run leaves nothing behind")
fn ! removeAll! path: String -> (Result Unit String)
  (mt (dirList path)
    ((err _) (pathRemove path))
    ((ok names) (do (map (fn [(n String)] -> (Result Unit String) (removeAll! (str path "/" n))) names)
                    (pathRemove path))))

fn ! nmOutput! path: String -> String
  (runOf (list "/usr/bin/nm" path) (sys/parentOf path)).out

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/nativeSanitizeTest." (stringFromInt64 (procSelf))))
        (made (dirCreate work))
        (ll (str work "/uaf.ll"))
        (wrote (fileWrite ll (uafFixture)))
        (plainLib (str root "/asl/host/out/libaslrt.a"))
        (clang (optionOr (envGet "CLANG") "clang"))
        (ctx (sys/Context :root root :scriptDir "" :argv0 "" :hostBin ""))
        (asl1R (cache/nativeAsl1! ctx plainLib clang))
        (asl1 (resultOr asl1R ""))
        (b (nb/Build :root root :cache work :tmp work :lib plainLib :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 900000000000) :maxDesc 16))
        (asanLibR (nb/asanRuntime! b asl1 (str root "/asl/packages")))
        (asanLib (resultOr asanLibR ""))
        (asanLibAgainR (nb/asanRuntime! b asl1 (str root "/asl/packages")))
        (asanLibAgain (resultOr asanLibAgainR ""))
        (plainOut (str work "/uafPlain"))
        (asanOut (str work "/uafAsan"))
        (plainLinkedR (nb/linkSanitized! b ll plainLib plainOut false))
        (asanLinkedR (nb/linkSanitized! b ll asanLib asanOut true))
        (plainRan (runOf (list plainOut) work))
        (asanRan (runOf (list asanOut) work))
        (cleaned (sys/isFile? plainLib))
        (bin (str root "/bin/asl"))
        (cliSrc (str work "/sanBuildFixture.asl"))
        (cliWrote (fileWrite cliSrc (cliFixtureSource)))
        (asanDir (str work "/asanConfig"))
        (asanDirMade (dirCreate asanDir))
        (asanConfigWrote (fileWrite (str asanDir "/.asl.config.asn") "(:aslConfig :native (:rc :asan))"))
        (cliAsanSrc (str asanDir "/sanBuildFixture.asl"))
        (cliAsanWrote (fileWrite cliAsanSrc (cliFixtureSource)))
        (cliPlainOut (str work "/sanCliPlain"))
        (cliEnvOut (str work "/sanCliEnv"))
        (cliAsanOut (str work "/sanCliAsan"))
        (cliPlainBuild (cliBuild! bin cliSrc cliPlainOut work (list)))
        (cliEnvBuild (cliBuild! bin cliSrc cliEnvOut work (list "ASL_NATIVE_SANITIZE=1")))
        (cliAsanBuild (cliBuild! bin cliAsanSrc cliAsanOut asanDir (list)))
        (cliPlainNm (if (= cliPlainBuild.exit 0) (nmOutput! cliPlainOut) ""))
        (cliAsanNm (if (= cliAsanBuild.exit 0) (nmOutput! cliAsanOut) ""))
        (cliEnvNm (if (= cliEnvBuild.exit 0) (nmOutput! cliEnvOut) ""))
        (asanLibBuilt (sys/isFile? asanLib))
        (swept (removeAll! work))]
    (do
        (assert (ok? made) (str "the work directory " work " was created"))
        (assert (ok? wrote) "the UAF fixture .ll was written")
        (assert (sys/isFile? plainLib) (str plainLib " exists (built by asl/host/build.sh before this test runs)"))
        (assert (okMsg asl1R "a native asl1 compiler (cache/nativeAsl1!) is available") "native asl1 compiler")
        (assert (okMsg asanLibR "nb/asanRuntime! builds the ASan-instrumented runtime archive") "asan runtime built")
        (assert asanLibBuilt (str "the built ASan runtime archive exists at " asanLib))
        (assert (not (= asanLib plainLib)) "the ASan runtime archive is a distinct file from the plain runtime archive (no cache collision)")
        (assert (okMsg asanLibAgainR "a second nb/asanRuntime! call") "asan runtime cache reuse")
        (assert (= asanLib asanLibAgain) "a second nb/asanRuntime! call for the same sources and flag reuses the same cache entry")
        (assert (okMsg plainLinkedR "linking the fixture with the plain runtime") "plain link")
        (assert (okMsg asanLinkedR "linking the fixture with the ASan runtime") "asan link")
        (assert (= plainRan.exit 0) (str "without the sanitize mode, the use-after-free is undefined behaviour that exits 0: got " (stringFromInt64 plainRan.exit) " " plainRan.out))
        (refute (stringContains? plainRan.out "AddressSanitizer") (str "the plain build reports no sanitizer: " plainRan.out))
        (assert (!= asanRan.exit 0) (str "under the sanitize mode, the heap-use-after-free aborts: got exit " (stringFromInt64 asanRan.exit)))
        (assert (stringContains? asanRan.out "AddressSanitizer") (str "the sanitized build's ASan report names the sanitizer: " asanRan.out))
        (assert (stringContains? asanRan.out "heap-use-after-free") (str "the sanitized build's ASan report names the bug class: " asanRan.out))
        (assert cleaned "the plain runtime archive was not disturbed by building the ASan one")
        (assert (ok? cliWrote) "the bin/asl build CLI fixture source was written")
        (assert (and (ok? asanDirMade) (and (ok? asanConfigWrote) (ok? cliAsanWrote))) "the :rc :asan fixture directory, config and source were written")
        (assert (= cliPlainBuild.exit 0) (str "bin/asl build succeeds without :native :rc: " cliPlainBuild.out))
        (assert (= cliEnvBuild.exit 0) (str "bin/asl build succeeds with the retired ASL_NATIVE_SANITIZE=1 in its env: " cliEnvBuild.out))
        (assert (= cliAsanBuild.exit 0) (str "bin/asl build succeeds under :native (:rc :asan): " cliAsanBuild.out))
        (refute (stringContains? cliPlainNm "__asan") (str "the plain bin/asl build binary carries no __asan symbols: " cliPlainNm))
        (refute (stringContains? cliEnvNm "__asan") (str "ASL_NATIVE_SANITIZE=1 is no longer read: the env alone links a plain binary: " cliEnvNm))
        (assert (stringContains? cliAsanNm "__asan") (str "bin/asl build -o under :native (:rc :asan) links an ASan-instrumented binary (nm shows __asan symbols): " cliAsanNm))
        (assert (ok? swept) (str "the work directory " work " is removed before any assertion can fail"))
        true))
