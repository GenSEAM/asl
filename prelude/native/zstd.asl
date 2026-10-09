(module aslPreludeNative/zstd :x [zstdDecompress] :i [])

fn ! zstdDecompress src: Bytes -> (Result Bytes String)
  (zstdAslDecompress src)
