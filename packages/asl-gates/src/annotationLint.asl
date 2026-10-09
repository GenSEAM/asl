(module asl-gates/annotationLint :x [AnnotationLintResult countKebabSegments isRefAnnotation extractAnnotationBody auditSingleAnnotation auditRefAnnotations allAnnotationsValid? auditAnnotationDensity] :i [])

(schema AnnotationLintResult (:f tag Str) (:f tokens I64) (:f valid Bool) (:f reason Str))

fn countKebabSegments name: Str -> I64
  (let [(parts (stringSplit name "-"))] (max 1 (listLength parts)))

fn isRefAnnotation tag: Str -> Bool
  (or (stringStartsWith? tag "@ref:") (or (stringStartsWith? tag "@dep:") (or (stringStartsWith? tag "@task:") (stringStartsWith? tag "@mem:"))))

fn extractAnnotationBody tag: Str -> Str
  (if (stringStartsWith? tag "@ref:") (stringReplace tag "@ref:" "") (if (stringStartsWith? tag "@dep:") (stringReplace tag "@dep:" "") (if (stringStartsWith? tag "@task:") (stringReplace tag "@task:" "") (if (stringStartsWith? tag "@mem:") (stringReplace tag "@mem:" "") tag))))

fn auditSingleAnnotation tag: Str ceiling: I64 -> AnnotationLintResult
  (let [(body (extractAnnotationBody tag)) (tokens (countKebabSegments body)) (valid (<= tokens ceiling)) (reason (if valid "Within token ceiling" (str "Exceeds token ceiling of " (stringFromInt64 ceiling))))] (AnnotationLintResult :tag tag :tokens tokens :valid valid :reason reason))

fn auditRefAnnotations tags: (List Str) -> (List AnnotationLintResult)
  (map (fn [(tag Str)] -> AnnotationLintResult (auditSingleAnnotation tag 2)) tags)

fn allAnnotationsValid? results: (List AnnotationLintResult) -> Bool
  (fold (fn [(acc Bool) (r AnnotationLintResult)] -> Bool (and acc r.valid)) true results)

fn auditAnnotationDensity tags: (List Str) ceiling: I64 -> Bool
  (let [(results (map (fn [(tag Str)] -> AnnotationLintResult (auditSingleAnnotation tag ceiling)) tags))] (allAnnotationsValid? results))
