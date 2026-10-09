(module aslHarness/verifier :x [VerificationVerdict VerificationResult detectLanguage validateDelimiterBalance validateMarkupTags isVoidTag? validateYamlSyntax resolveTestRunner verifyChunkMatch verifyStructuralAction executeVerificationGate formatGateRejection] :i [(compactor :a comp) (asl-text/string :a s) (asl-parser/balance :a bal)])

(schema VerificationVerdict (:f allowed Bool) (:f reason Str) (:f language Str))

(schema VerificationResult (:f success Bool) (:f errorMsg Str) (:f details Str))

fn detectLanguage path: Str -> Str
  (cond ((stringEndsWith? path ".asl") "asl") ((or (stringEndsWith? path ".tsx") (stringEndsWith? path ".jsx")) "tsx") ((or (stringEndsWith? path ".ts") (stringEndsWith? path ".js")) "typescript") ((stringEndsWith? path ".py") "python") ((stringEndsWith? path ".rs") "rust") ((stringEndsWith? path ".swift") "swift") ((or (stringEndsWith? path ".kt") (stringEndsWith? path ".kts")) "kotlin") ((stringEndsWith? path ".java") "java") ((or (stringEndsWith? path ".yaml") (stringEndsWith? path ".yml")) "yaml") ((stringEndsWith? path ".xml") "xml") ((or (stringEndsWith? path ".html") (stringEndsWith? path ".htm")) "html") ((stringEndsWith? path ".json") "json") (else "text"))

fn validateDelimiterBalance code: Str -> Bool
  (bal/isPlainDelimiterBalanced? code)

fn isVoidTag? tag: Str -> Bool
  (let [(clean (stringLower (stringReplace tag "/" "")))]
    (or (= clean "br")
      (or (= clean "img")
        (or (= clean "input")
          (or (= clean "hr")
            (or (= clean "meta")
              (= clean "link")))))))

fn extractTagName part: Str -> Str
  (mt (stringIndexOf part ">") ((none) "") ((some gt) (mt (stringIndexOf part " ") ((none) (optionOr (stringSlice part 0 gt) "")) ((some sp) (if (< sp gt) (optionOr (stringSlice part 0 sp) "") (optionOr (stringSlice part 0 gt) ""))))))

fn processTags parts: (List Str) stack: (List Str) -> Bool
  (if (listEmpty? parts) (listEmpty? stack) (let [(part (optionOr (listHead parts) "")) (tag (extractTagName part))] (if (= tag "") (processTags (optionOr (listTail parts) (list)) stack) (if (isVoidTag? tag) (processTags (optionOr (listTail parts) (list)) stack) (if (stringStartsWith? tag "/") (let [(closing (stringReplace tag "/" ""))] (if (and (not (listEmpty? stack)) (= (optionOr (listHead stack) "") closing)) (processTags (optionOr (listTail parts) (list)) (optionOr (listTail stack) (list))) false)) (if (stringEndsWith? tag "/") (processTags (optionOr (listTail parts) (list)) stack) (if (stringEndsWith? part "/>") (processTags (optionOr (listTail parts) (list)) stack) (processTags (optionOr (listTail parts) (list)) (cons tag stack)))))))))

fn validateMarkupTags code: Str -> Bool
  (if (and (stringContains? code "<") (not (stringContains? code ">"))) false (if (and (stringContains? code ">") (not (stringContains? code "<"))) false (let [(parts (s/split code "<"))] (processTags (optionOr (listTail parts) (list)) (list)))))

fn validateYamlSyntax code: Str -> Bool
  (if (stringContains? code "\t") false (validateDelimiterBalance code))

fn resolveTestRunner lang: Str -> Str
  (cond ((= lang "asl") "asl test") ((or (= lang "typescript") (= lang "tsx")) "pnpm test") ((= lang "python") "pytest") ((= lang "rust") "cargo test") ((or (= lang "java") (= lang "kotlin")) "gradle test") ((= lang "swift") "swift test") (else "test"))

fn verifyChunkMatch fileContent: Str oldChunk: Str -> VerificationVerdict
  (let [(trimmedTarget (stringTrim oldChunk))] (cond ((stringEmpty? trimmedTarget) (VerificationVerdict :allowed false :reason "Target chunk cannot be empty" :language "text")) ((not (stringContains? fileContent trimmedTarget)) (VerificationVerdict :allowed false :reason "Target chunk not found in file content" :language "text")) (else (VerificationVerdict :allowed true :reason "" :language "text"))))

fn verifyStructuralAction actionName: Str path: Str payload: Str -> VerificationVerdict
  (let [(lang (detectLanguage path))] (cond ((stringEmpty? path) (VerificationVerdict :allowed false :reason "File path cannot be empty" :language lang)) ((and (or (= lang "html") (or (= lang "xml") (= lang "tsx"))) (not (validateMarkupTags payload))) (VerificationVerdict :allowed false :reason "Unbalanced markup or JSX tags detected in replacement payload" :language lang)) ((and (= lang "yaml") (not (validateYamlSyntax payload))) (VerificationVerdict :allowed false :reason "Invalid YAML syntax: tabs used for indentation or unbalanced collections" :language lang)) ((and (= lang "python") (stringContains? payload "\t")) (VerificationVerdict :allowed false :reason "Forbidden tab characters in Python payload (PEP 8 violation)" :language lang)) ((and (or (= actionName "fs-write") (= actionName "str-replace")) (not (if (= lang "asl") (bal/isDelimiterBalanced? payload) (validateDelimiterBalance payload)))) (VerificationVerdict :allowed false :reason "Unbalanced delimiters detected in replacement payload" :language lang)) ((and (= actionName "ast-patch") (not (= lang "asl"))) (VerificationVerdict :allowed false :reason "ast-patch is specialized for S-expression ASTs; use str-replace for other languages" :language lang)) (else (VerificationVerdict :allowed true :reason "" :language lang))))

fn executeVerificationGate testCmd: Str gatePassed: Bool -> VerificationVerdict
  (cond ((stringEmpty? testCmd) (VerificationVerdict :allowed false :reason "Task must define an explicit verification command" :language "text")) ((not gatePassed) (VerificationVerdict :allowed false :reason "Verification command exited with failure; regressions detected" :language "text")) (else (VerificationVerdict :allowed true :reason "" :language "text")))

fn formatGateRejection testCmd: Str reason: Str -> Str
  (str "(:gate-rejected :command \"" testCmd "\" :reason \"" reason "\" :directive \"Fix failing tests before declaring completion\")")
