(module asl-codec/compactNotationsTest
  :d "Unit verification test suite for compact tabular, DAG pyramid, and sparkline codecs."
  :x [testTableCodec
      testTableSavings
      testDagPyramid
      testSparklineCodec
      testSparklineAscii
      testEdgeCases
      runTests]
  :i [(asl-codec/compactNotations :a cn)])

(df testTableCodec [] -> Bool
  :d "Verifies tabular ASN encoding, decoding, roundtrip, and markdown rendering."
  (let [(tbl (cn/TableData :cols (list "pkg" "ver" "status")
                           :rows (list (list "asl-codec" "0.1.0" "active")
                                       (list "asl-parser" "0.1.0" "ready"))))
        (enc (cn/encodeDenseTable tbl))
        (dec (cn/decodeDenseTable enc))
        (md (cn/tableToMarkdown tbl))
        (emptyTbl (cn/TableData :cols (list) :rows (list)))
        (emptyEnc (cn/encodeDenseTable emptyTbl))
        (emptyDec (cn/decodeDenseTable emptyEnc))]
    (assert (string-starts-with? enc "(:tbl :cols [\"pkg\" \"ver\" \"status\"] :rows [") "encoded starts with cols")
    (assert (string-contains? enc "[\"asl-codec\" \"0.1.0\" \"active\"]") "contains row data")
    (assert (is-ok? dec) "decode valid table succeeds")
    (assert (string-contains? md "| pkg | ver | status |") "markdown contains headers")
    (assert (string-contains? md "| --- | --- | --- |") "markdown contains separator")
    (assert (is-ok? emptyDec) "empty table decodes successfully")
    (assert (not (is-ok? (cn/decodeDenseTable "(:not-a-table)"))) "reject malformed table")
    true))

(df testTableSavings [] -> Bool
  :d "Verifies token compaction savings calculation >= 70%."
  (let [(tbl (cn/TableData :cols (list "service" "region" "replicas" "latency_p99" "cpu_util")
                           :rows (list (list "gateway" "us-east-1" "12" "4.2ms" "38%")
                                       (list "auth-api" "us-east-1" "8" "1.8ms" "24%")
                                       (list "data-store" "us-east-1" "24" "8.5ms" "62%")
                                       (list "cache-layer" "us-east-1" "16" "0.6ms" "18%"))))
        (savings (cn/measureTableSavings tbl))
        (emptyTbl (cn/TableData :cols (list) :rows (list)))
        (emptySavings (cn/measureTableSavings emptyTbl))]
    (assert (>= savings 70.0) "table savings >= 70%")
    (assert (= emptySavings 0.0) "empty table savings is 0.0")
    (assert (not (< savings 50.0)) "table savings is not below threshold")
    true))

(df testDagPyramid [] -> Bool
  :d "Verifies hierarchical DAG pyramid encoding, decoding, and roundtrip."
  (let [(pyr (cn/DagPyramid :root "main"
                            :deps (list (cn/DagNode :id "main" :deps (list "parse" "check"))
                                        (cn/DagNode :id "parse" :deps (list "lex"))
                                        (cn/DagNode :id "check" :deps (list))
                                        (cn/DagNode :id "lex" :deps (list)))))
        (enc (cn/encodeDagPyramid pyr))
        (dec (cn/decodeDagPyramid enc))
        (emptyPyr (cn/DagPyramid :root "leaf" :deps (list)))
        (emptyEnc (cn/encodeDagPyramid emptyPyr))
        (emptyDec (cn/decodeDagPyramid emptyEnc))]
    (assert (string-starts-with? enc "(:dag :root \"main\" :deps [") "encoded root")
    (assert (string-contains? enc "(:node :id \"main\" :deps [\"parse\" \"check\"])") "main node")
    (assert (is-ok? dec) "decode valid dag succeeds")
    (assert (is-ok? emptyDec) "decode empty dag succeeds")
    (assert (not (is-ok? (cn/decodeDagPyramid "(:not-a-dag)"))) "reject invalid dag")
    true))

(df testSparklineCodec [] -> Bool
  :d "Verifies telemetry sparkline metric encoding, decoding, and roundtrip."
  (let [(m (cn/SparkMetric :metric "rss_mb" :vals (list 128.5 135.2 142.0 139.8 150.1)))
        (enc (cn/encodeSparklineMetric m))
        (dec (cn/decodeSparklineMetric enc))
        (emptyM (cn/SparkMetric :metric "counter" :vals (list)))
        (emptyEnc (cn/encodeSparklineMetric emptyM))
        (emptyDec (cn/decodeSparklineMetric emptyEnc))]
    (assert (string-starts-with? enc "(:spark :metric \"rss_mb\" :vals [") "encoded sparkline metric")
    (assert (string-contains? enc "128.5") "contains first val")
    (assert (is-ok? dec) "decode valid sparkline succeeds")
    (assert (is-ok? emptyDec) "decode empty sparkline succeeds")
    (assert (not (is-ok? (cn/decodeSparklineMetric "(:not-a-spark)"))) "reject invalid sparkline")
    true))

(df testSparklineAscii [] -> Bool
  :d "Verifies Unicode 8-level ASCII sparkline quantization across edge cases."
  (let [(emptyRes (cn/renderSparklineAscii (list)))
        (singleRes (cn/renderSparklineAscii (list 42.0)))
        (flatRes (cn/renderSparklineAscii (list 10.0 10.0 10.0 10.0)))
        (rampRes (cn/renderSparklineAscii (list 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0)))
        (dynRes (cn/renderSparklineAscii (list 10.0 30.0 20.0 50.0 40.0)))]
    (assert (= emptyRes "") "empty list produces empty sparkline")
    (assert (= singleRes "▄") "single value mid block")
    (assert (= flatRes "▄▄▄▄") "flat values mid blocks")
    (assert (= rampRes " ▂▃▄▅▆▇█") "ramp values full range")
    (assert (= (string-length dynRes) 5) "dynamic length matches")
    (assert (not (= (string-length rampRes) 0)) "ramp sparkline is not empty")
    true))

(df testEdgeCases [] -> Bool
  :d "Verifies rejection of corrupt inputs, empty inputs, and roundtrips."
  (let [(singleM (cn/SparkMetric :metric "single" :vals (list 100.0)))
        (roundtrip (cn/decodeSparklineMetric (cn/encodeSparklineMetric singleM)))]
    (assert (is-ok? roundtrip) "valid single metric roundtrip succeeds")
    (assert (not (is-ok? (cn/decodeDenseTable "(:not-a-table)"))) "reject not a table")
    (assert (not (is-ok? (cn/decodeDenseTable ""))) "reject empty table string")
    (assert (not (is-ok? (cn/decodeDagPyramid "(:not-a-dag)"))) "reject not a dag")
    (assert (not (is-ok? (cn/decodeDagPyramid ""))) "reject empty dag string")
    (assert (not (is-ok? (cn/decodeSparklineMetric "(:not-a-spark)"))) "reject not a spark")
    (assert (not (is-ok? (cn/decodeSparklineMetric ""))) "reject empty spark string")
    true))

(df runTests [] -> Bool
  :d "Executes all compact notations verification assertions."
  (do
    (assert (testTableCodec) "table codec")
    (assert (testTableSavings) "table savings")
    (assert (testDagPyramid) "dag pyramid")
    (assert (testSparklineCodec) "sparkline codec")
    (assert (testSparklineAscii) "sparkline ascii")
    (assert (testEdgeCases) "edge cases")
    true))
