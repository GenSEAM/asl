(module aslBench/bootstrapRebuild :x [BootstrapStage RebuildReceipt verifyBootstrapClosure makeRebuildReceipt] :i [])

(schema BootstrapStage (:f stageId I64) (:f stageName Str) (:f toolchain Str) (:f artifactPath Str) (:f sourceDigest Str) (:f artifactDigest Str))

(schema RebuildReceipt (:f stage0Digest Str) (:f stage1Digest Str) (:f stage2Digest Str) (:f closed Bool) (:f status Str))

fn makeRebuildReceipt s0: Str s1: Str s2: Str -> RebuildReceipt
  (let [(isClosed (and (not (stringEmpty? s1)) (= s1 s2)))] (RebuildReceipt :stage0Digest s0 :stage1Digest s1 :stage2Digest s2 :closed isClosed :status (if isClosed ":verified" ":divergent")))

fn verifyBootstrapClosure s0: Str s1: Str s2: Str -> Bool
  (let [(r (makeRebuildReceipt s0 s1 s2))] r.closed)
