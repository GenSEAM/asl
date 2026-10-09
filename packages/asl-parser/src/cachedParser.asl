(module asl-parser/cachedParser
  :x [CachedAstEntry AstCache ParseTelemetry newAstCache newBoundedAstCache computeFormHash extractFormSymbol parseCachedForm parseWithCache parseIncrementalWithTelemetry getCacheStats clearCache]
  :i [(reader :a rd) (indentParser :a ip)])

(schema CachedAstEntry
  (:f hash String)
  (:f symbol String)
  (:f kind String)
  (:f ast rd/SExpr)
  (:f rawText String)
  (:f merkleParentHash String))

(schema AstCache
  (:f entries (Map String CachedAstEntry))
  (:f hits Int64)
  (:f misses Int64)
  (:f evictions Int64)
  (:f maxBytes Int64)
  (:f currentBytes Int64))

(schema ParseTelemetry
  (:f totalForms Int64)
  (:f hits Int64)
  (:f misses Int64)
  (:f cacheHitRate Float64)
  (:f forms (List rd/SExpr)))

fn newAstCache -> AstCache
  (AstCache :entries (mapEmpty) :hits 0 :misses 0 :evictions 0 :maxBytes 1048576 :currentBytes 0)

fn newBoundedAstCache maxBytes: Int64 -> AstCache
  (AstCache :entries (mapEmpty) :hits 0 :misses 0 :evictions 0 :maxBytes maxBytes :currentBytes 0)

fn clearCache cache: AstCache -> AstCache
  (with cache :entries (mapEmpty) :hits 0 :misses 0 :evictions (+ cache.evictions cache.misses) :currentBytes 0)

fn charToAscii ch: String -> Int64
  (let [(code (cond
                ((= ch "a") 97) ((= ch "b") 98) ((= ch "c") 99) ((= ch "d") 100)
                ((= ch "e") 101) ((= ch "f") 102) ((= ch "g") 103) ((= ch "h") 104)
                ((= ch "i") 105) ((= ch "j") 106) ((= ch "k") 107) ((= ch "l") 108)
                ((= ch "m") 109) ((= ch "n") 110) ((= ch "o") 111) ((= ch "p") 112)
                ((= ch "q") 113) ((= ch "r") 114) ((= ch "s") 115) ((= ch "t") 116)
                ((= ch "u") 117) ((= ch "v") 118) ((= ch "w") 119) ((= ch "x") 120)
                ((= ch "y") 121) ((= ch "z") 122) ((= ch "(") 40) ((= ch ")") 41)
                ((= ch " ") 32) ((= ch "\n") 10) ((= ch ":") 58) ((= ch "-") 45)
                ((= ch ">") 62) ((= ch "\"") 34) ((= ch "[") 91) ((= ch "]") 93)
                (else 63)))]
    code)

fn computeFormHash content: String -> String
  (let [(chars (stringChars content))
        (len (stringLength content))
        (h1 (fold (fn [(acc Int64) (ch String)] -> Int64
                    (mod (+ (* acc 31) (charToAscii ch)) 2147483647))
                  5381 chars))
        (h2 (fold (fn [(acc Int64) (ch String)] -> Int64
                    (mod (+ (* acc 131) (charToAscii ch)) 2147483647))
                  1777 chars))]
    (str "cas-" (stringFromInt64 h1) "-" (stringFromInt64 h2) "-" (stringFromInt64 len)))

fn extractFormSymbol formText: String -> (Pair String String)
  (let [(trimmed (stringTrim formText))
        (afterP (if (stringStartsWith? trimmed "(")
                  (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "")
                  trimmed))
        (words (stringSplit (stringTrim afterP) " "))
        (cleanWords (filter (fn [(w String)] -> Bool (> (stringLength w) 0)) words))
        (k (optionOr (listGet cleanWords 0) "unknown"))
        (n (optionOr (listGet cleanWords 1) "anonymous"))]
    (pair k n))


fn parseCachedForm formText: String cache: AstCache -> (Pair CachedAstEntry (Pair AstCache Bool))
  (let [(h (computeFormHash formText))
        (cachedOpt (mapGet cache.entries h))]
    (mt cachedOpt
      ((some entry)
        (if (= entry.rawText formText)
          (let [(updCache (with cache :hits (+ cache.hits 1)))]
            (pair entry (pair updCache true)))
          (let [(kn (extractFormSymbol formText))
                (k (pairFirst kn))
                (n (pairSecond kn))
                (parsedRes (ip/parseIndented formText))
                (astNode (mt parsedRes
                           ((ok node) (ip/stripInferredUnit node))
                           ((err _) (rd/makeList (list (rd/makeAtom k) (rd/makeAtom n))))))
                (newEntry (CachedAstEntry :hash h :symbol n :kind k :ast astNode :rawText formText :merkleParentHash (str "merkle-" h)))
                (newEntries (mapSet cache.entries h newEntry))
                (updCache (with cache :entries newEntries :misses (+ cache.misses 1) :evictions (+ cache.evictions 1) :currentBytes (+ (- cache.currentBytes (stringLength entry.rawText)) (stringLength formText))))]
            (pair newEntry (pair updCache false)))))
      ((none)
        (let [(kn (extractFormSymbol formText))
              (k (pairFirst kn))
              (n (pairSecond kn))
              (parsedRes (ip/parseIndented formText))
              (astNode (mt parsedRes
                         ((ok node) (ip/stripInferredUnit node))
                         ((err _) (rd/makeList (list (rd/makeAtom k) (rd/makeAtom n))))))
              (formLen (stringLength formText))
              (newEntry (CachedAstEntry :hash h :symbol n :kind k :ast astNode :rawText formText :merkleParentHash (str "merkle-" h)))
              (isOverBudget (and (> cache.maxBytes 0) (> (+ cache.currentBytes formLen) cache.maxBytes)))
              (baseEntries (if isOverBudget (mapEmpty) cache.entries))
              (baseBytes (if isOverBudget 0 cache.currentBytes))
              (baseEvictions (if isOverBudget (+ cache.evictions cache.misses) cache.evictions))
              (newEntries (mapSet baseEntries h newEntry))
              (updCache (with cache :entries newEntries :misses (+ cache.misses 1) :evictions baseEvictions :currentBytes (+ baseBytes formLen)))]
          (pair newEntry (pair updCache false))))))

(schema BatchState
  (:f cache AstCache)
  (:f forms (List rd/SExpr))
  (:f hits Int64)
  (:f misses Int64))

fn processFormsBatch forms: (List String) state: BatchState -> BatchState
  (if (listEmpty? forms)
    state
    (let [(curForm (optionOr (listHead forms) ""))
          (rest (optionOr (listTail forms) (list)))
          (trimmed (stringTrim curForm))]
      (if (stringEmpty? trimmed)
        (processFormsBatch rest state)
        (let [(res (parseCachedForm trimmed state.cache))
              (entry (pairFirst res))
              (nextCache (pairFirst (pairSecond res)))
              (wasHit (pairSecond (pairSecond res)))
              (newHits (if wasHit (+ state.hits 1) state.hits))
              (newMisses (if wasHit state.misses (+ state.misses 1)))
              (newForms (listAppend state.forms (list entry.ast)))
              (nextState (BatchState :cache nextCache
                                     :forms newForms
                                     :hits newHits
                                     :misses newMisses))]
          (processFormsBatch rest nextState)))))

fn splitTopForms source: String -> (List String)
  (let [(lines (stringSplit source "\n"))
        (step (fold (fn [(acc (pair (List String) (pair (List String) Int64))) (line String)] -> (Pair (List String) (Pair (List String) Int64))
                      (let [(forms (pairFirst acc))
                            (cur (pairFirst (pairSecond acc)))
                            (depth (pairSecond (pairSecond acc)))
                            (t (stringTrim line))]
                        (if (and (= depth 0) (listEmpty? cur) (not (stringStartsWith? t "(")))
                          acc
                          (let [(chars (stringChars line))
                                (delta (fold (fn [(d Int64) (c String)] -> Int64
                                               (cond ((= c "(") (+ d 1))
                                                     ((= c ")") (- d 1))
                                                     (else d)))
                                             0 chars))
                                (newDepth (+ depth delta))
                                (newCur (listAppend cur (list line)))]
                            (if (and (<= newDepth 0) (> (listLength newCur) 0))
                              (pair (listAppend forms (list (stringJoin newCur "\n")))
                                    (pair (list) 0))
                              (pair forms (pair newCur newDepth)))))))
                    (pair (list) (pair (list) 0)) lines))]
    (pairFirst step))

fn parseIncrementalWithTelemetry cache: AstCache source: String -> (Pair ParseTelemetry AstCache)
  (let [(rawForms (splitTopForms source))
        (forms (if (listEmpty? rawForms)
                 (let [(t (stringTrim source))]
                   (if (stringEmpty? t) (list) (list t)))
                 rawForms))
        (initState (BatchState :cache cache :forms (list) :hits 0 :misses 0))
        (finalState (processFormsBatch forms initState))
        (tot (+ finalState.hits finalState.misses))
        (rate (if (> tot 0)
                (/ (int64ToFloat64 finalState.hits) (int64ToFloat64 tot))
                0.0))
        (telemetry (ParseTelemetry :totalForms tot
                                   :hits finalState.hits
                                   :misses finalState.misses
                                   :cacheHitRate rate
                                   :forms finalState.forms))]
    (pair telemetry finalState.cache))

fn parseWithCache cache: AstCache source: String -> (Pair (List rd/SExpr) AstCache)
  (let [(res (parseIncrementalWithTelemetry cache source))]
    (pair (pairFirst res).forms (pairSecond res)))

fn getCacheStats cache: AstCache -> String
  (let [(entriesCount (- cache.misses cache.evictions))
        (validEntries (if (< entriesCount 0) 0 entriesCount))]
    (str "(:ast-cache :entries " (stringFromInt64 validEntries)
         " :hits " (stringFromInt64 cache.hits)
         " :misses " (stringFromInt64 cache.misses)
         " :evictions " (stringFromInt64 cache.evictions)
         " :bytes " (stringFromInt64 cache.currentBytes)
         " :maxBytes " (stringFromInt64 cache.maxBytes) ")"))
