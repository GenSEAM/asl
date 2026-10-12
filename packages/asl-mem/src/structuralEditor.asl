(module aslMem/structuralEditor :x [ASTTransform rewriteAstNode isStubBody? scaffoldModule scaffoldTest scaffoldFn isBalancedDelimiters?] :i [(vfs :a v) (astFilter :a af) (asl-parser/balance :a bal)])

(schema ASTTransform (:f op Str) (:f targetSymbol Str) (:f replacement Str) (:f fieldType (Option Str)))

fn isBalancedDelimiters? text: Str -> Bool
  (bal/isDelimiterBalanced? text)

fn computeCasHash content: Str -> Str
  (let [(chars (stringChars content)) (len (stringLength content)) (h (fold (fn [(acc I64) (ch Str)] -> I64 (mod (+ (* acc 31) (v/charToCode ch)) 2147483647)) 5381 chars))] (str "cas-" (stringFromInt64 h) "-" (stringFromInt64 len)))

fn stringReplaceFirst text: Str target: Str replacement: Str -> Str
  (if (or (stringEmpty? target) (stringEmpty? text)) text (mt (stringIndexOf text target) ((none) text) ((some idx) (let [(pre (optionOr (stringSlice text 0 idx) "")) (postStart (+ idx (stringLength target))) (post (optionOr (stringSlice text postStart (stringLength text)) ""))] (str pre replacement post)))))

fn findLastParenIdx chars: (List Str) idx: I64 best: I64 -> I64
  (if (>= idx (listLength chars)) best (let [(c (optionOr (listGet chars idx) "")) (nextBest (if (= c ")") idx best))] (findLastParenIdx chars (+ idx 1) nextBest)))

fn mutateRenameSymbol raw: Str node: af/ASTMatchNode m: ASTTransform -> Str
  (let [(target (if (stringEmpty? m.targetSymbol) node.symbolId m.targetSymbol))] (stringReplaceFirst raw target m.replacement))

fn findDocstringEnd text: Str start: I64 -> (Option I64)
  (let [(chars (stringChars text)) (len (listLength chars))] (mt (stringIndexOf (optionOr (stringSlice text start len) "") "\"") ((none) (none)) ((some q1Rel) (let [(q1 (+ start (+ q1Rel 1)))] (mt (stringIndexOf (optionOr (stringSlice text q1 len) "") "\"") ((none) (none)) ((some q2Rel) (some (+ q1 (+ q2Rel 1)))))))))

fn replaceBodyFallback raw: Str repl: Str -> Str
  (let [(chars (stringChars raw)) (lastP (findLastParenIdx chars 0 -1))] (if (> lastP 0) (str (optionOr (stringSlice raw 0 lastP) "") "\n  " repl "\n)") raw))

fn replaceBodyPostBracket raw: Str brIdx: I64 repl: Str -> Str
  (let [(postBr (optionOr (stringSlice raw (+ brIdx 1) (stringLength raw)) ""))] (mt (stringIndexOf postBr "->") ((none) (str (optionOr (stringSlice raw 0 (+ brIdx 1)) "") "\n  " repl "\n)")) ((some arrIdx) (let [(afterArr (optionOr (stringSlice postBr (+ arrIdx 2) (stringLength postBr)) "")) (words (stringSplit (stringTrim afterArr) " ")) (retType (optionOr (listGet words 0) "")) (cutLen (+ (+ brIdx 1) (+ (+ arrIdx 2) (+ (stringLength retType) 1))))] (str (optionOr (stringSlice raw 0 cutLen) "") "\n  " repl "\n)")))))

fn replaceBodyAfterDoc raw: Str dIdx: I64 repl: Str -> Str
  (mt (findDocstringEnd raw dIdx) ((some docEnd) (let [(prefix (optionOr (stringSlice raw 0 docEnd) ""))] (str prefix "\n  " repl "\n)"))) ((none) (replaceBodyFallback raw repl)))

fn replaceBodyNoDoc raw: Str repl: Str -> Str
  (mt (stringIndexOf raw "]") ((some brIdx) (replaceBodyPostBracket raw brIdx repl)) ((none) (replaceBodyFallback raw repl)))

fn mutateReplaceBody raw: Str m: ASTTransform -> Str
  (let [(repl m.replacement)] (mt (stringIndexOf raw ":d ") ((some dIdx) (replaceBodyAfterDoc raw dIdx repl)) ((none) (replaceBodyNoDoc raw repl))))

fn mutateAddField raw: Str m: ASTTransform -> Str
  (let [(chars (stringChars raw)) (lastP (findLastParenIdx chars 0 -1)) (repl m.replacement)] (if (<= lastP 0) raw (let [(prefix (optionOr (stringSlice raw 0 lastP) "")) (fieldStr (if (or (stringStartsWith? repl "(:f") (stringStartsWith? repl "(")) (str "  " repl "\n") (let [(ft (optionOr m.fieldType "Str"))] (str "  (:f " repl " " ft " \"" repl " field\")\n"))))] (str prefix fieldStr ")"))))

fn normalizeMutationOp op: Str -> Str
  (if (stringStartsWith? op ":") (optionOr (stringSlice op 1 (stringLength op)) "") op)

fn applyAstMutation raw: Str node: af/ASTMatchNode m: ASTTransform -> Str
  (let [(op (normalizeMutationOp m.op))] (cond ((= op "rename-symbol") (mutateRenameSymbol raw node m)) ((= op "replace-body") (mutateReplaceBody raw m)) ((= op "add-field") (mutateAddField raw m)) ((= op "wrap-with-assert") (str "(assert " raw " \"" m.replacement "\")")) ((= op "remove-form") "") (else raw)))

fn rewriteAstNode buffer: v/VFSBuffer node: af/ASTMatchNode mutation: ASTTransform -> v/VFSBuffer
  (let [(raw node.rawForm) (mutated (applyAstMutation raw node mutation)) (content buffer.content) (cLen (stringLength content)) (startC node.startChar) (endC node.endChar)] (if (and (not (stringEmpty? mutated)) (not (isBalancedDelimiters? mutated))) buffer (let [(pre (optionOr (stringSlice content 0 startC) "")) (post (optionOr (stringSlice content endC cLen) "")) (newContent (str pre mutated post)) (newHash (computeCasHash newContent)) (baseH buffer.baseHash) (isDirty (!= newHash baseH))] (v/VFSBuffer :path buffer.path :content newContent :baseContent buffer.baseContent :casHash newHash :baseHash baseH :revision (+ buffer.revision 1) :dirty isDirty :loadedAt buffer.loadedAt :leaseHolder buffer.leaseHolder :leaseExpiresAt buffer.leaseExpiresAt :leaseToken buffer.leaseToken))))

fn isStubBody? body: Str -> Bool
  (let [(trimmed (stringTrim body))] (or (stringEmpty? trimmed) (= trimmed "true") (= trimmed "false") (= trimmed "nil") (= trimmed "0") (= trimmed "\"\"")))

fn scaffoldModule name: Str -> Str
  (str "(module " name "\n" "  :x [init-" name "\n" "      process-" name "]\n" "  :i [])\n\n" "fn init-" name " -> Bool\n" "  (let [(ready true)]\n" "    (assert ready \"" name " initialization contract established\")\n" "    ready)\n\n" "fn process-" name " input: Str -> Str\n" "  (if (stringEmpty? input)\n" "    \"default\"\n" "    (str \"" name ":\" input))\n")

fn scaffoldTest name: Str -> Str
  (str "(module tests/" name "\n" "  :x [runTests\n" "      test" name "Positive\n" "      test" name "Negative]\n" "  :i [])\n\n" (str "fn test" name "Positive -> Bool\n") "  (let [(expected \"sample-data\")\n" "        (actual (str \"sample\" \"-\" \"data\"))]\n" "    (assert (= expected actual) \"expected must match actual\")\n" "    (= expected actual))\n\n" (str "fn test" name "Negative -> Bool\n") "  (let [(empty-str \"\")\n" "        (is-empty (stringEmpty? empty-str))]\n" "    (assert is-empty \"empty string must satisfy string-empty predicate\")\n" "    is-empty)\n\n" "fn runTests -> Bool\n" "  (do\n" "    (assert (test" name "Positive) \"test" name "Positive must pass\")\n" "    (assert (test" name "Negative) \"test" name "Negative must pass\")\n" "    true)\n")

fn scaffoldFn name: Str -> Str
  (str "fn " name " payload: Str -> Str\n" "  (if (stringEmpty? payload)\n" "    \"" name "-empty\"\n" "    (str \"" name ":\" payload))\n")
