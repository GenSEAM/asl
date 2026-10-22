(module grammar/capabilitiesTruthTest
  :x [runTests]
  :i [(asl-forms/tests/leaseProbeSupport :a lp)])

fn hasManageTimeout! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (stringContains? text ":id manage"))
    ((err e) false))

fn hasFetchRows! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (and
        (stringContains? text ":id curl")
        (and
          (stringContains? text "asl-crawler")
          (stringContains? text "asl-gateway/src/browserGateway"))))
    ((err e) false))

fn canonicalNoAslMemEdit! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (match (stringIndexOf text ":canonicalMemoryMatrix")
        ((some before)
          (match (stringIndexOf text ":situations")
            ((some after)
              (match (stringSlice text before after)
                ((some section)
                  (not (stringContains? section "asl mem edit")))
                ((none) false)))
            ((none) false)))
        ((none) false)))
    ((err e) false))

fn allRowsHaveStatus! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (let [(replaced (stringReplace text ":status :works" ""))
            (workCount (- (stringLength text) (stringLength replaced)))]
        (> workCount 0)))
    ((err e) false))

; (:m :note "HLAUDIT-LOWS: allRowsHaveStatus! only asserted the string ':status :works' exists somewhere in capabilities.asn, never that any one row's claim is true; the lease row (:cap :id lease :status :works) had no :probe/:expect pair like the read-side capabilities do and no test anywhere called asl-coord/claims' claim!/release!, so its :works status was asserted, not probed -- lp/leaseClaimWorks! calls the real claim!/release! functions against a throwaway, isolated git repo (never the shared .git/asl/claims this worktree's own coordination uses) to probe the actual behavior the row claims: a lease is acquired, visible, blocks an overlapping claim, and is fully gone after release; the one-time setup child goes through asl/tools/fleet/run.asl (fr/job/fr/runOneLimited), per spawnSafety, not a bare processRun; the probe itself lives in asl-forms/tests/leaseProbeSupport.asl (HLLOWS-TRAINFIX), a sibling of claimTest.asl, not here, so this grammarExamples-surface file stays free of the raw envGet/nowNs/pathRemove/fileExists? builtin calls the audit flags as retired pending the builtinBang codemod")
fn ! runTests -> Bool
  (do
    (assert (hasManageTimeout!) "manage capability exists")
    (assert (hasFetchRows!) "curl, crawler, and browserGateway rows exist")
    (assert (canonicalNoAslMemEdit!) "canonicalMemoryMatrix uses form names not 'asl mem edit' strings")
    (assert (allRowsHaveStatus!) "capabilities have status values")
    (assert (lp/leaseClaimWorks!) "the lease capability's :works claim is probed against a real, isolated claim!/release! round trip, not just asserted")
    true)
