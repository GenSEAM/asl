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
    (and (string-starts-with? enc "(:tbl :cols [\"pkg\" \"ver\" \"status\"] :rows [")
         (and (string-contains? enc "[\"asl-codec\" \"0.1.0\" \"active\"]")
              (and (is-ok? dec)
                   (let [(val (result-or dec empty-tbl))]
                     (and (= (list-length (.-cols val)) 3)
                          (and (= (list-length (.-rows val)) 2)
                               (and (string-contains? md "| pkg | ver | status |")
                                    (and (string-contains? md "| --- | --- | --- |")
                                         (and (string-contains? md "| asl-codec | 0.1.0 | active |")
                                              (and (is-ok? empty-dec)
                                                   (= (list-length (.-cols (result-or empty-dec tbl))) 0)))))))))))))

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
    (and (>= savings 70.0)
         (= empty-savings 0.0))))

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
    (and (string-starts-with? enc "(:dag :root \"main\" :deps [")
         (and (string-contains? enc "(:node :id \"main\" :deps [\"parse\" \"check\"])")
              (and (string-contains? enc "(:node :id \"lex\" :deps [])")
                   (and (is-ok? dec)
                        (let [(val (result-or dec empty-pyr))]
                          (and (= (.-root val) "main")
                               (and (= (list-length (.-deps val)) 4)
                                    (and (is-ok? empty-dec)
                                         (= (.-root (result-or empty-dec pyr)) "leaf")))))))))))

(df test-sparkline-codec [] -> Bool
  :d "Verifies telemetry sparkline metric encoding, decoding, and roundtrip."
  (let [(m (cn/SparkMetric :metric "rss_mb" :vals (list 128.5 135.2 142.0 139.8 150.1)))
        (enc (cn/encode-sparkline-metric m))
        (dec (cn/decode-sparkline-metric enc))
        (empty-m (cn/SparkMetric :metric "counter" :vals (list)))
        (empty-enc (cn/encode-sparkline-metric empty-m))
        (empty-dec (cn/decode-sparkline-metric empty-enc))]
    (and (string-starts-with? enc "(:spark :metric \"rss_mb\" :vals [")
         (and (string-contains? enc "128.5")
              (and (string-contains? enc "150.1")
                   (and (is-ok? dec)
                        (let [(val (result-or dec empty-m))]
                          (and (= (.-metric val) "rss_mb")
                               (and (= (list-length (.-vals val)) 5)
                                    (and (is-ok? empty-dec)
                                         (= (list-length (.-vals (result-or empty-dec m))) 0)))))))))))

(df test-sparkline-ascii [] -> Bool
  :d "Verifies Unicode 8-level ASCII sparkline quantization across edge cases."
  (let [(empty-res (cn/render-sparkline-ascii (list)))
        (single-res (cn/render-sparkline-ascii (list 42.0)))
        (flat-res (cn/render-sparkline-ascii (list 10.0 10.0 10.0 10.0)))
        (ramp-res (cn/render-sparkline-ascii (list 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0)))
        (dyn-res (cn/render-sparkline-ascii (list 10.0 30.0 20.0 50.0 40.0)))]
    (and (= empty-res "")
         (and (= single-res "▄")
              (and (= flat-res "▄▄▄▄")
                   (and (= ramp-res " ▂▃▄▅▆▇█")
                        (and (= (string-length dyn-res) 5)
                             (and (string-starts-with? dyn-res " ")
                                  (string-contains? dyn-res "█")))))))))

(df test-edge-cases [] -> Bool
  :d "Verifies rejection of corrupt inputs, empty inputs, and roundtrips."
  (and (is-err? (cn/decode-dense-table "(:not-a-table)"))
       (and (is-err? (cn/decode-dense-table ""))
            (and (is-err? (cn/decode-dag-pyramid "(:not-a-dag)"))
                 (and (is-err? (cn/decode-dag-pyramid ""))
                      (and (is-err? (cn/decode-sparkline-metric "(:not-a-spark)"))
                           (and (is-err? (cn/decode-sparkline-metric ""))
                                (let [(single-m (cn/SparkMetric :metric "single" :vals (list 100.0)))
                                      (roundtrip (cn/decode-sparkline-metric (cn/encode-sparkline-metric single-m)))]
                                  (is-ok? roundtrip)))))))))

(df run-tests [] -> Bool
  :d "Executes all 32 compact notations verification assertions."
  (do
    (assert (test-table-codec))
    (assert (test-table-savings))
    (assert (test-dag-pyramid))
    (assert (test-sparkline-codec))
    (assert (test-sparkline-ascii))
    (assert (test-edge-cases))
    (assert (= (cn/render-sparkline-ascii (list)) ""))
    (assert (= (cn/render-sparkline-ascii (list 42.0)) "▄"))
    (assert (= (cn/render-sparkline-ascii (list 5.0 5.0 5.0)) "▄▄▄"))
    (assert (= (cn/render-sparkline-ascii (list 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0)) " ▂▃▄▅▆▇█"))
    (assert (string-starts-with? (cn/encode-dense-table (cn/TableData :cols (list "a" "b") :rows (list (list "1" "2")))) "(:tbl :cols ["))
    (assert (is-ok? (cn/decode-dense-table "(:tbl :cols [\"col1\"] :rows [[\"val1\"]])")))
    (assert (is-err? (cn/decode-dense-table "invalid")))
    (assert (is-err? (cn/decode-dense-table "")))
    (assert (string-contains? (cn/table-to-markdown (cn/TableData :cols (list "x" "y") :rows (list (list "1" "2")))) "| x | y |"))
    (assert (string-contains? (cn/table-to-markdown (cn/TableData :cols (list "x" "y") :rows (list (list "1" "2")))) "| --- | --- |"))
    (assert (>= (cn/measure-table-savings (cn/TableData :cols (list "service" "region" "replicas" "status") :rows (list (list "auth" "us-east-1" "4" "ok") (list "api" "us-east-1" "8" "ok")))) 70.0))
    (assert (= (cn/measure-table-savings (cn/TableData :cols (list) :rows (list))) 0.0))
    (assert (string-starts-with? (cn/encode-dag-pyramid (cn/DagPyramid :root "entry" :deps (list (cn/DagNode :id "entry" :deps (list "sub"))))) "(:dag :root \"entry\""))
    (assert (is-ok? (cn/decode-dag-pyramid "(:dag :root \"main\" :deps [(:node :id \"main\" :deps [\"a\"]) (:node :id \"a\" :deps [])])")))
    (assert (is-err? (cn/decode-dag-pyramid "invalid")))
    (assert (is-err? (cn/decode-dag-pyramid "")))
    (assert (= (.-root (result-or (cn/decode-dag-pyramid "(:dag :root \"core\" :deps [])") (cn/DagPyramid :root "" :deps (list)))) "core"))
    (assert (string-starts-with? (cn/encode-sparkline-metric (cn/SparkMetric :metric "cpu" :vals (list 1.0 2.0))) "(:spark :metric \"cpu\""))
    (assert (is-ok? (cn/decode-sparkline-metric "(:spark :metric \"mem\" :vals [10.5 20.0 30.2])")))
    (assert (is-err? (cn/decode-sparkline-metric "invalid")))
    (assert (is-err? (cn/decode-sparkline-metric "")))
    (assert (= (.-metric (result-or (cn/decode-sparkline-metric "(:spark :metric \"io\" :vals [1.0])") (cn/SparkMetric :metric "" :vals (list)))) "io"))
    (assert (= (list-length (.-vals (result-or (cn/decode-sparkline-metric "(:spark :metric \"io\" :vals [1.0 2.0 3.0])") (cn/SparkMetric :metric "" :vals (list))))) 3))
    (assert (is-ok? (cn/decode-sparkline-metric (cn/encode-sparkline-metric (cn/SparkMetric :metric "temp" :vals (list 98.6 99.1))))))
    (assert (is-ok? (cn/decode-dense-table (cn/encode-dense-table (cn/TableData :cols (list "id") :rows (list (list "test")))))))
    (assert (is-ok? (cn/decode-dag-pyramid (cn/encode-dag-pyramid (cn/DagPyramid :root "r" :deps (list))))))))
