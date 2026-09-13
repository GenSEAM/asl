(module asl-sh/pipe
  :d "Structured Shell Pipelines: Streaming stdout between processes without shell subshells (d-446d)."
  :x [Pipeline makePipeline pipe!]
  :i [(process :a proc)])

(dfs Pipeline
  (:f stages (List proc/ProcessCmd) "Ordered sequence of commands to execute in pipeline"))

(df makePipeline [(stages (List proc/ProcessCmd))] -> Pipeline
  :d "Constructs a pipeline from a list of commands."
  (Pipeline :stages stages))

(df ! executeStages [(stages (List proc/ProcessCmd)) (currentInput String) (totalDuration Int64)] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Recursively executes pipeline stages, piping stdout of stage N to stdin of stage N+1."
  (mt (list-head stages)
    ((none)
     (ok (proc/ProcessOutput
           :exitCode 0
           :stdout currentInput
           :stderr ""
           :durationMs totalDuration)))
    ((some stageCmd)
     (let [(cmdWithStdin (if (string-empty? currentInput)
                               stageCmd
                               (proc/withStdin stageCmd currentInput)))
           (execRes (proc/exec! cmdWithStdin))]
       (mt execRes
         ((err e) (err e))
         ((ok out)
          (if (!= (.-exitCode out) 0)
              (ok out)
              (let [(restStages (option-or (list-tail stages) (list)))]
                (if (list-empty? restStages)
                    (ok (proc/ProcessOutput
                          :exitCode (.-exitCode out)
                          :stdout (.-stdout out)
                          :stderr (.-stderr out)
                          :durationMs (+ totalDuration (.-durationMs out))))
                    (executeStages restStages (.-stdout out) (+ totalDuration (.-durationMs out))))))))))))

(df ! pipe! [(p Pipeline)] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Executes pipeline stages sequentially, feeding stdout of stage N into stdin of stage N+1."
  (let [(stages (.-stages p))]
    (if (list-empty? stages)
        (ok (proc/ProcessOutput :exitCode 0 :stdout "" :stderr "" :durationMs 0))
        (executeStages stages "" 0))))

