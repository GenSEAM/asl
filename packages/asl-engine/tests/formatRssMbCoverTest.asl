(module asl-engine/tests/formatRssMbCoverTest
  :x [runTests]
  :i [(asl-engine/engine :a en)])

; (:m :ref RSS-MB-FORMAT :do "formatRssMb prints ru_maxrss kilobytes as megabytes with one decimal, truncating the tenth: 1536 KB is 1.5, 1024 KB is 1.0, 100 KB is 0.0")
fn ! runTests -> Bool
  (do
    (assert (= (en/formatRssMb 1536) "1.5") "1536 KB is 1.5 MB")
    (assert (= (en/formatRssMb 1024) "1.0") "1024 KB is 1.0 MB")
    (assert (= (en/formatRssMb 100) "0.0") "100 KB rounds down to 0.0 MB")
    true)
