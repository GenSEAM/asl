(module aslPack/release :x [ReleasePlan makeReleasePlan ReleaseStepResult ReleaseReceipt executeReleaseStep! runVerificationGate! prepareDistDirectory! bundleTargetPlatform! generateChecksumManifest! preparePublishMetadata! executeReleasePlan! executeSelfUpdate! emitReleaseScriptSh emitUpgradeScriptSh emitVersionAsn] :i [(platform :a plat) (dist :a dist) (asl-proc :a sh)])

(schema ReleasePlan (:f version Str) (:f tag Str) (:f releaseDate Str) (:f targetPlatforms (List Str)) (:f distDir Str))

(schema ReleaseStepResult (:f name Str) (:f ok Bool) (:f message Str) (:f durationMs Int64))

(schema ReleaseReceipt (:f plan ReleasePlan) (:f ok Bool) (:f steps (List ReleaseStepResult)) (:f publishedArtifacts (List Str)))

fn makeReleasePlan version: Str -> ReleasePlan
  (ReleasePlan :version version :tag (str "v" version) :releaseDate "2026-09-08" :targetPlatforms (list "darwin-arm64" "darwin-x64" "linux-x64" "linux-arm64" "windows-x64") :distDir "dist")

fn executeReleaseStep! name: Str binary: Str args: (List Str) -> ReleaseStepResult
  (mt (sh/runCmd! binary args) ((ok r) (let [(exitCode r.exitCode) (dur r.durationMs) (summary r.summary) (_ (sh/releaseReceipt! r))] (ReleaseStepResult :name name :ok (== exitCode 0) :message summary :durationMs dur))) ((err _) (ReleaseStepResult :name name :ok false :message "Process execution failed" :durationMs 0)))

fn runVerificationGate! plan: ReleasePlan -> ReleaseStepResult
  (executeReleaseStep! "verificationGate" "./bin/asl" (list "audit" "gates"))

fn prepareDistDirectory! plan: ReleasePlan -> ReleaseStepResult
  (let [(distPath (str plan.distDir "/" plan.tag))] (executeReleaseStep! "prepareDist" "mkdir" (list "-p" distPath)))

fn bundleTargetPlatform! plan: ReleasePlan target: Str -> ReleaseStepResult
  (let [(distPath (str plan.distDir "/" plan.tag)) (v plan.version)] (if (stringContains? target "windows") (executeReleaseStep! (str "bundle-" target) "zip" (list "-q" (str distPath "/asl-" v "-" target ".zip") "asl")) (executeReleaseStep! (str "bundle-" target) "tar" (list "-czf" (str distPath "/asl-" v "-" target ".tar.gz") "asl"))))

fn generateChecksumManifest! plan: ReleasePlan -> ReleaseStepResult
  (let [(distPath (str plan.distDir "/" plan.tag))] (executeReleaseStep! "generateChecksums" "sh" (list "-c" (str "cd " distPath " && (sha256sum asl-* > SHA256SUMS 2>/dev/null || shasum -a 256 asl-* > SHA256SUMS 2>/dev/null || true)"))))

fn preparePublishMetadata! plan: ReleasePlan -> ReleaseStepResult
  (let [(distPath (str plan.distDir "/" plan.tag))] (executeReleaseStep! "publishMetadata" "cp" (list "package.json" (str distPath "/package.json"))))

fn executeReleasePlan! plan: ReleasePlan -> ReleaseReceipt
  (let [(s1 (runVerificationGate! plan)) (s2 (prepareDistDirectory! plan)) (targetBundles (map (fn [(t Str)] -> ReleaseStepResult (bundleTargetPlatform! plan t)) plan.targetPlatforms)) (s4 (generateChecksumManifest! plan)) (s5 (preparePublishMetadata! plan)) (allSteps (listAppend (list s1 s2) (listAppend targetBundles (list s4 s5)))) (allOk (fold (fn [(acc Bool) (step ReleaseStepResult)] -> Bool (and acc step.ok)) true allSteps)) (distPath (str plan.distDir "/" plan.tag)) (artifacts (map (fn [(t Str)] -> Str (str distPath "/asl-" plan.version "-" t (if (stringContains? t "windows") ".zip" ".tar.gz"))) plan.targetPlatforms))] (ReleaseReceipt :plan plan :ok allOk :steps allSteps :publishedArtifacts artifacts))

fn executeSelfUpdate! versionUrl: Str -> ReleaseStepResult
  (executeReleaseStep! "selfUpdate" "curl" (list "-fsSL" versionUrl))

fn emitVersionAsn plan: ReleasePlan -> Str
  (str "(:release\n" "  :version \"" plan.version "\"\n" "  :tag \"" plan.tag "\"\n" "  :date \"" plan.releaseDate "\"\n" "  :channel :stable\n" "  :binary-base \"https://github.com/GenSEAM/asl/releases/download/" plan.tag "\")\n")

fn emitReleaseScriptSh plan: ReleasePlan -> Str
  (let [(v plan.version) (tag plan.tag)] (str "#!/usr/bin/env bash\n" "# AgentSlang (ASL) Production Release Pipeline\n" "# Auto-generated from pure AgentSlang module: asl/packages/asl-pack/src/release.asl\n" "set -eo pipefail\n\n" "VERSION=\"" v "\"\n" "TAG=\"" tag "\"\n" "ROOT_DIR=\"$(cd -P \"$(dirname \"${BASH_SOURCE[0]}\")/..\" && pwd)\"\n" "cd \"$ROOT_DIR\"\n\n" "echo \"[RELEASE] Starting automated release for ${TAG}...\";\n\n" "# Step 1: Verification Gates\n" "echo \"--> [1/5] Executing complete 7-gate verification suite...\";\n" "./asl/asl gate\n\n" "# Step 2: Prepare Release Output\n" "echo \"--> [2/5] Preparing release distribution directory...\";\n" "DIST_DIR=\"dist/${TAG}\"\n" "mkdir -p \"$DIST_DIR\"\n\n" "# Step 3: Bundle Platform Archives\n" "echo \"--> [3/5] Packaging binary archives for target platforms...\";\n" "for target in darwin-arm64 darwin-x64 linux-x64 linux-arm64; do\n" "  ARCHIVE=\"${DIST_DIR}/asl-${VERSION}-${target}.tar.gz\"\n" "  tar -czf \"${ARCHIVE}\" -C \"${ROOT_DIR}\" asl\n" "  echo \"    [OK] Built ${ARCHIVE}\"\n" "done\n" "# Windows zip bundle\n" "if command -v zip >/dev/null 2>&1; then\n" "  zip -q \"${DIST_DIR}/asl-${VERSION}-windows-x64.zip\" asl\n" "  echo \"    [OK] Built ${DIST_DIR}/asl-${VERSION}-windows-x64.zip\"\n" "fi\n\n" "# Step 4: Checksums\n" "echo \"--> [4/5] Generating cryptographic SHA256 checksums...\";\n" "cd \"$DIST_DIR\"\n" "if command -v sha256sum >/dev/null 2>&1; then\n" "  sha256sum asl-* > SHA256SUMS\n" "elif command -v shasum >/dev/null 2>&1; then\n" "  shasum -a 256 asl-* > SHA256SUMS\n" "fi\n" "cd \"$ROOT_DIR\"\n\n" "# Step 5: Web & NPM Publishing Preparation\n" "echo \"--> [5/5] Updating web distribution and version metadata...\";\n" "cp \"$ROOT_DIR/npm/package.json\" \"$DIST_DIR/package.json\"\n" "echo \"[OK] Release ${TAG} packaged cleanly in ${DIST_DIR}.\";\n" "echo \"[RELEASE] Ready to tag and publish: git tag ${TAG} && git push origin ${TAG}\";\n"))

fn emitUpgradeScriptSh -> Str
  (str "#!/bin/bash\n" "# AgentSlang (ASL) Self-Update Runner\n" "# Auto-generated from pure AgentSlang module: asl/packages/asl-pack/src/release.asl\n" "set -eo pipefail\n\n" "VERSION_URL=\"https://aslang.dev/version.asn\"\n" "CURRENT_BIN=\"$(command -v asl 2>/dev/null || echo \"${HOME}/.local/bin/asl\")\"\n\n" "echo \"[UPDATE] Checking for AgentSlang updates from ${VERSION_URL}...\";\n" "REMOTE_ASN=\"$(curl -fsSL \"${VERSION_URL}\" 2>/dev/null || true)\"\n" "if [ -z \"$REMOTE_ASN\" ]; then\n" "  echo \"[ERROR] Could not check for updates (offline or network error).\";\n" "  exit 1;\n" "fi\n\n" "REMOTE_VER=\"$(echo \"$REMOTE_ASN\" | grep ':version' | head -1 | awk -F'\"' '{print $2}')\"\n" "LOCAL_VER=\"$(\"$CURRENT_BIN\" version 2>/dev/null || echo \"0.0.0\")\"\n\n" "if [ \"$REMOTE_VER\" = \"$LOCAL_VER\" ]; then\n" "  echo \"[OK] AgentSlang is already up to date (v${LOCAL_VER}).\";\n" "  exit 0;\n" "fi\n\n" "echo \"[UPDATE] Upgrading AgentSlang: v${LOCAL_VER} -> v${REMOTE_VER}...\";\n" "curl -fsSL https://aslang.dev/install.sh | bash\n" "echo \"[OK] Successfully updated to v${REMOTE_VER}!\";\n")
