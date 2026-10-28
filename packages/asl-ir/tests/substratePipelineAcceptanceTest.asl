(module asl-ir/tests/substratePipelineAcceptanceTest
  :x [runTests RunTests testSubstratePipeline testSubstrateRefutations]
  :i [(asl-ir/patch :a patch)
      (asl-ir/types :a irTy)
      (asl-hypergraph/model :a hyper)
      (asl-derive/derive :a der)
      (aslConform/types :a conf)
      (asl-target-c :a tc)])

fn bytesSameFrom? a: Bytes b: Bytes i: Int64 -> Bool
  (if (>= i (bytesLength a))
    true
    (and (= (bytesGet a i) (bytesGet b i)) (bytesSameFrom? a b (+ i 1))))

fn bytesSame? a: Bytes b: Bytes -> Bool
  (and (= (bytesLength a) (bytesLength b)) (bytesSameFrom? a b 0))

fn testSubstratePipeline -> Bool
  (let [(d (patch/computeAstDigest "(module sample)"))
        (bytes (stringToBytes "SubstrateDataBlock"))
        (writable (bytesAlloc 3))
        (node (hyper/makeHyperNode "pkg/core:run" "function" "pkg/core" "run" "executes run"))
        (f1 (der/makeField "id" "I64" false))
        (schema (der/makeRecordSchema "Entity" "entities" (some "id") (list f1)))
        (prof (conf/makeProfile "c11" "C11 Standalone" "clang" "essential"))
        (cType (tc/emitC11Type (irTy/makeIrType "i64" "raw" false)))]
    (do
    (bytesSet writable 0 65)
    (bytesSet writable 1 83)
    (bytesSet writable 2 76)
    (assert (stringStartsWith? d "d") "AST digest starts with d")
    (refute (not (stringStartsWith? d "d")) "AST digest refutes non-d prefix")
    (assert (= (bytesLength bytes) 18) "Bytes API reports substrate byte length")
    (assert (= (bytesGet bytes 0) 83) "Bytes API reads the first substrate byte")
    (assert (= (bytesGet bytes 8) 101) "Bytes API reads the final byte of Substrate")
    (assert (= (bytesGet writable 2) 76) "Bytes API writes and reads a byte")
    (refute (!= (bytesGet writable 2) 76) "Bytes API write refutes a different value")
    (assert (bytesSame? writable (stringToBytes "ASL")) "written buffer equals the whole ASL buffer")
    (assert (= node.symbol "run") "hypernode symbol is run")
    (refute (!= node.symbol "run") "hypernode symbol refutes non-run")
    (assert (= schema.name "Entity") "derived schema name is Entity")
    (assert (= prof.id "c11") "conformance profile id is c11")
    (assert (= cType "int64_t") "target-c i64 type is int64_t")
    (refute (!= cType "int64_t") "target-c i64 refutes non-int64_t")
    true))

fn testSubstrateRefutations -> Bool
  (let [(d1 (patch/computeAstDigest "(module A)"))
        (d2 (patch/computeAstDigest "(module B)"))
        (s1 (stringToBytes "AB"))
        (s2 (stringToBytes "BB"))
        (s3 (stringToBytes "AC"))]
    (assert (!= d1 d2) "digests for different modules are not equal")
    (refute (= d1 d2) "digests refute equality")
    (assert (bytesSame? s1 (stringToBytes "AB")) "equal byte buffers compare equal")
    (refute (bytesSame? s1 s2) "buffers differing at the first byte refute equality")
    (refute (bytesSame? s1 s3) "buffers differing only at the last byte refute equality")
    true)

fn runTests -> Bool
  (do
    (assert (testSubstratePipeline) "testSubstratePipeline passed")
    (assert (testSubstrateRefutations) "testSubstrateRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
