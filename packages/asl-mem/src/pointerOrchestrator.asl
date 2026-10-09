(module aslMem/pointerOrchestrator :x [PointerSpec makePointerSpec derefPointer collapsePointer rehydratePointer! orchestrateContextPointers formatPointerSpec parsePointerSpec totalActiveTokens isContextMinimal?] :i [(checkpoint :a cp)])

(schema PointerSpec (:f id Str) (:f kind Str) (:f target Str) (:f tokens I64) (:f expandedTokens I64) (:f isExpanded Bool) (:f summary Str) (:f payload Str) (:f vfsRef Str))

fn makePointerSpec id: Str kind: Str target: Str tokens: I64 summary: Str -> PointerSpec
  (PointerSpec :id id :kind kind :target target :tokens tokens :expandedTokens 0 :isExpanded false :summary summary :payload "" :vfsRef target)

fn derefPointer ptr: PointerSpec fullContent: Str -> PointerSpec
  (let [(len (stringLength fullContent)) (toks (/ len 4))] (with ptr :expandedTokens toks :isExpanded true :payload fullContent :vfsRef (if (not (stringEmpty? fullContent)) fullContent ptr.vfsRef)))

fn collapsePointer ptr: PointerSpec -> PointerSpec
  (let [(ref (if (not (stringEmpty? ptr.payload)) ptr.payload ptr.vfsRef))] (with ptr :isExpanded false :payload "" :vfsRef ref))

fn rehydratePointer! ptr: PointerSpec -> PointerSpec
  (if ptr.isExpanded ptr (let [(ref ptr.vfsRef)] (if (stringEmpty? ref) (derefPointer ptr ptr.target) (if (and (= ptr.kind "file") (fileExists? ref)) (mt (fileRead ref) ((ok content) (derefPointer ptr content)) ((err _) (derefPointer ptr ref))) (derefPointer ptr ref)))))

fn formatPointerSpec ptr: PointerSpec -> Str
  (let [(tokS (stringFromInt64 ptr.tokens)) (expS (if ptr.isExpanded "true" "false")) (p1 (str "(:ptr :kind \"" ptr.kind "\" :id \"" ptr.id "\" :target \"" ptr.target "\"")) (p2 (str " :tokens " tokS " :expanded " expS " :summary \"" ptr.summary "\"")) (p3 (if (stringEmpty? ptr.vfsRef) ")" (str " :vfs-ref \"" ptr.vfsRef "\")")))] (str p1 p2 p3))

fn parsePointerSpec line: Str -> (Option PointerSpec)
  (let [(trimmed (stringTrim line))] (if (and (stringStartsWith? trimmed "(:ptr") (stringEndsWith? trimmed ")")) (let [(kindStr (cp/extractBetween trimmed ":kind \"" "\"")) (idStr (cp/extractBetween trimmed ":id \"" "\"")) (targetStr (cp/extractBetween trimmed ":target \"" "\"")) (tokensStr (cp/extractBetween trimmed ":tokens " " ")) (expandedStr (cp/extractBetween trimmed ":expanded " " ")) (summaryStr (cp/extractBetween trimmed ":summary \"" "\""))] (mt kindStr ((none) (none)) ((some k) (mt idStr ((none) (none)) ((some i) (mt targetStr ((none) (none)) ((some targ) (let [(tokVal (optionOr (stringToInt64 (stringTrim (optionOr tokensStr "0"))) 0)) (isExp (stringStartsWith? (stringTrim (optionOr expandedStr "false")) "true")) (summ (optionOr summaryStr "")) (vfsR (optionOr (cp/extractBetween trimmed ":vfs-ref \"" "\"") targ))] (some (PointerSpec :id i :kind k :target targ :tokens tokVal :expandedTokens 0 :isExpanded isExp :summary summ :payload "" :vfsRef vfsR)))))))))) (none)))

fn totalActiveTokensLoop ptrs: (List PointerSpec) sum: I64 -> I64
  (if (listEmpty? ptrs) sum (let [(defaultPtr (PointerSpec :id "" :kind "" :target "" :tokens 0 :expandedTokens 0 :isExpanded false :summary "" :payload "" :vfsRef "")) (headP (optionOr (listHead ptrs) defaultPtr)) (tailP (optionOr (listTail ptrs) (list))) (actTok (if headP.isExpanded headP.expandedTokens headP.tokens))] (totalActiveTokensLoop tailP (+ sum actTok))))

fn totalActiveTokens pointers: (List PointerSpec) -> I64
  (totalActiveTokensLoop pointers 0)

fn isContextMinimal? pointers: (List PointerSpec) ceiling: I64 -> Bool
  (< (totalActiveTokens pointers) ceiling)

fn orchestrateLoop ptrs: (List PointerSpec) budget: I64 accumulated: I64 acc: (List PointerSpec) -> (List PointerSpec)
  (if (listEmpty? ptrs) acc (let [(defaultPtr (PointerSpec :id "" :kind "" :target "" :tokens 0 :expandedTokens 0 :isExpanded false :summary "" :payload "" :vfsRef "")) (headP (optionOr (listHead ptrs) defaultPtr)) (tailP (optionOr (listTail ptrs) (list))) (expTok (if (> headP.expandedTokens 0) headP.expandedTokens headP.tokens))] (if (<= (+ accumulated expTok) budget) (let [(expandedPtr (PointerSpec :id headP.id :kind headP.kind :target headP.target :tokens headP.tokens :expandedTokens expTok :isExpanded true :summary headP.summary :payload (if (not (stringEmpty? headP.payload)) headP.payload headP.vfsRef) :vfsRef headP.vfsRef))] (orchestrateLoop tailP budget (+ accumulated expTok) (listAppend acc (list expandedPtr)))) (let [(collapsedPtr (PointerSpec :id headP.id :kind headP.kind :target headP.target :tokens headP.tokens :expandedTokens headP.expandedTokens :isExpanded false :summary headP.summary :payload "" :vfsRef (if (not (stringEmpty? headP.payload)) headP.payload headP.vfsRef)))] (orchestrateLoop tailP budget (+ accumulated headP.tokens) (listAppend acc (list collapsedPtr)))))))

fn orchestrateContextPointers pointers: (List PointerSpec) budget: I64 -> (List PointerSpec)
  (orchestrateLoop pointers budget 0 (list))
