(module asl-proc/tmpTest :x [runTests] :i [(asl-proc/process :a proc) (reducer :a red) (sh :a sh) (apm :a apm) (spool :a spool)])

fn ! testOobStreamDemuxMemoryBound -> Bool
  (let [(spoolPathRes (spool/reserveSpoolPath! "oob-100mb" 0))]
    (do
      (assert (ok? spoolPathRes) "reserve-spool-path! must succeed")
      (let [(spoolPath (resultOr spoolPathRes "")) (demuxer0 (apm/makeOobDemuxer spoolPath 67108864)) (finishRes (apm/oobDemuxFinish demuxer0 0 1200))]
        (do
          (assert (ok? finishRes) "oob-demux-finish! must succeed")
          (assert (mt finishRes ((ok receipt) (and (= receipt.exitCode 0) (= receipt.durationMs 1200))) ((err _) false)) "an unterminated demuxer finishes with the exit code it was given and keeps the duration")
          (let [(_ (mt finishRes ((ok receipt) (spool/spoolPathRelease! receipt.spoolPath)) ((err _) (err "no receipt"))))] true)))))

fn ! runTests -> Bool
  (testOobStreamDemuxMemoryBound)
