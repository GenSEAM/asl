(module asl-bench/bootstrap-rebuild
  :d "Benchmark and closure validation for self-hosted compiler bootstrap generations."
  :x [BootstrapStage RebuildReceipt
      verify-bootstrap-closure make-rebuild-receipt]
  :i [])

(dfs BootstrapStage
  (:f stage-id I64 "Generation index 0, 1, or 2")
  (:f stage-name Str "Identifier seed, stage1, stage2, or wasm")
  (:f toolchain Str "Toolchain responsible for compilation")
  (:f artifact-path Str "Output binary path")
  (:f source-digest Str "Source SHA256 digest")
  (:f artifact-digest Str "Produced artifact SHA256 digest"))

(dfs RebuildReceipt
  (:f stage0-digest Str "Seed interpreter digest")
  (:f stage1-digest Str "First generation compiler digest")
  (:f stage2-digest Str "Second generation self-compiled digest")
  (:f closed Bool "True if stage1 and stage2 achieve semantic and artifact closure")
  (:f status Str "Closure status :verified or :failed"))

(df make-rebuild-receipt [(s0 Str) (s1 Str) (s2 Str)] -> RebuildReceipt
  :d "Constructs a bootstrap rebuild receipt comparing successive compiler generations."
  (let [(is-closed (and (not (string-empty? s1)) (= s1 s2)))]
    (RebuildReceipt
      :stage0-digest s0
      :stage1-digest s1
      :stage2-digest s2
      :closed is-closed
      :status (if is-closed ":verified" ":divergent"))))

(df verify-bootstrap-closure [(s0 Str) (s1 Str) (s2 Str)] -> Bool
  :d "Verifies closure across bootstrap compiler rebuild generations."
  (let [(r (make-rebuild-receipt s0 s1 s2))]
    (.-closed r)))
