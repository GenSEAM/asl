(module aslMem/tokenRegex :x [TokenPattern TokenMatchResult TokenMatcher compileTokenPattern matchTokenStream scanTokenStream findTokenSubsequences tokenizePattern] :i [])

(schema TokenPattern (:f kind Str) (:f literal (Option Str)) (:f quantifier Str) (:f captureGroup (Option Str)))

(schema TokenMatchResult (:f matched Bool) (:f tokensConsumed I64) (:f captures (Map Str (List Str))))

(schema TokenMatcher (:f patterns (List TokenPattern)) (:f caseSensitive Bool))

fn sliceTokensLoop tokens: (List Str) idx: I64 endIdx: I64 acc: (List Str) -> (List Str)
  (if (>= idx endIdx) acc (let [(tok (optionOr (listGet tokens idx) ""))] (sliceTokensLoop tokens (+ idx 1) endIdx (listAppend acc (list tok)))))

fn tokenizePattern s: Str -> (List Str)
  (let [(hasGroup (stringContains? s "(?<")) (res (fold (fn [(acc (pair (List Str) Str)) (ch Str)] -> (Pair (List Str) Str) (let [(tokens (pairFirst acc)) (curr (pairSecond acc))] (if (or (= ch " ") (or (= ch "\t") (or (= ch "\n") (= ch "\r")))) (if (= curr "") (pair tokens "") (pair (listAppend tokens (list curr)) "")) (if (and (not hasGroup) (or (= ch "(") (= ch ")"))) (let [(t1 (if (= curr "") tokens (listAppend tokens (list curr))))] (pair (listAppend t1 (list ch)) "")) (pair tokens (str curr ch)))))) (pair (list) "") (stringChars s)))] (if (= (pairSecond res) "") (pairFirst res) (listAppend (pairFirst res) (list (pairSecond res)))))

fn parseNamedGroupParen tok: Str -> (Option (Pair Str Str))
  (if (stringStartsWith? tok "(?<") (mt (stringIndexOf tok ">") ((some gtPos) (let [(name (optionOr (stringSlice tok 3 gtPos) "")) (subStart (+ gtPos 1)) (totLen (stringLength tok)) (subEnd (if (stringEndsWith? tok ")") (- totLen 1) totLen)) (subTok (if (> subEnd subStart) (optionOr (stringSlice tok subStart subEnd) "") ""))] (some (pair name (if (= subTok "") "_" subTok))))) ((none) (none))) (none))

fn parseNamedGroupAngle tok: Str -> (Option (Pair Str Str))
  (let [(totLen (stringLength tok))] (if (and (stringStartsWith? tok "<") (and (stringEndsWith? tok ">") (> totLen 2))) (let [(inner (optionOr (stringSlice tok 1 (- totLen 1)) ""))] (mt (stringIndexOf inner ":") ((some colPos) (let [(name (optionOr (stringSlice inner 0 colPos) "")) (subTok (optionOr (stringSlice inner (+ colPos 1) (stringLength inner)) ""))] (some (pair name (if (= subTok "") "_" subTok))))) ((none) (some (pair inner "_"))))) (none)))

fn parseTokenCapture tok: Str -> (Pair (Option Str) Str)
  (mt (parseNamedGroupParen tok) ((some p) (pair (some (pairFirst p)) (pairSecond p))) ((none) (mt (parseNamedGroupAngle tok) ((some p2) (pair (some (pairFirst p2)) (pairSecond p2))) ((none) (pair (none) tok)))))

fn extractQuantifier s: Str -> (Pair Str Str)
  (let [(len (stringLength s))] (cond ((and (>= len 3) (stringEndsWith? s "*?")) (pair (optionOr (stringSlice s 0 (- len 2)) "") "*?")) ((and (>= len 3) (stringEndsWith? s "+?")) (pair (optionOr (stringSlice s 0 (- len 2)) "") "+?")) ((and (>= len 3) (stringEndsWith? s "??")) (pair (optionOr (stringSlice s 0 (- len 2)) "") "??")) ((and (>= len 2) (stringEndsWith? s "*")) (pair (optionOr (stringSlice s 0 (- len 1)) "") "*")) ((and (>= len 2) (stringEndsWith? s "+")) (pair (optionOr (stringSlice s 0 (- len 1)) "") "+")) ((and (>= len 2) (stringEndsWith? s "?")) (pair (optionOr (stringSlice s 0 (- len 1)) "") "?")) ((= s "*") (pair "_" "*")) ((= s "+") (pair "_" "+")) ((= s "?") (pair "_" "?")) (else (pair s "1"))))

fn determineKind base: Str -> Str
  (cond ((or (= base "_") (= base "*")) "wildcard") ((= base "any") "any") (else "literal"))

fn compileSingleTokenPattern rawTok: Str -> TokenPattern
  (let [(capPair (parseTokenCapture rawTok)) (capGrp (pairFirst capPair)) (subTok (pairSecond capPair)) (quantPair (extractQuantifier subTok)) (base (pairFirst quantPair)) (quant (pairSecond quantPair)) (kind (determineKind base)) (lit (if (= kind "literal") (some base) (none)))] (TokenPattern :kind kind :literal lit :quantifier quant :captureGroup capGrp))

fn compileTokenPattern patternStr: Str -> TokenMatcher
  (let [(tokens (tokenizePattern patternStr)) (patterns (map compileSingleTokenPattern tokens))] (TokenMatcher :patterns patterns :caseSensitive true))

fn tokenMatchesPattern? pat: TokenPattern tok: Str caseSensitive: Bool -> Bool
  (let [(kind pat.kind)] (if (or (= kind "wildcard") (= kind "any")) true (let [(lit (optionOr pat.literal ""))] (if caseSensitive (= tok lit) (= (stringLower tok) (stringLower lit))))))

fn countConsecutiveMatches pat: TokenPattern tokens: (List Str) tokensLen: I64 tokIdx: I64 caseSensitive: Bool acc: I64 -> I64
  (if (>= tokIdx tokensLen) acc (let [(tok (optionOr (listGet tokens tokIdx) ""))] (if (tokenMatchesPattern? pat tok caseSensitive) (countConsecutiveMatches pat tokens tokensLen (+ tokIdx 1) caseSensitive (+ acc 1)) acc)))

fn recordCapture captures: (Map Str (List Str)) groupName: (Option Str) tokens: (List Str) startIdx: I64 count: I64 -> (Map Str (List Str))
  (mt groupName ((some name) (let [(slice (sliceTokensLoop tokens startIdx (+ startIdx count) (list))) (existing (optionOr (mapGet captures name) (list)))] (mapSet captures name (listAppend existing slice)))) ((none) captures))

fn tryGreedyK matcher: TokenMatcher tokens: (List Str) tokensLen: I64 startIdx: I64 patIdx: I64 tokIdx: I64 pat: TokenPattern grp: (Option Str) captures: (Map Str (List Str)) k: I64 minK: I64 -> (Option (Pair I64 (Map Str (List Str))))
  (if (< k minK) (none) (let [(nextCap (recordCapture captures grp tokens tokIdx k)) (res (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) (+ tokIdx k) nextCap))] (mt res ((some r) (some r)) ((none) (tryGreedyK matcher tokens tokensLen startIdx patIdx tokIdx pat grp captures (- k 1) minK)))))

fn tryNongreedyK matcher: TokenMatcher tokens: (List Str) tokensLen: I64 startIdx: I64 patIdx: I64 tokIdx: I64 pat: TokenPattern grp: (Option Str) captures: (Map Str (List Str)) k: I64 maxK: I64 -> (Option (Pair I64 (Map Str (List Str))))
  (if (> k maxK) (none) (let [(nextCap (recordCapture captures grp tokens tokIdx k)) (res (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) (+ tokIdx k) nextCap))] (mt res ((some r) (some r)) ((none) (tryNongreedyK matcher tokens tokensLen startIdx patIdx tokIdx pat grp captures (+ k 1) maxK)))))

fn matchPatternsStep matcher: TokenMatcher tokens: (List Str) tokensLen: I64 startIdx: I64 patIdx: I64 tokIdx: I64 captures: (Map Str (List Str)) -> (Option (Pair I64 (Map Str (List Str))))
  (let [(patterns matcher.patterns) (patCount (listLength patterns))] (if (>= patIdx patCount) (some (pair (- tokIdx startIdx) captures)) (let [(pat (optionOr (listGet patterns patIdx) (TokenPattern :kind "" :literal (none) :quantifier "1" :captureGroup (none)))) (quant pat.quantifier) (grp pat.captureGroup) (caseSens matcher.caseSensitive)] (cond ((= quant "1") (if (>= tokIdx tokensLen) (none) (let [(tok (optionOr (listGet tokens tokIdx) ""))] (if (tokenMatchesPattern? pat tok caseSens) (let [(nextCap (recordCapture captures grp tokens tokIdx 1))] (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) (+ tokIdx 1) nextCap)) (none))))) ((= quant "?") (let [(res1 (if (< tokIdx tokensLen) (let [(tok (optionOr (listGet tokens tokIdx) ""))] (if (tokenMatchesPattern? pat tok caseSens) (let [(nextCap (recordCapture captures grp tokens tokIdx 1))] (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) (+ tokIdx 1) nextCap)) (none))) (none)))] (mt res1 ((some r) (some r)) ((none) (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) tokIdx captures))))) ((= quant "??") (let [(res0 (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) tokIdx captures))] (mt res0 ((some r) (some r)) ((none) (if (< tokIdx tokensLen) (let [(tok (optionOr (listGet tokens tokIdx) ""))] (if (tokenMatchesPattern? pat tok caseSens) (let [(nextCap (recordCapture captures grp tokens tokIdx 1))] (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) (+ tokIdx 1) nextCap)) (none))) (none)))))) ((= quant "*") (let [(maxK (countConsecutiveMatches pat tokens tokensLen tokIdx caseSens 0))] (tryGreedyK matcher tokens tokensLen startIdx patIdx tokIdx pat grp captures maxK 0))) ((= quant "+") (let [(maxK (countConsecutiveMatches pat tokens tokensLen tokIdx caseSens 0))] (if (< maxK 1) (none) (tryGreedyK matcher tokens tokensLen startIdx patIdx tokIdx pat grp captures maxK 1)))) ((= quant "*?") (let [(maxK (countConsecutiveMatches pat tokens tokensLen tokIdx caseSens 0))] (tryNongreedyK matcher tokens tokensLen startIdx patIdx tokIdx pat grp captures 0 maxK))) ((= quant "+?") (let [(maxK (countConsecutiveMatches pat tokens tokensLen tokIdx caseSens 0))] (if (< maxK 1) (none) (tryNongreedyK matcher tokens tokensLen startIdx patIdx tokIdx pat grp captures 1 maxK)))) (else (if (>= tokIdx tokensLen) (none) (let [(tok (optionOr (listGet tokens tokIdx) ""))] (if (tokenMatchesPattern? pat tok caseSens) (let [(nextCap (recordCapture captures grp tokens tokIdx 1))] (matchPatternsStep matcher tokens tokensLen startIdx (+ patIdx 1) (+ tokIdx 1) nextCap)) (none)))))))))

fn matchTokenStream matcher: TokenMatcher tokens: (List Str) startIdx: I64 -> TokenMatchResult
  (let [(tokensLen (listLength tokens))] (if (or (< startIdx 0) (> startIdx tokensLen)) (TokenMatchResult :matched false :tokensConsumed 0 :captures (mapEmpty)) (let [(res (matchPatternsStep matcher tokens tokensLen startIdx 0 startIdx (mapEmpty)))] (mt res ((some pairRes) (TokenMatchResult :matched true :tokensConsumed (pairFirst pairRes) :captures (pairSecond pairRes))) ((none) (TokenMatchResult :matched false :tokensConsumed 0 :captures (mapEmpty)))))))

fn scanTokensLoop matcher: TokenMatcher tokens: (List Str) tokensLen: I64 idx: I64 acc: (List TokenMatchResult) -> (List TokenMatchResult)
  (if (>= idx tokensLen) acc (let [(res (matchTokenStream matcher tokens idx))] (if res.matched (let [(advance (if (> res.tokensConsumed 0) res.tokensConsumed 1))] (scanTokensLoop matcher tokens tokensLen (+ idx advance) (listAppend acc (list res)))) (scanTokensLoop matcher tokens tokensLen (+ idx 1) acc))))

fn scanTokenStream matcher: TokenMatcher tokens: (List Str) -> (List TokenMatchResult)
  (let [(tokensLen (listLength tokens))] (scanTokensLoop matcher tokens tokensLen 0 (list)))

fn findSubseqsLoop matcher: TokenMatcher tokens: (List Str) tokensLen: I64 idx: I64 acc: (List (Pair I64 I64)) -> (List (Pair I64 I64))
  (if (>= idx tokensLen) acc (let [(res (matchTokenStream matcher tokens idx))] (if res.matched (let [(consumed res.tokensConsumed) (advance (if (> consumed 0) consumed 1)) (span (pair idx (+ idx consumed)))] (findSubseqsLoop matcher tokens tokensLen (+ idx advance) (listAppend acc (list span)))) (findSubseqsLoop matcher tokens tokensLen (+ idx 1) acc))))

fn findTokenSubsequences matcher: TokenMatcher tokens: (List Str) -> (List (Pair I64 I64))
  (let [(tokensLen (listLength tokens))] (findSubseqsLoop matcher tokens tokensLen 0 (list)))
