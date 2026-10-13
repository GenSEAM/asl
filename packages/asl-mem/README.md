# @genseam/mem (ASL Vector Semantic Memory)

Zero-server in-memory vector database and cosine similarity search engine running in 64KB WebAssembly.

## Package Dependency
Declare in your module's `manifest.asn`:
```asn
(:package my-app
  :dependencies ["asl-mem"])
```

## Performance
- **Memory Footprint:** 64KB Wasm page
- **Search Latency:** 0.038ms (5,000 vectors)
- **Zero-Server:** Runs 100% in-browser, on edge devices, or inside iOS/Android Wasm3 runtimes.

## Verification
```asn
;; Run pure ASL vector memory assertions
(:test-mem
  :do "./bin/asl test asl/packages/asl-mem/tests/memTest.asl"
  :summary "Execute in-memory vector indexing and cosine similarity assertion suite")
```

## License
MIT
