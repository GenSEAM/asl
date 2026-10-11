(module asl-proc :x [runCmd! execReceipt! releaseReceipt! runPipeline! logInfo! logWarn! logErr! boundPortHeadWindow] :i [(asl-proc/process :a proc) (asl-proc/coreProcess :a cp) (asl-proc/pipe :a pipe) (asl-proc/log :a log) (spool :a spool) (deadline :a wd) (apm :a apm)])

fn boundPortHeadWindow s: String -> String
  (let [(len (int32ToInt64 (stringLength s)))]
    (if (<= len 65536) s (optionOr (stringSlice s 0 65536) s)))

fn ! execReceipt! c: cp/ProcessCmd -> (Result cp/ProcessReceipt cp/ProcessError)
  (mt (proc/execRaw! c)
    ((err e) (err e))
    ((ok out)
      (mt (spool/reserveSpoolPath! c.bin 0)
        ((err e) (err (cp/executionFailed out.exitCode (str "could not reserve a spool path: " e))))
        ((ok spoolPath)
          (let [(demuxer (apm/makeOobDemuxer spoolPath 67108864)) (demuxed1 (if (stringEmpty? out.stdout) demuxer (apm/oobDemuxChunk demuxer out.stdout))) (demuxed2 (if (stringEmpty? out.stderr) demuxed1 (apm/oobDemuxChunk demuxed1 out.stderr))) (rssVerdict (wd/checkRssCeiling 0 512)) (deadlockVerdict (wd/detectDeadlock 0 10000)) (stdoutVerdict (wd/detectBoundPort (boundPortHeadWindow out.stdout))) (boundPort (if stdoutVerdict.detected (some stdoutVerdict.port) (let [(stderrVerdict (wd/detectBoundPort (boundPortHeadWindow out.stderr)))] (if stderrVerdict.detected (some stderrVerdict.port) (none))))) (_ (mt boundPort ((some p) (log/info! "asl-proc" (str ":port-bound " (stringFromInt64 p)))) ((none) ())))]
            (mt (apm/oobDemuxFinish demuxed2 out.exitCode out.durationMs)
              ((ok receipt) (ok receipt))
              ((err e) (err (cp/executionFailed out.exitCode (str "spool sync failed: " e))))))))))

fn ! runCmd! bin: String args: (List String) -> (Result cp/ProcessReceipt cp/ProcessError)
  (execReceipt! (proc/cmd bin args))

fn ! releaseReceipt! r: cp/ProcessReceipt -> (Result Unit String)
  (spool/spoolPathRelease! r.spoolPath)

fn ! runPipeline! stages: (List cp/ProcessCmd) -> (Result cp/ProcessOutput cp/ProcessError)
  (pipe/pipe! (pipe/makePipeline stages))

fn ! logInfo! subsystem: String message: String -> Unit
  (log/info! subsystem message)

fn ! logWarn! subsystem: String message: String -> Unit
  (log/warn! subsystem message)

fn ! logErr! subsystem: String message: String -> Unit
  (log/err! subsystem message)
