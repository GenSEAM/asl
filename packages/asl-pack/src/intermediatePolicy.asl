(module aslPack/intermediatePolicy
  :x [IntermediatePolicy makeDefaultIntermediatePolicy resolveIntermediatePath isIntermediateFile? shouldCleanIntermediates? cleanIntermediateFile! isPathGitIgnored? defaultIgnoredExtensions defaultIgnoredDirectories]
  :i [])

(schema IntermediatePolicy
  (:f cleanIntermediates Bool)
  (:f buildDir Str)
  (:f keepFlag Str)
  (:f ignoredExtensions (List Str))
  (:f ignoredDirectories (List Str)))

fn defaultIgnoredExtensions -> (List Str)
  (list ".ll" ".bc" ".o" ".s" ".tmp" ".wasm.csv")

fn defaultIgnoredDirectories -> (List Str)
  (list "target" "build" "dist" "tmp" "scratch" ".asl/build" ".asl/cache")

fn makeDefaultIntermediatePolicy -> IntermediatePolicy
  (IntermediatePolicy
    :cleanIntermediates true
    :buildDir "target"
    :keepFlag "--keep-intermediates"
    :ignoredExtensions (defaultIgnoredExtensions)
    :ignoredDirectories (defaultIgnoredDirectories))

fn resolveIntermediatePath policy: IntermediatePolicy baseName: Str ext: Str -> Str
  (let [(dir policy.buildDir)]
    (str dir "/" baseName ext))

fn isIntermediateFile? policy: IntermediatePolicy path: Str -> Bool
  (let [(exts policy.ignoredExtensions)
        (dirs policy.ignoredDirectories)]
    (or (listAny? (fn [(e Str)] -> Bool (stringEndsWith? path e)) exts)
        (listAny? (fn [(d Str)] -> Bool (or (stringStartsWith? path (str d "/")) (= path d))) dirs)))

fn shouldCleanIntermediates? policy: IntermediatePolicy keepIntermediates: Bool -> Bool
  (and policy.cleanIntermediates (not keepIntermediates))

fn ! cleanIntermediateFile! policy: IntermediatePolicy path: Str keepIntermediates: Bool -> (Result Unit Str)
  (if (shouldCleanIntermediates? policy keepIntermediates)
    (let [(res (processRun (str "rm -f " path)))]
      (if (= res.exitCode 0)
        (ok ())
        (err (str "Failed to delete intermediate file: " path))))
    (ok ()))

fn isPathGitIgnored? path: Str gitignoreContent: Str -> Bool
  (let [(lines (stringSplit gitignoreContent "\n"))
        (cleanLines (filter (fn [(l Str)] -> Bool (and (not (stringEmpty? (stringTrim l))) (not (stringStartsWith? (stringTrim l) "#")))) lines))]
    (listAny? (fn [(pat Str)] -> Bool
           (let [(p (stringTrim pat))
                 (cleanPat (if (stringEndsWith? p "/") (optionOr (stringSlice p 0 (- (stringLength p) 1)) p) p))]
             (or (= path p)
                 (= path cleanPat)
                 (and (stringStartsWith? p "*.") (stringEndsWith? path (optionOr (stringSlice p 1 (stringLength p)) "")))
                 (stringStartsWith? path (str cleanPat "/")))))
         cleanLines))
