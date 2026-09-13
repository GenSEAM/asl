(module aslBench/bootstrapRebuild
  :d "Benchmark and closure validation for self-hosted compiler bootstrap generations."
  :x [BootstrapStage RebuildReceipt
      verifyBootstrapClosure makeRebuildReceipt]
  :i [])

(dfs BootstrapStage
  (:f stageId I64 "Generation index 0, 1, or 2")
  (:f stageName Str "Identifier seed, stage1, stage2, or wasm")
  (:f toolchain Str "Toolchain responsible for compilation")
  (:f artifactPath Str "Output binary path")
  (:f sourceDigest Str "Source SHA256 digest")
  (:f artifactDigest Str "Produced artifact SHA256 digest"))

(dfs RebuildReceipt
  (:f stage0Digest Str "Seed interpreter digest")
  (:f stage1Digest Str "First generation compiler digest")
  (:f stage2Digest Str "Second generation self-compiled digest")
  (:f closed Bool "True if stage1 and stage2 achieve semantic and artifact closure")
  (:f status Str "Closure status :verified or :failed"))

(df makeRebuildReceipt [(s0 Str) (s1 Str) (s2 Str)] -> RebuildReceipt
  :d "Constructs a bootstrap rebuild receipt comparing successive compiler generations."
  (let [(isClosed (and (not (string-empty? s1)) (= s1 s2)))]
    (RebuildReceipt
      :stage0Digest s0
      :stage1Digest s1
      :stage2Digest s2
      :closed isClosed
      :status (if isClosed ":verified" ":divergent"))))

(df verifyBootstrapClosure [(s0 Str) (s1 Str) (s2 Str)] -> Bool
  :d "Verifies closure across bootstrap compiler rebuild generations."
  (let [(r (makeRebuildReceipt s0 s1 s2))]
    (.-closed r)))
