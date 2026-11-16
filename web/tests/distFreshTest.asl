(module aslSite/tests/distFreshTest
  :x [runTests]
  :i [(aslSite/tools/build :a build)])

fn ! runTests -> Bool
  (let [(prefix (optionOr (build/prefixIn! ".") "missing/"))
        (recorded (resultOr (fileReadString (str (build/distDir prefix) "/build.asn")) ""))
        (digest (build/sourceDigest! prefix))]
    (do
      (assert (= (stringLength digest) 64) "the site sources hash to one digest")
      (assert (stringContains? recorded (str ":sources \"" digest "\"")) "the committed web/dist was built from the current site sources; rebuild with asl run asl/web/tools/build.asl and commit web/dist")
      true))
