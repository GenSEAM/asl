(module test/runMe :x [main] :i [])

fn ! main -> (Result Unit IoError)
  (let [(_ (println "RUN_OUTPUT_MARKER"))]
    (ok ()))
