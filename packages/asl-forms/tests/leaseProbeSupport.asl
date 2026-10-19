(module asl-forms/tests/leaseProbeSupport
  :x [leaseClaimWorks!]
  :i [(asl-coord/claims :a coord) (tools/fleet/run :a fr)])

; (:m :ref HLLOWS-TRAINFIX :do "leaseClaimWorks! moved out of asl/grammar/tests/capabilitiesTruthTest.asl (the grammarExamples audit surface, meant to model clean idiomatic style for agents) into this sibling of asl-forms/tests/claimTest.asl, which already probes claim!/release! the same way; the throwaway-repo setup and teardown calls envGet/nowNs/pathRemove/fileExists? as raw host builtins, same as claimTest.asl's own tmp-root line, which the builtinBang codemod has not reached yet (plan row EFFECT-BUILTINS-BANG) -- keeping that debt out of the grammar surface instead of counting it there")
fn leaseProbeRoot! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/aslCapabilitiesTruthProbe" (stringFromInt64 (nowNs)))

fn leaseClaimWorks! -> Bool
  (let [(root (leaseProbeRoot!))
        (setup (fr/runOneLimited (fr/job (list "sh" "-c" (str "mkdir -p " root " && cd " root " && git init -b sh/probeUnit >/dev/null 2>&1")) "." (fr/childEnv (list))) (fr/limits 30 4)))
        (claimed (coord/claim! root "probeUnit" (list "src/a")))
        (listedAfterClaim (coord/claims! root))
        (conflict (coord/claim! root "otherUnit" (list "src/a/sub")))
        (independent (coord/claim! root "otherUnit" (list "src/b")))
        (released (coord/release! root "probeUnit"))
        (listedAfterRelease (coord/claims! root))
        (cleaned (pathRemove root))]
    (do
      (assert (= setup.exit 0) "a throwaway git repo is created for the probe, never the shared coordination store")
      (assert (ok? claimed) (str "claim! actually acquires a lease: " claimed))
      (assert (and (ok? listedAfterClaim) (stringContains? (resultOr listedAfterClaim "") ":unit \"probeUnit\""))
        (str "claims! lists the just-acquired lease: " listedAfterClaim))
      (assert (err? conflict) (str "claim! actually refuses a path overlapping a live lease: " conflict))
      (assert (ok? independent) (str "claim! actually allows a non-overlapping path: " independent))
      (assert (ok? released) (str "release! actually drops the lease: " released))
      (assert (and (ok? listedAfterRelease) (not (stringContains? (resultOr listedAfterRelease "") ":unit \"probeUnit\"")))
        (str "claims! no longer lists the released lease: " listedAfterRelease))
      (assert (and (ok? cleaned) (not (fileExists? root))) "the throwaway probe repo is removed")
      true))
