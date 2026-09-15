(module asl-gates/annotationLint
  :d "Enforces 2-token ceiling on memory ref annotations under Minimum Token Principle."
  :x [AnnotationLintResult
      countKebabSegments
      isRefAnnotation
      extractAnnotationBody
      auditSingleAnnotation
      auditRefAnnotations
      allAnnotationsValid?
      auditAnnotationDensity]
  :i [(gates :a g)])

(dfs AnnotationLintResult
  (:f tag Str "Raw annotation tag string")
  (:f tokens I64 "Calculated kebab token count")
  (:f valid Bool "True if within ceiling")
  (:f reason Str "Lint verdict explanation"))

(df countKebabSegments [(name Str)] -> I64
  :d "Calculates token count by counting hyphen-separated segments."
  (let [(parts (string-split name "-"))]
    (max 1 (list-length parts))))

(df isRefAnnotation [(tag Str)] -> Bool
  :d "Checks if tag is a recognized memory reference annotation."
  (or (string-starts-with? tag "@ref:")
      (or (string-starts-with? tag "@dep:")
          (or (string-starts-with? tag "@task:")
              (string-starts-with? tag "@mem:")))))

(df extractAnnotationBody [(tag Str)] -> Str
  :d "Extracts identifier payload from prefixed annotation tag."
  (if (string-starts-with? tag "@ref:")
      (string-replace tag "@ref:" "")
      (if (string-starts-with? tag "@dep:")
          (string-replace tag "@dep:" "")
          (if (string-starts-with? tag "@task:")
              (string-replace tag "@task:" "")
              (if (string-starts-with? tag "@mem:")
                  (string-replace tag "@mem:" "")
                  tag)))))

(df auditSingleAnnotation [(tag Str) (ceiling I64)] -> AnnotationLintResult
  :d "Validates single annotation against maximum token ceiling."
  (let [(body (extractAnnotationBody tag))
        (tokens (countKebabSegments body))
        (valid (<= tokens ceiling))
        (reason (if valid
                    "Within token ceiling"
                    (str "Exceeds token ceiling of " (string-from-int64 ceiling))))]
    (AnnotationLintResult
      :tag tag
      :tokens tokens
      :valid valid
      :reason reason)))

(df auditRefAnnotations [(tags (List Str))] -> (List AnnotationLintResult)
  :d "Audits list of memory ref annotations enforcing strict 2-token ceiling."
  (map (fn [(tag Str)] -> AnnotationLintResult
         (auditSingleAnnotation tag 2))
       tags))

(df allAnnotationsValid? [(results (List AnnotationLintResult))] -> Bool
  :d "Returns true if all annotation lint results are valid."
  (fold (fn [(acc Bool) (r AnnotationLintResult)] -> Bool
          (and acc (.-valid r)))
        true
        results))

(df auditAnnotationDensity [(tags (List Str)) (ceiling I64)] -> Bool
  :d "Verifies that all annotations in collection satisfy token ceiling."
  (let [(results (map (fn [(tag Str)] -> AnnotationLintResult
                        (auditSingleAnnotation tag ceiling))
                      tags))]
    (allAnnotationsValid? results)))
