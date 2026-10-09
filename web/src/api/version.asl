(module aslWeb/apiVersion :x [versionInfo])

(schema DownloadUrls (:f darwin_arm64 Str) (:f darwin_x64 Str) (:f linux_x64 Str) (:f linux_arm64 Str))
(schema VersionInfo (:f version Str) (:f name Str) (:f channel Str) (:f published_at Str) (:f min_cli_version Str) (:f download_urls DownloadUrls) (:f release_notes Str))

fn versionInfo -> VersionInfo
  (VersionInfo :version "0.1.0" :name "asl" :channel "stable" :published_at "2026-09-01T11:25:00Z" :min_cli_version "0.1.0" :download_urls (DownloadUrls :darwin_arm64 "https://github.com/GenSEAM/asl/releases/latest/download/asl-darwin-arm64.tar.gz" :darwin_x64 "https://github.com/GenSEAM/asl/releases/latest/download/asl-darwin-x64.tar.gz" :linux_x64 "https://github.com/GenSEAM/asl/releases/latest/download/asl-linux-x64.tar.gz" :linux_arm64 "https://github.com/GenSEAM/asl/releases/latest/download/asl-linux-arm64.tar.gz") :release_notes "ASL (df, dfs, dfe, F64, I64, Str, Bool) v0.3 release with in-memory WebAssembly execution and Universal Agent Skills Hub.")
