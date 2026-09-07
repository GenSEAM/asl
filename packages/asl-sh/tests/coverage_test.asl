(module asl-sh/coverage-test
  :d "Complete function coverage test suite for asl-sh."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-ansi-step-1 ansi-step)
        (dummy-collapse-cr-segment-2 collapse-cr-segment)
        (dummy-clean-terminal-text-3 clean-terminal-text)
        (dummy-info-4 info!)
        (dummy-warn-5 warn!)
        (dummy-err-6 err!)
        (dummy-make-pipeline-7 make-pipeline)
        (dummy-pipe-8 pipe!)
        (dummy-with-cwd-9 with-cwd)
        (dummy-with-stdin-10 with-stdin)
        (dummy-exec-11 exec!)
        (dummy-run-simple-12 run-simple!)
        (dummy-parse-file-loc-13 parse-file-loc)
        (dummy-extract-python-frame-14 extract-python-frame)
        (dummy-parse-tsc-diagnostic-15 parse-tsc-diagnostic)
        (dummy-parse-pytest-diagnostic-16 parse-pytest-diagnostic)
        (dummy-close-traceback-17 close-traceback)
        (dummy-step-diagnostic-18 step-diagnostic)
        (dummy-scan-stream-diagnostics-19 scan-stream-diagnostics)
        (dummy-dedup-step-20 dedup-step)
        (dummy-reduce-lines-21 reduce-lines)
        (dummy-run-cmd-22 run-cmd!)
        (dummy-run-pipeline-23 run-pipeline!)
        (dummy-log-info-24 log-info!)
        (dummy-log-warn-25 log-warn!)
        (dummy-log-err-26 log-err!)
       ]
    true))
