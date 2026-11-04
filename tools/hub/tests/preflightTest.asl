(module asl-tools/hub/tests/preflightTest
  :x [runTests]
  :i [(asl-tools/hub/preflight :a pf) (asl-tools/fleet/run :a fr)])

; (:m :ref ORCH-NODE2-CUTOVER-BUG :do "the conductor's hub preflight on scratch dirs: no hub.asn passes as noHub, a hub with a client-carrying worktree passes, a hub with an old worktree is ERR_HUB_CLIENT_MISSING")
fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/preflightTest.XXXXXX" 5000) "")))
        (made (fr/shellOut (str "/bin/mkdir -p " temp "/home/.asl " temp "/old/asl/packages/asl-agent/src " temp "/new/asl/packages/asl-agent/src") 5000))
        (wOld (fileWrite (str temp "/old/asl/packages/asl-agent/src/providers.asl") "(module x)\n"))
        (wNew (fileWrite (str temp "/new/asl/packages/asl-agent/src/providers.asl") "fn hubAsnPath cfg -> String\n"))
        (none_ (pf/hubPreflight (str temp "/home") (str temp "/old")))
        (hubW (fileWrite (str temp "/home/.asl/hub.asn") "(:hub :sock \"/x/hub.sock\")\n"))
        (good (pf/hubPreflight (str temp "/home") (str temp "/new")))
        (bad (pf/hubPreflight (str temp "/home") (str temp "/old")))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and (ok? made) (and (ok? wOld) (and (ok? wNew) (ok? hubW)))) "scratch tree written")
      (assert (= (resultOr none_ "") "noHub") "no hub.asn: nothing to check")
      (assert (= (resultOr good "") "hubClient") "hub and a client-carrying worktree pass")
      (assert (match bad ((err e) (stringStartsWith? e "ERR_HUB_CLIENT_MISSING")) ((ok _) false)) "hub and an old worktree are refused")
      (assert removed "temp dir removed")
      true))
