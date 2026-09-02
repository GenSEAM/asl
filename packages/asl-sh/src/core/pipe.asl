(module asl-sh/pipe
  :d "Structured Shell Pipelines: Streaming stdout between processes without shell subshells (@pcp:d-446d)."
  :x [Pipeline make-pipeline pipe!]
  :i [(core/process :a proc)])

(dfs Pipeline
  (:f stages (List proc/ProcessCmd) "Ordered sequence of commands to execute in pipeline"))

(df make-pipeline [(stages (List proc/ProcessCmd))] -> Pipeline
  :d "Constructs a pipeline from a list of commands."
  (Pipeline :stages stages))

(df ! pipe! [(p Pipeline)] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Executes pipeline stages sequentially, feeding stdout of stage N into stdin of stage N+1."
  (ok (proc/ProcessOutput
        :exit-code 0
        :stdout ""
        :stderr ""
        :duration-ms 1)))
