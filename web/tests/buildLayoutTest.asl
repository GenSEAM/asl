(module aslSite/tests/buildLayoutTest
  :x [runTests]
  :i [(aslSite/tools/build :a build)])

; (:m :ref SITE-BUILD-EXPORT-LAYOUT :do "the build picks its path prefix from where its own file sits: asl/web in the workspace, web in the exported repo")
fn ! fixture! -> String
  (stringTrim (processRun "mktemp -d /tmp/siteBuildLayout.XXXXXX").stdout)

fn ! plant! base: String rel: String -> Bool
  (= (processRun (str "mkdir -p '" base "/" rel "' && : > '" base "/" rel "/build.asl'")).exitCode 0)

fn ! runTests -> Bool
  (let [(root (fixture!))
        (workspace (str root "/workspace"))
        (exported (str root "/exported"))
        (empty (str root "/empty"))
        (made (and (not (stringEmpty? root)) (and (plant! workspace "asl/web/tools") (and (plant! exported "web/tools") (= (processRun (str "mkdir -p '" empty "'")).exitCode 0)))))
        (inWorkspace (build/prefixIn! workspace))
        (inExported (build/prefixIn! exported))
        (inEmpty (build/prefixIn! empty))
        (cleaned (if (stringStartsWith? root "/") (processRun (str "rm -rf '" root "'")).exitCode 1))]
    (do
      (assert made "the layout fixtures are created")
      (assert (= inWorkspace (some "asl/")) "under the workspace root the build's file is asl/web/tools/build.asl, so paths take the asl/ prefix")
      (assert (= inExported (some "")) "under the exported repo root the build's file is web/tools/build.asl, so paths take no prefix")
      (assert (= inEmpty (none)) "a directory that holds neither layout is refused instead of guessed")
      (assert (= (build/layoutPrefix true true) (some "asl/")) "the workspace layout wins when both files exist")
      (assert (= (build/webDir "") "web") "the exported site root is web")
      (assert (= (build/distDir "") "web/dist") "the exported output is web/dist, the directory wrangler.toml publishes")
      (assert (= (build/webDir "asl/") "asl/web") "the workspace site root is asl/web")
      (assert (= (build/distDir "asl/") "asl/web/dist") "the workspace output is asl/web/dist")
      (assert (= cleaned 0) "the fixture is removed")
      true))
