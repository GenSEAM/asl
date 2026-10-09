(module asl-proc/pipe :x [Pipeline makePipeline pipe!] :i [(asl-proc/coreProcess :a proc)])

(schema Pipeline (:f stages (List proc/ProcessCmd)))

fn makePipeline stages: (List proc/ProcessCmd) -> Pipeline
  (Pipeline :stages stages)

fn ! executeStages stages: (List proc/ProcessCmd) currentInput: String totalDuration: Int64 -> (Result proc/ProcessOutput proc/ProcessError)
  (mt (listHead stages) ((none) (ok (proc/ProcessOutput :exitCode 0 :stdout currentInput :stderr "" :durationMs totalDuration))) ((some stageCmd) (let [(cmdWithStdin (if (stringEmpty? currentInput) stageCmd (proc/withStdin stageCmd currentInput))) (execRes (proc/exec! cmdWithStdin))] (mt execRes ((err e) (err e)) ((ok out) (if (!= out.exitCode 0) (ok out) (let [(restStages (optionOr (listTail stages) (list)))] (if (listEmpty? restStages) (ok (proc/ProcessOutput :exitCode out.exitCode :stdout out.stdout :stderr out.stderr :durationMs (+ totalDuration out.durationMs))) (executeStages restStages out.stdout (+ totalDuration out.durationMs))))))))))

fn ! pipe! p: Pipeline -> (Result proc/ProcessOutput proc/ProcessError)
  (let [(stages p.stages)] (if (listEmpty? stages) (ok (proc/ProcessOutput :exitCode 0 :stdout "" :stderr "" :durationMs 0)) (executeStages stages "" 0)))
