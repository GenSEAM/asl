(module asl-sh/pipe
  :d "Structured Shell Pipelines: Streaming stdout between processes without shell subshells (@pcp:d-446d)."
  :x [Pipeline make-pipeline pipe!]
  :i [(process :a proc)])

(dfs Pipeline
  (:f stages (List proc/ProcessCmd) "Ordered sequence of commands to execute in pipeline"))

(df make-pipeline [(stages (List proc/ProcessCmd))] -> Pipeline
  :d "Constructs a pipeline from a list of commands."
  (Pipeline :stages stages))

(df ! execute-stages [(stages (List proc/ProcessCmd)) (current-input String) (total-duration Int64)] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Recursively executes pipeline stages, piping stdout of stage N to stdin of stage N+1."
  (mt (list-head stages)
    ((none)
     (ok (proc/ProcessOutput
           :exit-code 0
           :stdout current-input
           :stderr ""
           :duration-ms total-duration)))
    ((some stage-cmd)
     (let [(cmd-with-stdin (if (string-empty? current-input)
                               stage-cmd
                               (proc/with-stdin stage-cmd current-input)))
           (exec-res (proc/exec! cmd-with-stdin))]
       (mt exec-res
         ((err e) (err e))
         ((ok out)
          (if (!= (.-exit-code out) 0)
              (ok out)
              (let [(rest-stages (option-or (list-tail stages) (list)))]
                (if (list-empty? rest-stages)
                    (ok (proc/ProcessOutput
                          :exit-code (.-exit-code out)
                          :stdout (.-stdout out)
                          :stderr (.-stderr out)
                          :duration-ms (+ total-duration (.-duration-ms out))))
                    (execute-stages rest-stages (.-stdout out) (+ total-duration (.-duration-ms out))))))))))))

(df ! pipe! [(p Pipeline)] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Executes pipeline stages sequentially, feeding stdout of stage N into stdin of stage N+1."
  (let [(stages (.-stages p))]
    (if (list-empty? stages)
        (ok (proc/ProcessOutput :exit-code 0 :stdout "" :stderr "" :duration-ms 0))
        (execute-stages stages "" 0))))

