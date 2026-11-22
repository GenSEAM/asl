(module asl-cli/tests/nativeColdFixture
  :x [coldBuildS sharedCliCache! upstreamText adoptFrom! adopted?]
  :i [(asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref FORMS-PINNED-CLI :do "the seconds a test lets a scratch checkout build its native CLI from cold: 18 min on a quiet node2 and more than 25 under load, so 5400; relayPinTest and formsPinTest both read it, a shorter literal in either killed the build and left no head")
fn coldBuildS -> Int64
  5400

; (:m :ref TRAIN-SUITES-COLD-CLI :do "the native CLI store this run already has: as nativeCli cacheDir! resolves it; a scratch cache names it read-only upstream, so only what the test's claim needs is built")
fn ! sharedCliCache! -> String
  (nc/cacheDir!)

fn upstreamText dir: String take: (List String) -> String
  (str "(:upstream :dir \"" dir "\" :take (" (stringJoin take " ") "))\n")

; (:m :ref TRAIN-SUITES-COLD-CLI :do "make the scratch cache and write its upstream.asn naming the shared store and the entry kinds (seed rt asl1 cli) it may copy instead of building; nothing is written upstream")
fn ! adoptFrom! cache: String take: (List String) -> Bool
  (let [(_ (dirCreate cache))] (ok? (fileWrite (str cache "/upstream.asn") (upstreamText (sharedCliCache!) take))))

; (:m :ref TRAIN-SUITES-COLD-CLI :do "the build output says it copied the entry of this kind from upstream")
fn adopted? out: String kind: String -> Bool
  (stringContains? out (str "(:adopt :entry " kind "-"))
