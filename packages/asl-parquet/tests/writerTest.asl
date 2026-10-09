(module asl-parquet/tests/writerTest
  :x [runTests]
  :i [(asl-parquet/writer :a pq) (asl-parquet/footer :a foot)])

fn checkCanonical! h: ParquetHandle path: String -> Bool
  (do
    (assert (= (parquetNumRows h) 5) "canonical row count")
    (assert (= (i64ArrayGet (parquetReadI64 h "tsUs" 0) 4) 1759276807264124) "tsUs round trips exactly")
    (assert (= (i64ArraySum (parquetReadI64 h "price" 0)) 138160) "price ticks round trip exactly")
    (assert (resultOr (resultMap (foot/parquetColumnEncodings path "tsUs" 0) (fn [xs] (listContains? xs "DELTA_BINARY_PACKED"))) false) "footer records DELTA_BINARY_PACKED")
    (assert (resultOr (resultMap (foot/parquetColumnEncodings path "price" 0) (fn [xs] (listContains? xs "BYTE_STREAM_SPLIT"))) false) "footer records BYTE_STREAM_SPLIT")
    (assert (= (resultOr (foot/parquetColumnCompression path "price" 0) "") "ZSTD") "footer records ZSTD")
    (assert (not (resultOr (foot/parquetColumnHasDictionary path "price" 0) true)) "no dictionary page")
    (assert (= (resultOr (foot/parquetKvMetadata path "vtbot.dataset") "") "{\"schema\": \"vtbot.dataset.v1\"}") "key-value metadata round trips")
    (assert (= (resultOr (foot/parquetKvMetadata path "asl.parquet.zstd.level") "") "19") "footer records the applied ZSTD level")
    true)

fn assertPyArrow! path: String -> Bool
  (let [(probe (processRun "python3 -c 'import pyarrow.parquet'"))]
    (do
      (assert (= probe.exitCode 0) "pyarrow is required for Parquet interoperability")
      (let [(read (processRun (str "python3 -c 'import pyarrow.parquet as p; t=p.read_table(\"" path "\"); assert t.column(\"tsUs\").to_pylist()==[1759276807264120,1759276807264121,1759276807264122,1759276807264123,1759276807264124]; assert sum(t.column(\"price\").to_pylist())==138160; e=p.ParquetFile(\"" path "\").metadata.row_group(0).column(0).encodings; assert \"PLAIN\" in e and \"DELTA_BINARY_PACKED\" in e'")))]
        (do (assert (= read.exitCode 0) "pyarrow reads canonical values and encoding metadata") true))))

fn varyingTimestampAt index: Int64 current: Int64 -> Int64
  (if (= index 0) current
    (let [(mini (mod (/ (- index 1) 32) 4))
          (range (cond ((= mini 0) 4) ((= mini 1) 8) ((= mini 2) 16) (else 32)))
          (delta (+ 1 (mod index range)))]
      (if (= index 1) (+ current delta)
        (+ (varyingTimestampAt (- index 1) current) delta))))

fn ! assertI64Array! expected: I64Array actual: I64Array index: Int64 -> Bool
  (if (= index (i64ArrayLen expected)) true
    (and (= (i64ArrayGet expected index) (i64ArrayGet actual index))
      (assertI64Array! expected actual (+ index 1))))

fn testVaryingDeltaBlocks! -> Bool
  (let [(path "/tmp/aslParquetVaryingDelta.parquet")
        (values (i64ArrayGenerate 385 (fn [i] (varyingTimestampAt i 1759276807264120))))
        (columns (list (pq/i64Column "tsUs" values "DELTA_BINARY_PACKED")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "385")))
        (written (pq/parquetWrite path columns options (list)))
        (probe (processRun "python3 -c 'import pyarrow.parquet'"))]
    (do
      (assert (ok? written) "varying multi-block deltas write")
      (mt (parquetOpen path)
        ((err e) (assert false (str "varying-delta host open failed: " e)))
        ((ok h)
          (let [(actual (parquetReadI64 h "tsUs" 0))
        (read (processRun (str "python3 -c 'import pyarrow.parquet as p; a=p.read_table(\"" path "\").column(\"tsUs\").to_pylist(); e=[1759276807264120]; [e.append(e[-1]+1+(j%(2**(2+((j-1)//32)%4)))) for j in range(1,385)]; assert a==e'")))]
            (do
              (assert (assertI64Array! values actual 0) "host reader returns all 385 varying timestamps")
              (assert (= probe.exitCode 0) "pyarrow is required for varying-delta interoperability")
              (assert (= read.exitCode 0) "pyarrow returns all 385 varying timestamps")
              (assert (ok? (pathRemove path)) "varying-delta cleanup succeeds")
              true))))))

fn testDeltaFloatAndInt8! -> Bool
  (let [(path "/tmp/aslParquetPQWRITEVariants.parquet")
        (delta (i64ArrayGenerate 3 (fn [i] (cond ((= i 0) 0) ((= i 1) 1) (else 4)))))
        (measure (f64ArrayGenerate 3 (fn [i] (cond ((= i 0) 1.25) ((= i 1) -2.5) (else 3.75)))))
        (small (i8ArrayGenerate 3 (fn [i] (cond ((= i 0) -3) ((= i 1) 0) (else 7)))))
        (columns (list (pq/i64Column "delta" delta "DELTA_BINARY_PACKED")
                       (pq/f64Column "measure" measure "PLAIN")
                       (pq/i8Column "small" small "PLAIN")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "3")))
        (written (pq/parquetWrite path columns options (list)))
        (probe (processRun "python3 -c 'import pyarrow.parquet'"))]
    (do
      (assert (ok? written) "varying delta and typed columns write")
      (assert (= probe.exitCode 0) "pyarrow is required for Parquet interoperability")
      (let [(read (processRun (str "python3 -c 'import pyarrow.parquet as p; t=p.read_table(\"" path "\"); assert t.column(\"delta\").to_pylist()==[0,1,4]; assert t.column(\"measure\").to_pylist()==[1.25,-2.5,3.75]; assert t.column(\"small\").to_pylist()==[-3,0,7]; e=p.ParquetFile(\"" path "\").metadata.row_group(0).column(0).encodings; assert \"PLAIN\" in e and \"DELTA_BINARY_PACKED\" in e'")))
            (typeCheck (processRun (str "python3 -c 'import pyarrow as a, pyarrow.parquet as p; assert p.read_table(\"" path "\").schema.field(\"small\").type==a.int8()'")))]
        (do
          (assert (= read.exitCode 0) "pyarrow reads varying delta, f64, i8, and encoding list")
          (assert (= typeCheck.exitCode 0) "pyarrow reports i8 columns as INT_8")
          (assert (ok? (pathRemove path)) "variant cleanup succeeds")
          true))))

fn testDeltaSmallGap! -> Bool
  (let [(path "/tmp/aslParquetDeltaSmallGap.parquet")
        (values (i64ArrayGenerate 3 (fn [i] (cond ((= i 0) 1759276807264120) ((= i 1) 1759276807264121) (else 1759276807274121)))))
        (columns (list (pq/i64Column "tsUs" values "DELTA_BINARY_PACKED")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "3")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "three-row timestamp with 10ms gap writes")
      (mt (parquetOpen path)
        ((err e) (assert false (str "small-gap host open failed: " e)))
        ((ok h)
          (do
            (assert (assertI64Array! values (parquetReadI64 h "tsUs" 0) 0) "three-row timestamp with 10ms gap round trips")
            (assert (ok? (pathRemove path)) "small-gap cleanup succeeds")
            true)))))

fn testDeltaHundredMillisecondGaps! -> Bool
  (let [(path "/tmp/aslParquetDeltaHundredMs.parquet")
        (values (i64ArrayGenerate 128 (fn [i]
          (+ 1759276807264120 (* i 100000) (* (/ i 2) 200000)))))
        (columns (list (pq/i64Column "tsUs" values "DELTA_BINARY_PACKED")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "128")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "128 microsecond timestamps with alternating 100ms/300ms gaps write")
      (mt (parquetOpen path)
        ((err e) (assert false (str "100ms-gap host open failed: " e)))
        ((ok h) (do
          (assert (assertI64Array! values (parquetReadI64 h "tsUs" 0) 0) "100ms-gap timestamps round trip")
          (assert (ok? (pathRemove path)) "100ms-gap cleanup succeeds")
          true)))))

fn testLongNameFooter! -> Bool
  (let [(path "/tmp/aslParquetLongNameFooter.parquet")
        (name (stringRepeat "longName" 200))
        (values (i64ArrayGenerate 6 (fn [i] (+ i 10))))
        (columns (list (pq/i64Column name values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "1")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "long-name six-row-group Parquet write succeeds")
      (mt (parquetOpen path)
        ((err e) (assert false (str "long-name footer host open failed: " e)))
        ((ok h) (do
          (assert (= (parquetNumRowGroups h) 6) "long-name footer retains six row groups")
          (assert (= (parquetNumRows h) 6) "long-name footer retains all rows")
          (assert (ok? (pathRemove path)) "long-name cleanup succeeds")
          true)))))

fn testZigzagBoundary! -> Bool
  (let [(path "/tmp/aslParquetZigzagBoundary.parquet")
        (positiveBase 4611686018427387904)
        (negativeBase -4611686018427387904)
        (positive (i64ArrayGenerate 3 (fn [i] (+ positiveBase i))))
        (negative (i64ArrayGenerate 3 (fn [i] (+ negativeBase i))))
        (columns (list (pq/i64Column "widePositive" positive "DELTA_BINARY_PACKED")
                       (pq/i64Column "wideNegative" negative "DELTA_BINARY_PACKED")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "3")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "delta streams with positive and negative 2^62-scale values write without zigzag overflow")
      (mt (parquetOpen path)
        ((err e) (assert false (str "wide-value host open failed: " e)))
        ((ok h) (do
          (assert (assertI64Array! positive (parquetReadI64 h "widePositive" 0) 0) "positive 2^62-scale values round trip")
          (assert (assertI64Array! negative (parquetReadI64 h "wideNegative" 0) 0) "negative 2^62-scale values round trip")
          (assert (ok? (pathRemove path)) "wide-value cleanup succeeds")
          true)))))

fn testFifteenElementCompactList! -> Bool
  (let [(path "/tmp/aslParquetFifteenElementList.parquet")
        (values (i64ArrayGenerate 2 (fn [i] (+ i 10))))
        (columns (list (pq/i64Column "c00" values "PLAIN") (pq/i64Column "c01" values "PLAIN")
          (pq/i64Column "c02" values "PLAIN") (pq/i64Column "c03" values "PLAIN")
          (pq/i64Column "c04" values "PLAIN") (pq/i64Column "c05" values "PLAIN")
          (pq/i64Column "c06" values "PLAIN") (pq/i64Column "c07" values "PLAIN")
          (pq/i64Column "c08" values "PLAIN") (pq/i64Column "c09" values "PLAIN")
          (pq/i64Column "c10" values "PLAIN") (pq/i64Column "c11" values "PLAIN")
          (pq/i64Column "c12" values "PLAIN") (pq/i64Column "c13" values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "2")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "14-column file with 15-element schema list writes")
      (mt (parquetOpen path)
        ((err e) (assert false (str "15-element schema list host open failed: " e)))
        ((ok h) (do
          (assert (= (parquetNumRows h) 2) "14-column file row count")
          (assert (assertI64Array! values (parquetReadI64 h "c13" 0) 0) "14th column round trips")
          (assert (ok? (pathRemove path)) "14-column cleanup succeeds")
          true)))))

fn testDecreasingDelta! -> Bool
  (let [(path "/tmp/aslParquetDecreasingDelta.parquet")
        (values (i64ArrayGenerate 5 (fn [i] (cond ((= i 0) 1000) ((= i 1) 999) ((= i 2) 900) ((= i 3) 899) (else 700)))))
        (columns (list (pq/i64Column "decreasing" values "DELTA_BINARY_PACKED")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "5")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "decreasing delta values write")
      (mt (parquetOpen path)
        ((err e) (assert false (str "decreasing-delta host open failed: " e)))
        ((ok h)
          (do
            (assert (assertI64Array! values (parquetReadI64 h "decreasing" 0) 0) "decreasing delta values round trip")
            (assert (ok? (pathRemove path)) "decreasing-delta cleanup succeeds")
            true)))))

fn testManyColumns! -> Bool
  (let [(path "/tmp/aslParquetManyColumns.parquet")
        (values (i64ArrayGenerate 2 (fn [i] (+ i 10))))
        (columns (list (pq/i64Column "c00" values "PLAIN") (pq/i64Column "c01" values "PLAIN")
          (pq/i64Column "c02" values "PLAIN") (pq/i64Column "c03" values "PLAIN")
          (pq/i64Column "c04" values "PLAIN") (pq/i64Column "c05" values "PLAIN")
          (pq/i64Column "c06" values "PLAIN") (pq/i64Column "c07" values "PLAIN")
          (pq/i64Column "c08" values "PLAIN") (pq/i64Column "c09" values "PLAIN")
          (pq/i64Column "c10" values "PLAIN") (pq/i64Column "c11" values "PLAIN")
          (pq/i64Column "c12" values "PLAIN") (pq/i64Column "c13" values "PLAIN")
          (pq/i64Column "c14" values "PLAIN") (pq/i64Column "c15" values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "2")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "16-column Parquet write succeeds")
      (mt (parquetOpen path)
        ((err e) (assert false (str "16-column host open failed: " e)))
        ((ok h)
          (do
            (assert (= (parquetNumRows h) 2) "16-column file row count")
            (assert (assertI64Array! values (parquetReadI64 h "c15" 0) 0) "last of 16 columns round trips across compact-list boundary")
            (assert (resultOr (resultMap (foot/parquetColumnEncodings path "c15" 0) (fn [xs] (listContains? xs "PLAIN"))) false) "16th column footer encoding")
            (assert (ok? (pathRemove path)) "many-column cleanup succeeds")
            true)))))

fn testZstdLevelAffectsFrame! -> Bool
  (let [(lowPath "/tmp/aslParquetZstdLevel1.parquet")
        (highPath "/tmp/aslParquetZstdLevel19.parquet")
        (values (i64ArrayGenerate 100000 (fn [i] (* (mod i 1000) (mod (/ i 1000) 251)))))
        (columns (list (pq/i64Column "x" values "PLAIN")))
        (lowOptions (list (list "compression" "zstd") (list "level" "1") (list "dictionary" "false") (list "rowGroupRows" "100000")))
        (highOptions (list (list "compression" "zstd") (list "level" "19") (list "dictionary" "false") (list "rowGroupRows" "100000")))
        (low (pq/parquetWrite lowPath columns lowOptions (list)))
        (high (pq/parquetWrite highPath columns highOptions (list)))
        (lowSize (resultOr (fileSize lowPath) 0))
        (highSize (resultOr (fileSize highPath) 0))]
    (do
      (assert (and (ok? low) (ok? high)) "ZSTD files at levels 1 and 19 write")
      (assert (or (> lowSize (+ highSize 16)) (> highSize (+ lowSize 16))) "configured ZSTD level changes compressed file size beyond footer metadata")
      (assert (= (resultOr (foot/parquetKvMetadata lowPath "asl.parquet.zstd.level") "") "1") "level-1 footer metadata")
      (assert (= (resultOr (foot/parquetKvMetadata highPath "asl.parquet.zstd.level") "") "19") "level-19 footer metadata")
      (assert (and (ok? (pathRemove lowPath)) (ok? (pathRemove highPath))) "ZSTD level fixtures cleanup succeeds")
      true))

fn testDictionaryDetection! -> Bool
  (let [(path "/tmp/aslParquetPQWRITEDictionaryFixture.parquet")
        (bytePath "/tmp/aslParquetCompactByteFixture.parquet")
        (write (processRun (str "python3 -c 'import pyarrow as a, pyarrow.parquet as p; p.write_table(a.table({\"x\":[1,1,2,2]}), \"" path "\", use_dictionary=True)'")))
        (byteWrite (processRun (str "python3 -c 'import pyarrow as a, pyarrow.parquet as p, struct; t=a.table({\"x\":[1,1,2,2]}).replace_schema_metadata({b\"fixture\":b\"present\"}); p.write_table(t, \"" bytePath "\"); b=open(\"" bytePath "\",\"rb\").read(); n=struct.unpack(\"<I\",b[-8:-4])[0]; s=len(b)-8-n; f=b[s:s+n]; q=f.rindex(b\"fixture\"); h=f.rfind(bytes([25,28]),0,q); assert h>=0; f=f[:h]+bytes([3,208,15,255,9,10])+f[h+1:]; open(\"" bytePath "\",\"wb\").write(b[:s]+f+struct.pack(\"<I\",len(f))+b\"PAR1\")'")))]
    (do
      (assert (= write.exitCode 0) "pyarrow dictionary fixture writes")
      (assert (= byteWrite.exitCode 0) "pyarrow compact-byte fixture writes")
      (assert (resultOr (foot/parquetColumnHasDictionary path "x" 0) false) "footer recognizes dictionary encoding")
      (assert (= (resultOr (foot/parquetKvMetadata bytePath "fixture") "") "present") "footer parses metadata after a raw compact byte field")
      (assert (ok? (pathRemove path)) "dictionary fixture cleanup succeeds")
      (assert (ok? (pathRemove bytePath)) "compact-byte fixture cleanup succeeds")
      true))

fn testCanonical! -> Bool
  (let [(path "/tmp/aslParquetCanonical.parquet")
        (ts (i64ArrayGenerate 5 (fn [i] (+ 1759276807264120 i))))
        (price (i64ArrayGenerate 5 (fn [i]
          (cond ((= i 0) 27630) ((= i 1) 27631) (else 27633)))))
        (columns (list (pq/i64Column "tsUs" ts "DELTA_BINARY_PACKED") (pq/i64Column "price" price "BYTE_STREAM_SPLIT")))
        (options (list (list "compression" "zstd") (list "level" "19") (list "dictionary" "false") (list "rowGroupRows" "1000000")))
        (metadata (list (list "vtbot.dataset" "{\"schema\": \"vtbot.dataset.v1\"}")))
        (written (pq/parquetWrite path columns options metadata))]
    (do
      (assert (ok? written) "canonical Parquet write succeeds")
      (let [(opened (parquetOpen path))]
        (mt opened
          ((err e) (assert false (str "host parquet open failed: " e)))
          ((ok h) (do
            (checkCanonical! h path)
            (assertPyArrow! path)
            (assert (ok? (pathRemove path)) "canonical cleanup succeeds")
            true))))))

fn testLargeRowGroups! -> Bool
  (let [(path "/tmp/aslParquetLarge.parquet")
        (values (i64ArrayGenerate 250000 (fn [i] (+ 1000000 i))))
        (columns (list (pq/i64Column "tsUs" values "DELTA_BINARY_PACKED")))
        (options (list (list "compression" "zstd") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" "100000")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "large row-group write succeeds")
      (let [(opened (parquetOpen path))]
        (do
          (assert (resultOr (resultMap opened (fn [h] (= (parquetNumRows h) 250000))) false) "large file has 250000 rows")
          (assert (resultOr (resultMap opened (fn [h] (= (parquetNumRowGroups h) 3))) false) "large file has three row groups")
          (assert (resultOr (resultMap opened (fn [h] (and (= (i64ArrayGet (parquetReadI64 h "tsUs" 0) 0) 1000000) (= (i64ArrayGet (parquetReadI64 h "tsUs" 0) 99999) 1099999) (= (i64ArrayGet (parquetReadI64 h "tsUs" 1) 0) 1100000) (= (i64ArrayGet (parquetReadI64 h "tsUs" 2) 49999) 1249999)))) false) "all row-group boundaries round trip exactly")
          (assert (ok? (pathRemove path)) "large cleanup succeeds")
          true))))

fn testZstdFrameSizes! -> Bool
  (let [(smallPath "/tmp/aslParquetZstd256.parquet")
        (largePath "/tmp/aslParquetZstd65752.parquet")
        (smallPlain "/tmp/aslParquetPlain256.parquet")
        (largePlain "/tmp/aslParquetPlain65752.parquet")
        (small (i64ArrayGenerate 32 (fn [i] 0)))
        (large (i64ArrayGenerate 8219 (fn [i] 0)))
        (smallColumn (list (pq/i64Column "x" small "PLAIN")))
        (largeColumn (list (pq/i64Column "x" large "PLAIN")))
        (zstd (list (list "compression" "zstd") (list "level" "19") (list "dictionary" "false") (list "rowGroupRows" "8219")))
        (plain (list (list "compression" "none") (list "level" "19") (list "dictionary" "false") (list "rowGroupRows" "8219")))
        (writeSmall (pq/parquetWrite smallPath smallColumn zstd (list)))
        (writeLarge (pq/parquetWrite largePath largeColumn zstd (list)))
        (writeSmallPlain (pq/parquetWrite smallPlain smallColumn plain (list)))
        (writeLargePlain (pq/parquetWrite largePlain largeColumn plain (list)))
        (probe (processRun "python3 -c 'import pyarrow.parquet'"))]
    (do
      (assert (and (ok? writeSmall) (and (ok? writeLarge) (and (ok? writeSmallPlain) (ok? writeLargePlain)))) "ZSTD and uncompressed boundary fixtures write")
      (assert (< (resultOr (fileSize smallPath) 1000000) (resultOr (fileSize smallPlain) 0)) "ZSTD compresses a 256-byte page")
      (assert (< (resultOr (fileSize largePath) 1000000) (resultOr (fileSize largePlain) 0)) "ZSTD compresses a 65752-byte page")
      (assert (= (resultOr (foot/parquetKvMetadata smallPath "asl.parquet.zstd.level") "") "19") "small ZSTD frame records applied level")
      (assert (= (resultOr (foot/parquetKvMetadata largePath "asl.parquet.zstd.level") "") "19") "large ZSTD frame records applied level")
      (mt (parquetOpen smallPath)
        ((err e) (assert false (str "256-byte ZSTD page host open failed: " e)))
        ((ok smallHandle)
          (do
            (assert (= (i64ArraySum (parquetReadI64 smallHandle "x" 0)) 0) "host reads compressed 256-byte page")
            (mt (parquetOpen largePath)
              ((err e) (assert false (str "65752-byte ZSTD page host open failed: " e)))
              ((ok largeHandle)
                (do
                  (assert (= (i64ArrayLen (parquetReadI64 largeHandle "x" 0)) 8219) "host reads compressed 65752-byte page")
                  (assert (= probe.exitCode 0) "pyarrow is required for ZSTD frame-size interoperability")
                  (let [(read (processRun (str "python3 -c 'import pyarrow.parquet as p; assert p.read_table(\"" smallPath "\").column(\"x\").to_pylist()==[0]*32; assert p.read_table(\"" largePath "\").column(\"x\").to_pylist()==[0]*8219'")))]
                    (do
                      (assert (= read.exitCode 0) "pyarrow reads ZSTD frames with 256- and 65752-byte content sizes")
                      (assert (and (ok? (pathRemove smallPath)) (and (ok? (pathRemove largePath)) (and (ok? (pathRemove smallPlain)) (ok? (pathRemove largePlain))))) "ZSTD frame-size fixture cleanup succeeds")
                      true))))))))))

fn testRejectedInputs! -> Bool
  (let [(values (i64ArrayGenerate 2 (fn [i] i)))
        (f64 (f64ArrayGenerate 2 (fn [i] 1.0)))
        (options (list (list "compression" "zstd") (list "level" "19") (list "dictionary" "false") (list "rowGroupRows" "2")))
        (badLevelOptions (list (list "compression" "zstd") (list "level" "23") (list "dictionary" "false") (list "rowGroupRows" "2")))
        (unsupportedLevelOptions (list (list "compression" "zstd") (list "level" "20") (list "dictionary" "false") (list "rowGroupRows" "2")))
        (level22Options (list (list "compression" "zstd") (list "level" "22") (list "dictionary" "false") (list "rowGroupRows" "2")))
        (overflowValues (i64ArrayGenerate 2 (fn [i] (if (= i 0) (- 0 9223372036854775807) 9223372036854775807))))
        (wrongType (pq/parquetWrite "/tmp/aslParquetWrongType.parquet" (list (pq/f64Column "x" f64 "DELTA_BINARY_PACKED")) options (list)))
        (emptyName (pq/parquetWrite "/tmp/aslParquetEmptyName.parquet" (list (pq/i64Column "" values "DELTA_BINARY_PACKED")) options (list)))
        (badLevel (pq/parquetWrite "/tmp/aslParquetBadLevel.parquet" (list (pq/i64Column "x" values "DELTA_BINARY_PACKED")) badLevelOptions (list)))
        (unsupportedLevel (pq/parquetWrite "/tmp/aslParquetUnsupportedLevel.parquet" (list (pq/i64Column "x" values "PLAIN")) unsupportedLevelOptions (list)))
        (level22Write (pq/parquetWrite "/tmp/aslParquetLevel22.parquet" (list (pq/i64Column "x" values "PLAIN")) level22Options (list)))
        (overflowWrite (pq/parquetWrite "/tmp/aslParquetOverflow.parquet" (list (pq/i64Column "x" overflowValues "DELTA_BINARY_PACKED")) options (list)))
        (unwritable (pq/parquetWrite "/no/such/asl-parquet/out.parquet" (list (pq/i64Column "x" values "DELTA_BINARY_PACKED")) options (list)))]
    (do
      (assert (err? wrongType) "incompatible encoding and physical type rejected")
      (assert (err? emptyName) "empty column name rejected")
      (assert (err? badLevel) "ZSTD level outside 1..22 rejected")
      (assert (ok? unsupportedLevel) "ZSTD level 20 writes successfully")
      (assert (ok? level22Write) "ZSTD level 22 writes successfully")
      (assert (err? overflowWrite) "full-range INT64 delta returns Err instead of overflowing")
      (assert (err? unwritable) "unwritable target returns Err")
      true))

fn testLongFooterVarint! -> Bool
  (let [(path "/tmp/aslParquetLongFooterVarint.parquet")
        (values (i64ArrayGenerate 1 (fn [i] i)))
        (columns (list (pq/i64Column "x" values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "1") (list "dictionary" "false") (list "rowGroupRows" "1")))
        (written (pq/parquetWrite path columns options (list (list "fixture" "present"))))
        (patched (processRun (str "python3 -c 'import struct; p=\"" path "\"; b=bytearray(open(p,\"rb\").read()); n=struct.unpack(\"<I\",b[-8:-4])[0]; s=len(b)-8-n; f=bytes(b[s:-8]); q=f.index(b\"fixture\"); h=f.rfind(bytes([25,28]),0,q); assert h>=0; f=f[:h]+bytes([3]+[128]*9+[1,255,9,10])+f[h+1:]; open(p,\"wb\").write(b[:s]+f+struct.pack(\"<I\",len(f))+b\"PAR1\")'")))]
    (do
      (assert (ok? written) "long-varint fixture writes")
      (assert (= patched.exitCode 0) "10-byte compact varint fixture patches")
      (assert (= (resultOr (foot/parquetKvMetadata path "fixture") "") "present") "footer reader skips a 10-byte varint field")
      (assert (ok? (pathRemove path)) "long-varint fixture cleanup succeeds")
      true))

fn testUncompressed! -> Bool
  (let [(path "/tmp/aslParquetUncompressed.parquet")
        (values (i64ArrayGenerate 3 (fn [i] (+ i 4))))
        (columns (list (pq/i64Column "x" values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "1") (list "dictionary" "false") (list "rowGroupRows" "3")))
        (written (pq/parquetWrite path columns options (list))) ]
    (do
      (assert (ok? written) "uncompressed write succeeds")
      (mt (parquetOpen path)
        ((err e) (assert false (str "uncompressed output open failed: " e)))
        ((ok h) (do
          (assert (= (parquetNumRows h) 3) "uncompressed row count")
          (assert (= (i64ArraySum (parquetReadI64 h "x" 0)) 15) "uncompressed values round trip")
          (assert (= (resultOr (foot/parquetColumnCompression path "x" 0) "") "UNCOMPRESSED") "footer records uncompressed codec")
          (assert (ok? (pathRemove path)) "uncompressed cleanup succeeds")
          true)))))

fn testSchemaNamedColumn! -> Bool
  (let [(path "/tmp/aslParquetSchemaNamed.parquet")
        (values (i64ArrayGenerate 3 (fn [i] (+ i 4))))
        (columns (list (pq/i64Column "schema" values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "1") (list "dictionary" "false") (list "rowGroupRows" "3")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) "schema-named column write succeeds")
      (assert (= (resultOr (foot/parquetColumnCompression path "schema" 0) "") "UNCOMPRESSED") "column named schema is found in the footer")
      (assert (ok? (pathRemove path)) "schema-named cleanup succeeds")
      true))

fn ! runTests -> Bool
  (do
    (testSchemaNamedColumn!)
    (testRejectedInputs!)
    (testLongFooterVarint!)
    (testDeltaHundredMillisecondGaps!)
    (testLongNameFooter!)
    (testFifteenElementCompactList!)
    (testDeltaSmallGap!)
    (testDecreasingDelta!)
    (testZigzagBoundary!)
    (testManyColumns!)
    (testZstdLevelAffectsFrame!)
    (testVaryingDeltaBlocks!)
    (testCanonical!)
    (testDeltaFloatAndInt8!)
    (testDictionaryDetection!)
    (testLargeRowGroups!)
    (testZstdFrameSizes!)
    (testUncompressed!)
    true)
