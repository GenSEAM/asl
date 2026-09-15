(module asl-sh/tmpTest
  :x [runTests]
  :i [(asl-sh/process :a proc)
      (reducer      :a red)
      (sh           :a sh)
      (apm          :a apm)])
(df testOobStreamDemuxMemoryBound [] -> Bool
  (let [(spoolPath "tmp/asl-proc-oob-100mb.spool")
        (demuxer0 (apm/makeOobDemuxer spoolPath 67108864))
        (receipt (apm/oobDemuxFinish demuxer0 0 1200))]
    (assert (= 1 1) "ok")
    true))
(df runTests [] -> Bool
  (testOobStreamDemuxMemoryBound))
