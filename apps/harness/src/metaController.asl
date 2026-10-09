(module aslHarness/metaController :x [computeTaskEntropy selectExecutionTier selectExecutionProfile] :i [])

fn computeTaskEntropy nFiles: I64 domainScore: F64 ambiguity: F64 securityCrit: F64 -> F64
  (let [(w1 0.5) (w2 1.5) (w3 1.0) (w4 1.5) (fFiles (int64ToFloat64 nFiles))] (+ (+ (* w1 fFiles) (* w2 domainScore)) (+ (* w3 ambiguity) (* w4 securityCrit))))

fn selectExecutionTier entropy: F64 -> Str
  (cond ((< entropy 1.5) "fast-path") ((< entropy 4.0) "balanced") (else "deep-reflex"))

fn selectExecutionProfile entropy: F64 -> Str
  (selectExecutionTier entropy)
