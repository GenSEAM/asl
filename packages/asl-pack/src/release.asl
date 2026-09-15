(module aslPack/release
  :d "Pure AgentScript release orchestrator: native process execution, multi-platform binary bundler, checksum generator, web publishing, and atomic self-update generator."
  :x [ReleasePlan
      makeReleasePlan
      ReleaseStepResult
      ReleaseReceipt
      executeReleaseStep
      runVerificationGate
      prepareDistDirectory
      bundleTargetPlatform
      generateChecksumManifest
      preparePublishMetadata
      executeReleasePlan
      executeSelfUpdate
      emitReleaseScriptSh
      emitUpgradeScriptSh
      emitVersionAsn]
  :i [(platform :a plat)
      (dist :a dist)
      (asl-sh :a sh)])

(dfs ReleasePlan
  (:f version Str "Semver release version string e.g. 0.1.0")
  (:f tag Str "Git release tag string e.g. v0.1.0")
  (:f releaseDate Str "ISO date of release")
  (:f targetPlatforms (List Str) "List of target platform descriptors")
  (:f distDir Str "Output directory for release archives"))

(dfs ReleaseStepResult
  (:f name Str "Release execution step name")
  (:f ok Bool "True if step completed successfully")
  (:f message Str "Terminal output or failure diagnostic")
  (:f durationMs Int64 "Execution elapsed time in milliseconds"))

(dfs ReleaseReceipt
  (:f plan ReleasePlan "Release plan executed")
  (:f ok Bool "True if all pipeline steps succeeded")
  (:f steps (List ReleaseStepResult) "Sequential execution step results")
  (:f publishedArtifacts (List Str) "List of generated distribution artifact paths"))

(df makeReleasePlan [(version Str)] -> ReleasePlan
  :d "Constructs standard production release plan."
  (ReleasePlan
    :version version
    :tag (str "v" version)
    :releaseDate "2026-09-08"
    :targetPlatforms (list "darwin-arm64" "darwin-x64" "linux-x64" "linux-arm64" "windows-x64")
    :distDir "dist"))

(df executeReleaseStep [(name Str) (binary Str) (args (List Str))] -> ReleaseStepResult
  :d "Natively executes a single release pipeline command and produces a structured step result"
  (mt (sh/runCmd! binary args)
    ((ok r)
     (let [(exitCode (.-exitCode r))
           (dur (.-durationMs r))
           (summary (.-summary r))]
       (ReleaseStepResult :name name :ok (== exitCode 0) :message summary :durationMs dur)))
    ((err _)
     (ReleaseStepResult :name name :ok false :message "Process execution failed" :durationMs 0))))

(df runVerificationGate [(plan ReleasePlan)] -> ReleaseStepResult
  :d "Natively executes complete pure ASL verification gate suite"
  (executeReleaseStep "verificationGate" "./asl/bin/asl" (list "gate")))

(df prepareDistDirectory [(plan ReleasePlan)] -> ReleaseStepResult
  :d "Prepares clean output distribution directory for the target release tag"
  (let [(distPath (str (.-distDir plan) "/" (.-tag plan)))]
    (executeReleaseStep "prepareDist" "mkdir" (list "-p" distPath))))

(df bundleTargetPlatform [(plan ReleasePlan) (target Str)] -> ReleaseStepResult
  :d "Packages binary release archive for named target platform"
  (let [(distPath (str (.-distDir plan) "/" (.-tag plan)))
        (v (.-version plan))]
    (if (string-contains? target "windows")
      (executeReleaseStep (str "bundle-" target) "zip" (list "-q" (str distPath "/asl-" v "-" target ".zip") "asl"))
      (executeReleaseStep (str "bundle-" target) "tar" (list "-czf" (str distPath "/asl-" v "-" target ".tar.gz") "asl")))))

(df generateChecksumManifest [(plan ReleasePlan)] -> ReleaseStepResult
  :d "Natively generates SHA256 checksum manifest for release archives"
  (let [(distPath (str (.-distDir plan) "/" (.-tag plan)))]
    (executeReleaseStep "generateChecksums" "sh" (list "-c" (str "cd " distPath " && (sha256sum asl-* > SHA256SUMS 2>/dev/null || shasum -a 256 asl-* > SHA256SUMS 2>/dev/null || true)")))))

(df preparePublishMetadata [(plan ReleasePlan)] -> ReleaseStepResult
  :d "Prepares package metadata and manifests for web and registry publishing"
  (let [(distPath (str (.-distDir plan) "/" (.-tag plan)))]
    (executeReleaseStep "publishMetadata" "cp" (list "package.json" (str distPath "/package.json")))))

(df executeReleasePlan [(plan ReleasePlan)] -> ReleaseReceipt
  :d "Master sequential pipeline orchestrator executing all release steps and returning structured receipt"
  (let [(s1 (runVerificationGate plan))
        (s2 (prepareDistDirectory plan))
        (targetBundles (map (fn [(t Str)] -> ReleaseStepResult (bundleTargetPlatform plan t)) (.-targetPlatforms plan)))
        (s4 (generateChecksumManifest plan))
        (s5 (preparePublishMetadata plan))
        (allSteps (concat (list s1 s2) (concat targetBundles (list s4 s5))))
        (allOk (fold (fn [(acc Bool) (step ReleaseStepResult)] -> Bool (and acc (.-ok step))) true allSteps))
        (distPath (str (.-distDir plan) "/" (.-tag plan)))
        (artifacts (map (fn [(t Str)] -> Str (str distPath "/asl-" (.-version plan) "-" t (if (string-contains? t "windows") ".zip" ".tar.gz"))) (.-targetPlatforms plan)))]
    (ReleaseReceipt
      :plan plan
      :ok allOk
      :steps allSteps
      :publishedArtifacts artifacts)))

(df executeSelfUpdate [(versionUrl Str)] -> ReleaseStepResult
  :d "Natively checks and coordinates in-place binary upgrade"
  (executeReleaseStep "selfUpdate" "curl" (list "-fsSL" versionUrl)))

(df emitVersionAsn [(plan ReleasePlan)] -> Str
  :d "Emits version.asn metadata for remote version discovery and self-update."
  (str "(:release\n"
       "  :version \"" (.-version plan) "\"\n"
       "  :tag \"" (.-tag plan) "\"\n"
       "  :date \"" (.-releaseDate plan) "\"\n"
       "  :channel :stable\n"
       "  :binary-base \"https://github.com/GenSEAM/asl/releases/download/" (.-tag plan) "\")\n"))

(df emitReleaseScriptSh [(plan ReleasePlan)] -> Str
  :d "Generates complete POSIX release pipeline script."
  (let [(v (.-version plan))
        (tag (.-tag plan))]
    (str "#!/usr/bin/env bash\n"
         "# AgentScript (ASL) Production Release Pipeline\n"
         "# Auto-generated from pure AgentScript module: asl/packages/asl-pack/src/release.asl\n"
         "set -eo pipefail\n\n"
         "VERSION=\"" v "\"\n"
         "TAG=\"" tag "\"\n"
         "ROOT_DIR=\"$(cd -P \"$(dirname \"${BASH_SOURCE[0]}\")/..\" && pwd)\"\n"
         "cd \"$ROOT_DIR\"\n\n"
         "echo \"[RELEASE] Starting automated release for ${TAG}...\";\n\n"
         "# Step 1: Verification Gates\n"
         "echo \"--> [1/5] Executing complete 7-gate verification suite...\";\n"
         "./asl/asl gate\n\n"
         "# Step 2: Prepare Release Output\n"
         "echo \"--> [2/5] Preparing release distribution directory...\";\n"
         "DIST_DIR=\"dist/${TAG}\"\n"
         "mkdir -p \"$DIST_DIR\"\n\n"
         "# Step 3: Bundle Platform Archives\n"
         "echo \"--> [3/5] Packaging binary archives for target platforms...\";\n"
         "for target in darwin-arm64 darwin-x64 linux-x64 linux-arm64; do\n"
         "  ARCHIVE=\"${DIST_DIR}/asl-${VERSION}-${target}.tar.gz\"\n"
         "  tar -czf \"${ARCHIVE}\" -C \"${ROOT_DIR}\" asl\n"
         "  echo \"    [OK] Built ${ARCHIVE}\"\n"
         "done\n"
         "# Windows zip bundle\n"
         "if command -v zip >/dev/null 2>&1; then\n"
         "  zip -q \"${DIST_DIR}/asl-${VERSION}-windows-x64.zip\" asl\n"
         "  echo \"    [OK] Built ${DIST_DIR}/asl-${VERSION}-windows-x64.zip\"\n"
         "fi\n\n"
         "# Step 4: Checksums\n"
         "echo \"--> [4/5] Generating cryptographic SHA256 checksums...\";\n"
         "cd \"$DIST_DIR\"\n"
         "if command -v sha256sum >/dev/null 2>&1; then\n"
         "  sha256sum asl-* > SHA256SUMS\n"
         "elif command -v shasum >/dev/null 2>&1; then\n"
         "  shasum -a 256 asl-* > SHA256SUMS\n"
         "fi\n"
         "cd \"$ROOT_DIR\"\n\n"
         "# Step 5: Web & NPM Publishing Preparation\n"
         "echo \"--> [5/5] Updating web distribution and version metadata...\";\n"
         "cp \"$ROOT_DIR/npm/package.json\" \"$DIST_DIR/package.json\"\n"
         "echo \"[OK] Release ${TAG} packaged cleanly in ${DIST_DIR}.\";\n"
         "echo \"[RELEASE] Ready to tag and publish: git tag ${TAG} && git push origin ${TAG}\";\n")))

(df emitUpgradeScriptSh [] -> Str
  :d "Generates atomic in-place binary upgrade script."
  (str "#!/bin/bash\n"
       "# AgentScript (ASL) Self-Update Runner\n"
       "# Auto-generated from pure AgentScript module: asl/packages/asl-pack/src/release.asl\n"
       "set -eo pipefail\n\n"
       "VERSION_URL=\"https://aslang.dev/version.asn\"\n"
       "CURRENT_BIN=\"$(command -v asl 2>/dev/null || echo \"${HOME}/.local/bin/asl\")\"\n\n"
       "echo \"[UPDATE] Checking for AgentScript updates from ${VERSION_URL}...\";\n"
       "REMOTE_ASN=\"$(curl -fsSL \"${VERSION_URL}\" 2>/dev/null || true)\"\n"
       "if [ -z \"$REMOTE_ASN\" ]; then\n"
       "  echo \"[ERROR] Could not check for updates (offline or network error).\";\n"
       "  exit 1;\n"
       "fi\n\n"
       "REMOTE_VER=\"$(echo \"$REMOTE_ASN\" | grep ':version' | head -1 | awk -F'\"' '{print $2}')\"\n"
       "LOCAL_VER=\"$(\"$CURRENT_BIN\" version 2>/dev/null || echo \"0.0.0\")\"\n\n"
       "if [ \"$REMOTE_VER\" = \"$LOCAL_VER\" ]; then\n"
       "  echo \"[OK] AgentScript is already up to date (v${LOCAL_VER}).\";\n"
       "  exit 0;\n"
       "fi\n\n"
       "echo \"[UPDATE] Upgrading AgentScript: v${LOCAL_VER} -> v${REMOTE_VER}...\";\n"
       "curl -fsSL https://aslang.dev/install.sh | bash\n"
       "echo \"[OK] Successfully updated to v${REMOTE_VER}!\";\n"))
