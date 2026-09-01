export async function onRequestGet(context: any) {
  const versionData = {
    version: "1.0.0",
    name: "asl",
    channel: "stable",
    published_at: new Date().toISOString(),
    min_cli_version: "1.0.0",
    download_urls: {
      darwin_arm64: "https://github.com/GenSEAM/asl/releases/latest/download/asl-darwin-arm64.tar.gz",
      darwin_x64: "https://github.com/GenSEAM/asl/releases/latest/download/asl-darwin-x64.tar.gz",
      linux_x64: "https://github.com/GenSEAM/asl/releases/latest/download/asl-linux-x64.tar.gz",
      linux_arm64: "https://github.com/GenSEAM/asl/releases/latest/download/asl-linux-arm64.tar.gz"
    },
    release_notes: "ASL Nano (df, dfs, dfe, F64, I64, Str, Bool) official 1.0 release with in-memory WebAssembly execution and Universal Agent Skills Hub."
  };

  return new Response(JSON.stringify(versionData, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
