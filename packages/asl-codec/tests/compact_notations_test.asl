(module asl-codec/compact-notations-test
  :d "Unit verification test suite for compact tabular, DAG pyramid, and sparkline codecs."
  :x [test-table-codec
      test-table-savings
      test-dag-pyramid
      test-sparkline-codec
      test-sparkline-ascii
      test-edge-cases
      run-tests]
  :i [(compact_notations :a cn)])

(df test-table-codec [] -> Bool
  :d "Verifies tabular ASN encoding, decoding, roundtrip, and markdown rendering."
  (let [(tbl (cn/TableData :cols (list "pkg" "ver" "status")
                           :rows (list (list "asl-codec" "0.1.0" "active")
                                       (list "asl-parser" "0.1.0" "ready"))))
        (enc (cn/encode-dense-table tbl))
        (dec (cn/decode-dense-table enc))
        (md (cn/table-to-markdown tbl))
        (empty-tbl (cn/TableData :cols (list) :rows (list)))
        (empty-enc (cn/encode-dense-table empty-tbl))
        (empty-dec (cn/decode-dense-table empty-enc))]
    (assert (string-starts-with? enc "(:tbl :cols [\"pkg\" \"ver\" \"status\"] :rows [") "encoded starts with cols")
    (assert (string-contains? enc "[\"asl-codec\" \"0.1.0\" \"active\"]") "contains row data")
    (assert (is-ok? dec) "decode valid table succeeds")
    (assert (string-contains? md "| pkg | ver | status |") "markdown contains headers")
    (assert (string-contains? md "| --- | --- | --- |") "markdown contains separator")
    (assert (is-ok? empty-dec) "empty table decodes successfully")
    (assert (not (is-ok? (cn/decode-dense-table "(:not-a-table)"))) "reject malformed table")
    true))

(df test-table-savings [] -> Bool
  :d "Verifies token compaction savings calculation >= 70%."
  (let [(tbl (cn/TableData :cols (list "service" "region" "replicas" "latency_p99" "cpu_util")
                           :rows (list (list "gateway" "us-east-1" "12" "4.2ms" "38%")
                                       (list "auth-api" "us-east-1" "8" "1.8ms" "24%")
                                       (list "data-store" "us-east-1" "24" "8.5ms" "62%")
                                       (list "cache-layer" "us-east-1" "16" "0.6ms" "18%"))))
        (savings (cn/measure-table-savings tbl))
        (empty-tbl (cn/TableData :cols (list) :rows (list)))
        (empty-savings (cn/measure-table-savings empty-tbl))]
    (assert (>= savings 70.0) "table savings >= 70%")
    (assert (= empty-savings 0.0) "empty table savings is 0.0")
    (assert (not (< savings 50.0)) "table savings is not below threshold")
    true))

(df test-dag-pyramid [] -> Bool
  :d "Verifies hierarchical DAG pyramid encoding, decoding, and roundtrip."
  (let [(pyr (cn/DagPyramid :root "main"
                            :deps (list (cn/DagNode :id "main" :deps (list "parse" "check"))
                                        (cn/DagNode :id "parse" :deps (list "lex"))
                                        (cn/DagNode :id "check" :deps (list))
                                        (cn/DagNode :id "lex" :deps (list)))))
        (enc (cn/encode-dag-pyramid pyr))
        (dec (cn/decode-dag-pyramid enc))
        (empty-pyr (cn/DagPyramid :root "leaf" :deps (list)))
        (empty-enc (cn/encode-dag-pyramid empty-pyr))
        (empty-dec (cn/decode-dag-pyramid empty-enc))]
    (assert (string-starts-with? enc "(:dag :root \"main\" :deps [") "encoded root")
    (assert (string-contains? enc "(:node :id \"main\" :deps [\"parse\" \"check\"])") "main node")
    (assert (is-ok? dec) "decode valid dag succeeds")
    (assert (is-ok? empty-dec) "decode empty dag succeeds")
    (assert (not (is-ok? (cn/decode-dag-pyramid "(:not-a-dag)"))) "reject invalid dag")
    true))

(df test-sparkline-codec [] -> Bool
  :d "Verifies telemetry sparkline metric encoding, decoding, and roundtrip."
  (let [(m (cn/SparkMetric :metric "rss_mb" :vals (list 128.5 135.2 142.0 139.8 150.1)))
        (enc (cn/encode-sparkline-metric m))
        (dec (cn/decode-sparkline-metric enc))
        (empty-m (cn/SparkMetric :metric "counter" :vals (list)))
        (empty-enc (cn/encode-sparkline-metric empty-m))
        (empty-dec (cn/decode-sparkline-metric empty-enc))]
    (assert (string-starts-with? enc "(:spark :metric \"rss_mb\" :vals [") "encoded sparkline metric")
    (assert (string-contains? enc "128.5") "contains first val")
    (assert (is-ok? dec) "decode valid sparkline succeeds")
    (assert (is-ok? empty-dec) "decode empty sparkline succeeds")
    (assert (not (is-ok? (cn/decode-sparkline-metric "(:not-a-spark)"))) "reject invalid sparkline")
    true))

(df test-sparkline-ascii [] -> Bool
  :d "Verifies Unicode 8-level ASCII sparkline quantization across edge cases."
  (let [(empty-res (cn/render-sparkline-ascii (list)))
        (single-res (cn/render-sparkline-ascii (list 42.0)))
        (flat-res (cn/render-sparkline-ascii (list 10.0 10.0 10.0 10.0)))
        (ramp-res (cn/render-sparkline-ascii (list 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0)))
        (dyn-res (cn/render-sparkline-ascii (list 10.0 30.0 20.0 50.0 40.0)))]
    (assert (= empty-res "") "empty list produces empty sparkline")
    (assert (= single-res "▄") "single value mid block")
    (assert (= flat-res "▄▄▄▄") "flat values mid blocks")
    (assert (= ramp-res " ▂▃▄▅▆▇█") "ramp values full range")
    (assert (= (string-length dyn-res) 5) "dynamic length matches")
    (assert (not (= (string-length ramp-res) 0)) "ramp sparkline is not empty")
    true))

(df test-edge-cases [] -> Bool
  :d "Verifies rejection of corrupt inputs, empty inputs, and roundtrips."
  (let [(single-m (cn/SparkMetric :metric "single" :vals (list 100.0)))
        (roundtrip (cn/decode-sparkline-metric (cn/encode-sparkline-metric single-m)))]
    (assert (is-ok? roundtrip) "valid single metric roundtrip succeeds")
    (assert (not (is-ok? (cn/decode-dense-table "(:not-a-table)"))) "reject not a table")
    (assert (not (is-ok? (cn/decode-dense-table ""))) "reject empty table string")
    (assert (not (is-ok? (cn/decode-dag-pyramid "(:not-a-dag)"))) "reject not a dag")
    (assert (not (is-ok? (cn/decode-dag-pyramid ""))) "reject empty dag string")
    (assert (not (is-ok? (cn/decode-sparkline-metric "(:not-a-spark)"))) "reject not a spark")
    (assert (not (is-ok? (cn/decode-sparkline-metric ""))) "reject empty spark string")
    true))

(df run-tests [] -> Bool
  :d "Executes all compact notations verification assertions."
  (do
    (assert (test-table-codec) "table codec")
    (assert (test-table-savings) "table savings")
    (assert (test-dag-pyramid) "dag pyramid")
    (assert (test-sparkline-codec) "sparkline codec")
    (assert (test-sparkline-ascii) "sparkline ascii")
    (assert (test-edge-cases) "edge cases")
    true))
