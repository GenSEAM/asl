(module prelude/tests/zstdAslTest :x [runTests] :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn decodeSha! path: String -> String
  (mt (fileReadBytes path)
    ((ok src)
      (mt (zstdAslDecompress src)
        ((ok decoded)
          (mt (zstdDecompress src)
            ((ok reference) (if (= (bytesSha256 decoded) (bytesSha256 reference)) (bytesSha256 decoded) "BYTE_MISMATCH"))
            ((err message) (str "C_ERR " message))))
        ((err message) (str "ASL_ERR " message))))
    ((err message) (str "NO_FILE " message)))

fn decodeErr! path: String -> String
  (mt (fileReadBytes path)
    ((ok src)
      (let [aslError (mt (zstdAslDecompress src) ((ok _) "DECODED") ((err message) (str "ERR " message)))
            cError (mt (zstdDecompress src) ((ok _) "DECODED") ((err message) (str "ERR " message)))]
        (if (= aslError cError) aslError "ERROR_TEXT_MISMATCH")))
    ((err _) "NO_FILE"))

fn isErr! path: String -> Bool
  (stringStartsWith? (decodeErr! path) "ERR ")

fn isUnsupported! path: String -> Bool
  (stringContains? (decodeErr! path) "ERR_ZSTD_UNSUPPORTED")

fn dataByte i: Int64 -> Int64
  (mod (+ (* i 131) (/ i 251)) 256)

fn ! putList b: Bytes at: Int64 xs: (List Int64) -> Int64
  (mt (listHead xs)
    ((some x) (do (bytesSet b at x) (mt (listTail xs) ((some rest) (putList b (+ at 1) rest)))))
    (none at))

fn ! putData b: Bytes at: Int64 i: Int64 end: Int64 -> Int64
  (if (>= i end) at
    (do (bytesSet b at (dataByte i)) (putData b (+ at 1) (+ i 1) end)))

"1 KiB window, two raw 600-byte blocks, then one RLE-mode sequence (ll 0, ml 3) whose offset off stays within the 1200 bytes already produced; the backward bitstream is the 1-sequence offset value off+3 whose top bit is the padding marker"
fn ! windowFrame off: Int64 -> Bytes
  (let [ofv (+ off 3)
        ofCode (if (>= ofv 1024) 10 9)
        b (bytesAlloc 1223)]
    (do
      (putList b 0 (list 40 181 47 253 0 0 192 18 0))
      (putData b 9 0 600)
      (putList b 609 (list 192 18 0))
      (putData b 612 600 1200)
      (putList b 1212 (list 69 0 0 0 1 84 0 ofCode 0 (mod ofv 256) (/ ofv 256)))
      b))

fn ! windowErr off: Int64 -> String
  (let [src (windowFrame off)
        aslError (mt (zstdAslDecompress src) ((ok _) "DECODED") ((err message) (str "ERR " message)))
        cError (mt (zstdDecompress src) ((ok _) "DECODED") ((err message) (str "ERR " message)))]
    (if (= aslError cError) aslError (str "ERROR_TEXT_MISMATCH asl=" aslError " c=" cError)))

fn ! windowTailMatches off: Int64 -> Bool
  (mt (zstdAslDecompress (windowFrame off))
    ((ok decoded)
      (and (= (bytesLength decoded) 1203)
        (= (bytesGet decoded 1200) (dataByte (- 1200 off)))
        (= (bytesGet decoded 1201) (dataByte (- 1201 off)))
        (= (bytesGet decoded 1202) (dataByte (- 1202 off)))
        (mt (zstdDecompress (windowFrame off)) ((ok reference) (= (bytesSha256 decoded) (bytesSha256 reference))) ((err _) false))))
    ((err _) false))

"default reps (1,4,8); block1 is 10 raw bytes [1..10], block2 has two sequences each (ll 1, ofv 3): both land on idx 2, which per RFC 8878 reads rep[2] then sets rep[1]=old rep[0], rep[2]=old rep[1]. Sequence 1 reads rep[2]=8 (copying block1[3..5]=[4,5,6] after literal 'A') and updates rep to (8,1,4). Sequence 2 reads the NEW rep[2]=4 (copying output[11..13]=[4,5,6] after literal 'B'), which a mutant that leaves rep[2] stale (treating idx 2 like idx 1, not updating it) would instead read as the old rep[2]=8 (copying block1[7..9]=[8,9,10]): the two decoders then disagree on bytes 15..17"
fn ! repeatOffsetIdx2Frame -> Bytes
  (let [b (bytesAlloc 31)]
    (do
      (putList b 0 (list 40 181 47 253 0 0 80 0 0))
      (putList b 9 (list 1 2 3 4 5 6 7 8 9 10))
      (putList b 19 (list 77 0 0 16 65 66 2 84 1 1 0 7))
      b))

fn ! repeatOffsetIdx2Matches? -> Bool
  (mt (zstdAslDecompress (repeatOffsetIdx2Frame))
    ((ok decoded)
      (mt (zstdDecompress (repeatOffsetIdx2Frame))
        ((ok reference) (= (bytesSha256 decoded) (bytesSha256 reference)))
        ((err _) false)))
    ((err _) false))

"1 KiB window (windowLog 10), one raw 10-byte block, then one full-offset sequence (ll 0, ml 3, ofv 14 so off = ofv-3 = 11) that reaches exactly one byte past the 10 bytes already produced: window (1024) comfortably covers offset 11, so only the produced-bound guard (off > baseOut+produced+ll) can reject it; a mutant that relaxes that guard by one lets this exact offset through into an out-of-range match copy"
fn ! offsetJustPastProducedFrame -> Bytes
  (let [b (bytesAlloc 29)]
    (do
      (putList b 0 (list 40 181 47 253 0 0 80 0 0))
      (putList b 9 (list 1 2 3 4 5 6 7 8 9 10))
      (putList b 19 (list 61 0 0 0 1 84 0 3 0 14))
      b))

fn ! offsetJustPastProducedErr -> String
  (let [src (offsetJustPastProducedFrame)
        aslError (mt (zstdAslDecompress src) ((ok _) "DECODED") ((err message) (str "ERR " message)))
        cError (mt (zstdDecompress src) ((ok _) "DECODED") ((err message) (str "ERR " message)))]
    (if (= aslError cError) aslError (str "ERROR_TEXT_MISMATCH asl=" aslError " c=" cError)))

"frames from zstd 1.5.7 --check -19 over the first n bytes of MANIFESTO.md; lengths 5, 13, 45, 77 and 100 leave a remainder past the 32-byte stripes, so the xxh64 8-byte and 4-byte tail rounds run, which the 0, 1 and 32-multiple file fixtures skip"
fn ! checkedFrameSha size: Int64 xs: (List Int64) -> String
  (let [src (bytesAlloc size)]
    (do
      (putList src 0 xs)
      (mt (zstdAslDecompress src)
        ((ok decoded)
          (mt (zstdDecompress src)
            ((ok reference) (if (= (bytesSha256 decoded) (bytesSha256 reference)) (bytesSha256 decoded) "BYTE_MISMATCH"))
            ((err message) (str "C_ERR " message))))
        ((err message) (str "ASL_ERR " message)))))

fn ! zstdFixturePaths -> (List String)
  (let [pos (mt (dirList "tests/acceptance/r1Host/fixtures/zstd/pos") ((ok xs) xs) ((err e) (assert false (str "list positive fixtures: " e)) (list)))]
    (let [pages (mt (dirList "tests/acceptance/r1Host/fixtures/zstd/pages") ((ok xs) xs) ((err e) (assert false (str "list parquet page fixtures: " e)) (list)))]
      (let [neg (mt (dirList "tests/acceptance/r1Host/fixtures/zstd/neg") ((ok xs) xs) ((err e) (assert false (str "list negative fixtures: " e)) (list)))
            posPaths (map (fn [n] (str "tests/acceptance/r1Host/fixtures/zstd/pos/" n)) pos)
            pagePaths (map (fn [n] (str "tests/acceptance/r1Host/fixtures/zstd/pages/" n)) pages)
            negPaths (map (fn [n] (str "tests/acceptance/r1Host/fixtures/zstd/neg/" n)) neg)]
        (listAppend (listAppend posPaths pagePaths) negPaths))))

fn ! pathCalls paths: (List String) -> String
  (stringJoin (map (fn [p] (str "    (one \"" p "\")")) paths) "\n")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! overlayProgram paths: (List String) -> String
  (str "(module zstdOverlayAll :x [main] :i [])\n"
       "fn ! adler b: Bytes i: Int64 n: Int64 a: Int64 s: Int64 -> Int64\n"
       "  (if (>= i n) (+ (* s 65536) a)\n"
       "    (let [(a2 (mod (+ a (bytesGet b i)) 65521))]\n"
       "      (adler b (+ i 1) n a2 (mod (+ s a2) 65521))))\n"
       "fn ! one path: String -> Bool\n"
       "  (do\n"
       "    (mt (fileReadBytes path)\n"
       "      ((ok input) (mt (zstdDecompress input)\n"
       "        ((ok decoded) (println (str path \" OK \" (bytesLength decoded) \" \" (adler decoded 0 (bytesLength decoded) 1 0))))\n"
       "        ((err message) (println (str path \" ERR \" message)))))\n"
       "      ((err message) (println (str path \" READ_ERR \" message))))\n"
       "    true)\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (do\n" (pathCalls paths) "\n    (ok 0))\n")

fn ! nativeFixtureParity! paths: (List String) -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))
        (sourcePath (str dir "/zstdOverlayAll.asl"))
        (llPath (str dir "/zstdOverlayAll.ll"))
        (exe (str dir "/zstdOverlayAll"))
        (wroteSource (fileWrite sourcePath (overlayProgram paths)))
        (code (mt (lk/linkEntry! sourcePath)
                ((err ds) (str "error: " (formatDiags ds)))
                ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
                          ((err ds) (str "error: " (formatDiags ds)))
                          ((ok ll) ll)))))
        (wroteLl (fileWrite llPath code))
        (clang (processRun (str "/usr/bin/clang -Wno-override-module -x ir " llPath " -x none asl/host/out/libaslrt.a -lm -o " exe)))
        (native (processRun exe))
        (host (processRun (str "asl/host/out/asl-host run " sourcePath)))
        (removed (processRun (str "rm -rf " dir)))
        (lines (filter (fn [(l String)] -> Bool (> (stringLength l) 0)) (stringSplit native.stdout "\n")))
        (okLines (filter (fn [(l String)] -> Bool (stringContains? l " OK ")) lines))
        (errLines (filter (fn [(l String)] -> Bool (stringContains? l " ERR ")) lines))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes the native zstd fixture work directory")
      (assert (= removed.exitCode 0) "native zstd fixture work directory removed")
      (assert (> (listLength paths) 0) "all three zstd fixture directories contain files")
      (assert (ok? wroteSource) "write all-fixture native zstd program")
      (refute (stringStartsWith? code "error: ") (str "zstdOverlayAll links and emits: " code))
      (assert (stringContains? code "native$2EzstdDecompress(") "the emitted IR defines the overlay function native.zstdDecompress")
      (refute (stringContains? code "@name.zstdDecompress") "the emitted IR names no asl_rt_builtin zstdDecompress")
      (assert (ok? wroteLl) (str "fileWrite " llPath))
      (assert (= clang.exitCode 0) (str "clang links zstdOverlayAll against libaslrt.a: " clang.stderr))
      (assert (= native.exitCode 0) (str "native zstd fixture exit " native.exitCode "; " native.stderr))
      (assert (= host.exitCode 0) (str "asl-host run zstd fixture exit " host.exitCode "; " host.stderr))
      (assert (= (listLength lines) (listLength paths)) (str "native prints one line per fixture: " (listLength lines) " of " (listLength paths)))
      (assert (> (listLength okLines) 0) "native decodes at least one fixture")
      (assert (> (listLength errLines) 0) "native rejects at least one negative fixture")
      (assert (= native.stdout host.stdout) (str "native overlay and asl-host C decoder agree on every frame's length and Adler-32 and on exact negative error text; native=" native.stdout))
      (assert (= native.stderr host.stderr) (str "native and host stderr match: native=" native.stderr " host=" host.stderr))
      true))

fn ! runTests -> Bool
  (do
    (nativeFixtureParity! (zstdFixturePaths))
    (assert (= (checkedFrameSha 18 (list 40 181 47 253 36 5 41 0 0 35 32 84 104 101 161 70 18 104)) "2a2fa0a8b9ef26cbae9e3ee6aa7e10e8669dbd04c2bbc2164b9973b64a9113b6") "checksummed 5-byte frame: xxh64 4-byte and 1-byte tail")
    (assert (= (checkedFrameSha 26 (list 40 181 47 253 36 13 105 0 0 35 32 84 104 101 32 65 103 101 110 116 45 78 98 150 12 115)) "d04001b65743cab9fe1bf25875b8b0df1316f8ae13fb6421a557b3cf1dab0b61") "checksummed 13-byte frame: xxh64 8-, 4- and 1-byte tail")
    (assert (= (checkedFrameSha 58 (list 40 181 47 253 36 45 105 1 0 35 32 84 104 101 32 65 103 101 110 116 45 78 97 116 105 118 101 32 76 97 110 103 117 97 103 101 32 38 32 68 117 97 108 45 80 114 111 106 101 99 116 105 111 110 30 234 36 80)) "ae3a0567cba51ceab8774e9d774a0d89409e12a0526eeb38462226bc1f176155") "checksummed 45-byte frame: one stripe then 8-, 4- and 1-byte tail")
    (assert (= (checkedFrameSha 86 (list 40 181 47 253 36 77 77 2 0 210 68 17 23 128 109 14 68 115 44 175 18 37 218 232 26 14 84 48 6 230 139 69 69 125 224 8 186 121 215 236 143 175 77 23 128 82 31 82 106 248 148 113 75 228 173 25 50 250 180 83 22 148 209 184 112 221 140 219 242 184 70 12 51 89 176 233 18 87 103 121 16 0 222 175 14 113)) "96fd9494aab9e64497e37fbc66f3d93896db80c8e1c0493b0873a1c5967a31d9") "checksummed compressed 77-byte frame: two stripes then 8-, 4- and 1-byte tail")
    (assert (= (checkedFrameSha 100 (list 40 181 47 253 36 100 189 2 0 66 198 20 23 112 111 14 40 73 227 142 104 151 9 254 252 141 8 12 120 130 100 13 208 130 120 1 95 167 46 14 173 101 95 157 24 76 124 196 117 111 105 248 36 71 245 163 167 4 4 97 4 0 222 198 75 234 178 177 123 186 236 212 131 143 81 165 181 120 240 91 90 205 37 227 95 186 233 24 235 222 18 127 130 44 4 0 123 191 221 236)) "c2b30f327eabbc4ab8d4f09d9cfe7063695077b71fa9a38bf8d12ce46cb6ebb1") "checksummed compressed 100-byte frame: three stripes then a 4-byte tail")
    (assert (windowTailMatches 1000) "offset 1000 inside a 1 KiB window copies the bytes 1000 back, matching the C decoder")
    (assert (windowTailMatches 1024) "offset equal to the 1 KiB window is accepted")
    (assert (= (windowErr 1025) "ERR ERR_ZSTD_CORRUPT: match offset beyond the window") "offset 1025 within the 1200 produced bytes but past the 1 KiB window is rejected by both decoders")
    (assert (= (windowErr 1100) "ERR ERR_ZSTD_CORRUPT: match offset beyond the window") "offset 1100 within the 1200 produced bytes but past the 1 KiB window is rejected by both decoders")
    (assert (repeatOffsetIdx2Matches?) "idx 2 repeat offset updates rep slot 3 (new2 = old rep[1]); the next idx-2 sequence reads that updated slot back, byte-exact against the C decoder")
    (assert (= (offsetJustPastProducedErr) "ERR ERR_ZSTD_CORRUPT: match offset beyond the window") "offset exactly one past produced bytes, well within the window, is rejected by the produced-bound guard alone")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/empty-cli-l1.zst") "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") "empty-cli-l1")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/empty-cli-l3.zst") "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") "empty-cli-l3")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/empty-cli-l19.zst") "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") "empty-cli-l19")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/empty-py-l3-checksum.zst") "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") "empty-py-l3-checksum")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/empty-py-l3-nochecksum-nosize.zst") "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") "empty-py-l3-nochecksum-nosize")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/oneByte-cli-l1.zst") "559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd") "oneByte-cli-l1")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/oneByte-cli-l3.zst") "559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd") "oneByte-cli-l3")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/oneByte-cli-l19.zst") "559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd") "oneByte-cli-l19")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/oneByte-py-l3-checksum.zst") "559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd") "oneByte-py-l3-checksum")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/oneByte-py-l3-nochecksum-nosize.zst") "559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd") "oneByte-py-l3-nochecksum-nosize")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text128k-cli-l1.zst") "831a85eb021292f18bbf806268e8a8f8e959f4ff86bc3a525216e122f0a2c82d") "text128k-cli-l1")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text128k-cli-l3.zst") "831a85eb021292f18bbf806268e8a8f8e959f4ff86bc3a525216e122f0a2c82d") "text128k-cli-l3")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text128k-cli-l19.zst") "831a85eb021292f18bbf806268e8a8f8e959f4ff86bc3a525216e122f0a2c82d") "text128k-cli-l19")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text128k-py-l3-checksum.zst") "831a85eb021292f18bbf806268e8a8f8e959f4ff86bc3a525216e122f0a2c82d") "text128k-py-l3-checksum")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text128k-py-l3-nochecksum-nosize.zst") "831a85eb021292f18bbf806268e8a8f8e959f4ff86bc3a525216e122f0a2c82d") "text128k-py-l3-nochecksum-nosize")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text4m-cli-l1.zst") "90c58fc94b502582fe3b3523c8a27b638f78a0e2676bb255dabba9707966ead5") "text4m-cli-l1")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text4m-cli-l3.zst") "90c58fc94b502582fe3b3523c8a27b638f78a0e2676bb255dabba9707966ead5") "text4m-cli-l3")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text4m-cli-l19.zst") "90c58fc94b502582fe3b3523c8a27b638f78a0e2676bb255dabba9707966ead5") "text4m-cli-l19")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/text4m-py-l3-checksum.zst") "90c58fc94b502582fe3b3523c8a27b638f78a0e2676bb255dabba9707966ead5") "text4m-py-l3-checksum")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/crafted-rleSequences-control.zst") "bbb59da3af939f7af5f360f2ceb80a496e3bae1cd87dde426db0ae40677e1c2c") "crafted-rleSequences-control")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/crafted-rawBlockMax-control.zst") "6007c17e06a93c026df05f33f9df8ee3be5ba102830bf063d9ca8e00d43d2930") "crafted-rawBlockMax-control")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c0p0-type2.zst") "ef2641c270ba425549a2cf6c0037fccb4fca7ba7c782c46f64e16100a578e1a1") "rg0c0p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c0p1-type0.zst") "8abd2fac7048e2abf472f35a26e2f64872962b67bb8001a34d72cbde2408bd51") "rg0c0p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c1p0-type2.zst") "59b89abe0b34e31e3926e7af018fd5cf7bfbf60deaae51f2dcfa12e20864654b") "rg0c1p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c1p1-type0.zst") "8abd2fac7048e2abf472f35a26e2f64872962b67bb8001a34d72cbde2408bd51") "rg0c1p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c2p0-type2.zst") "b36c9d511683128c54a76deaa8c7f6166f3d5282b1e9ce7ff9797f4004ee45a1") "rg0c2p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c2p1-type0.zst") "36692f2da22c158d13b458c0f88691f47810d01585de8556b0b8b765b972f2ef") "rg0c2p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c3p0-type2.zst") "456fbd558307be04efa4295580efc73b27a2d5c59c7ee41d7567329668c34f46") "rg0c3p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c3p1-type0.zst") "c67d3c0856c05552bf5640c001cebb95c957f65fd3e6f771f8ebe50b91586df5") "rg0c3p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c4p0-type2.zst") "3bdcf6187bab53fc6e18b7f3e8ea4a666f06f545460189157c6f1ef1e5d85ebc") "rg0c4p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg0c4p1-type0.zst") "09082cf01a55ab35a3830ec6502205481dc649add25170b2db72aec53dde461f") "rg0c4p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c0p0-type2.zst") "b8eee057dbc95af5beab85bb03e78dc4a1c00af18969da4019d6324f5ad154b0") "rg1c0p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c0p1-type0.zst") "8abd2fac7048e2abf472f35a26e2f64872962b67bb8001a34d72cbde2408bd51") "rg1c0p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c1p0-type2.zst") "06895eebb08321529403913182630a4482faaec169cd677d2cdb4696e58f8045") "rg1c1p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c1p1-type0.zst") "8abd2fac7048e2abf472f35a26e2f64872962b67bb8001a34d72cbde2408bd51") "rg1c1p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c2p0-type2.zst") "d1c60f77003604d2d506ed16f399350b345fdd9d0ddcbc909ed7052704bbd01c") "rg1c2p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c2p1-type0.zst") "f79dffadd050f7fdfab42c83cd499d8d7435916963164063e35c59379e5aa4a8") "rg1c2p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c3p0-type2.zst") "6e30a58bbf3bfb4f05439a3f0791cecc4d6504d75c8a48b7381ce25de2420767") "rg1c3p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c3p1-type0.zst") "c0f3296d82ab5340585967cac082b171c7316762879094627f64d74b11aa7fe5") "rg1c3p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c4p0-type2.zst") "b15348c8f462384c01e83b6d499c6faf3f96808f5aa07c6bab4b65b36b4445d4") "rg1c4p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg1c4p1-type0.zst") "1de44df09dd97c97bea5fc4b7e7a3e5b69ef7265317d5b2e34bf9f254c39ea75") "rg1c4p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c0p0-type2.zst") "a742b38973cfe31eb497a10a25f440b41dbaf6e210ef5c3b147379697ea239f5") "rg2c0p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c0p1-type0.zst") "db233051cd97e5b765e31d62cf574bbb82a0bed4189d599479a7fc20c76d3d59") "rg2c0p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c1p0-type2.zst") "51a3de22a3d058bc7c0b4e797dc41d4da07aeff4cf5ffef730700d7631ac192b") "rg2c1p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c1p1-type0.zst") "db233051cd97e5b765e31d62cf574bbb82a0bed4189d599479a7fc20c76d3d59") "rg2c1p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c2p0-type2.zst") "2a036c06f9d03cf0c8f12ca30f715d7470826ad73e670501c1a08dc6b67539b2") "rg2c2p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c2p1-type0.zst") "e91de24060cc4646471964d547b8fccdd22e1cfda100aa3f16bb5e15055cbba1") "rg2c2p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c3p0-type2.zst") "f9d7b3d233dea2ff1213578c1f9de192ef2e9353481525b1ae5546c06c51f259") "rg2c3p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c3p1-type0.zst") "54e690229ae04ed2cde5282f37a7a897f1e6916f8dff13412954c2aa25b467fa") "rg2c3p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c4p0-type2.zst") "3bdcf6187bab53fc6e18b7f3e8ea4a666f06f545460189157c6f1ef1e5d85ebc") "rg2c4p0-type2")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pages/rg2c4p1-type0.zst") "325123ebedae626047d389618a59c7060157762e3e7fe14dc4ebc2ca48157e80") "rg2c4p1-type0")
    (assert (= (decodeSha! "tests/acceptance/r1Host/fixtures/zstd/pos/crafted-rawBlockMax-control.zst") "6007c17e06a93c026df05f33f9df8ee3be5ba102830bf063d9ca8e00d43d2930") "control frame for malformed corpus")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/offsetBeyondWindow.zst") "offsetBeyondWindow exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/oversizedBlock.zst") "oversizedBlock exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-0.zst") "truncated-0 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-3.zst") "truncated-3 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-5.zst") "truncated-5 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-8.zst") "truncated-8 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-19705.zst") "truncated-19705 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-39406.zst") "truncated-39406 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/truncated-39410.zst") "truncated-39410 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/badMagic.zst") "badMagic exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/reservedBit.zst") "reservedBit exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/badWindowDescriptor.zst") "badWindowDescriptor exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/badChecksum.zst") "badChecksum exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/malformedHuffmanTree.zst") "malformedHuffmanTree exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/malformedFseTable.zst") "malformedFseTable exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-21226-0.zst") "flip-21226-0 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-25879-1.zst") "flip-25879-1 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-4751-2.zst") "flip-4751-2 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-23969-3.zst") "flip-23969-3 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-33259-4.zst") "flip-33259-4 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-2461-5.zst") "flip-2461-5 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-28423-6.zst") "flip-28423-6 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-4582-7.zst") "flip-4582-7 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-5948-8.zst") "flip-5948-8 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-3877-9.zst") "flip-3877-9 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-14634-10.zst") "flip-14634-10 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-37825-11.zst") "flip-37825-11 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-3253-12.zst") "flip-3253-12 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-3056-13.zst") "flip-3056-13 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-18983-14.zst") "flip-18983-14 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-9457-15.zst") "flip-9457-15 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-37419-16.zst") "flip-37419-16 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-36721-17.zst") "flip-36721-17 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-6757-18.zst") "flip-6757-18 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-24409-19.zst") "flip-24409-19 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-35900-20.zst") "flip-35900-20 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-36990-21.zst") "flip-36990-21 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-40571-22.zst") "flip-40571-22 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/flip-32537-23.zst") "flip-32537-23 exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/dictionaryId.zst") "dictionaryId exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/skippableFrame.zst") "skippableFrame exact error parity")
    (assert (isErr! "tests/acceptance/r1Host/fixtures/zstd/neg/multiFrame.zst") "multiFrame exact error parity")
    (assert (isUnsupported! "tests/acceptance/r1Host/fixtures/zstd/neg/dictionaryId.zst") "dictionaryId remains unsupported")
    (assert (isUnsupported! "tests/acceptance/r1Host/fixtures/zstd/neg/skippableFrame.zst") "skippableFrame remains unsupported")
    (assert (isUnsupported! "tests/acceptance/r1Host/fixtures/zstd/neg/multiFrame.zst") "multiFrame remains unsupported")
    true)
