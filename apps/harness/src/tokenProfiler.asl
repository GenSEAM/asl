(module aslHarness/tokenProfiler :x [WordFrequency TokenBreakdown TokenProfile makeWordFrequency makeTokenBreakdown makeTokenProfile estimateWordTokens isKeywordToken? isDelimiterToken? isLiteralToken? cleanTokenStream computeTokenBreakdown computeWordFrequencies sortWordFrequenciesDesc takeTopFrequencies computeTokenProfile formatWordFrequencyAsn formatTokenProfileAsn] :i [(asl-text/escape :a esc)])

(schema WordFrequency (:f word Str) (:f count I64) (:f tokens I64))

(schema TokenBreakdown (:f keywords I64) (:f identifiers I64) (:f literals I64) (:f delimiters I64))

(schema TokenProfile (:f sourceDesc Str) (:f totalTokens I64) (:f totalChars I64) (:f uniqueWords I64) (:f snrScore F64) (:f breakdown TokenBreakdown) (:f topWords (List WordFrequency)))

fn makeWordFrequency word: Str count: I64 tokens: I64 -> WordFrequency
  (WordFrequency :word word :count count :tokens tokens)

fn makeTokenBreakdown keywords: I64 identifiers: I64 literals: I64 delimiters: I64 -> TokenBreakdown
  (TokenBreakdown :keywords keywords :identifiers identifiers :literals literals :delimiters delimiters)

fn makeTokenProfile source: Str total: I64 chars: I64 unique: I64 snr: F64 breakdown: TokenBreakdown topWords: (List WordFrequency) -> TokenProfile
  (TokenProfile :sourceDesc source :totalTokens total :totalChars chars :uniqueWords unique :snrScore snr :breakdown breakdown :topWords topWords)

fn estimateWordTokens w: Str -> I64
  (let [(len (stringLength w))] (if (= len 0) 0 (if (<= len 4) 1 (/ (+ len 3) 4))))

fn isKeywordToken? w: Str -> Bool
  (and (> (stringLength w) 1) (stringStartsWith? w ":"))

fn isDelimiterToken? w: Str -> Bool
  (or (= w "(") (or (= w ")") (or (= w "[") (or (= w "]") (or (= w "{") (= w "}"))))))

fn isLiteralToken? w: Str -> Bool
  (or (stringStartsWith? w "\"") (or (= w "true") (or (= w "false") (or (stringStartsWith? w "0") (or (stringStartsWith? w "1") (or (stringStartsWith? w "2") (or (stringStartsWith? w "3") (or (stringStartsWith? w "4") (or (stringStartsWith? w "5") (or (stringStartsWith? w "6") (or (stringStartsWith? w "7") (or (stringStartsWith? w "8") (stringStartsWith? w "9")))))))))))))

fn cleanTokenStream text: Str -> (List Str)
  (let [(s1 (stringReplace text "\n" " ")) (s2 (stringReplace s1 "\t" " ")) (s3 (stringReplace s2 "\r" " ")) (s4 (stringReplace s3 "(" " ( ")) (s5 (stringReplace s4 ")" " ) ")) (s6 (stringReplace s5 "[" " [ ")) (s7 (stringReplace s6 "]" " ] ")) (s8 (stringReplace s7 "{" " { ")) (s9 (stringReplace s8 "}" " } ")) (rawWords (stringSplit s9 " "))] (filter (fn [(w Str)] -> Bool (not (stringEmpty? (stringTrim w)))) rawWords))

fn computeTokenBreakdown tokens: (List Str) -> TokenBreakdown
  (let [(kwCount (listLength (filter (fn [(w Str)] -> Bool (isKeywordToken? w)) tokens))) (delimCount (listLength (filter (fn [(w Str)] -> Bool (isDelimiterToken? w)) tokens))) (litCount (listLength (filter (fn [(w Str)] -> Bool (and (not (isDelimiterToken? w)) (isLiteralToken? w))) tokens))) (idCount (listLength (filter (fn [(w Str)] -> Bool (and (not (isKeywordToken? w)) (and (not (isDelimiterToken? w)) (not (isLiteralToken? w))))) tokens)))] (TokenBreakdown :keywords kwCount :identifiers idCount :literals litCount :delimiters delimCount))

fn insertWordFreq w: Str acc: (List WordFrequency) -> (List WordFrequency)
  (if (listEmpty? acc) (list (makeWordFrequency w 1 (estimateWordTokens w))) (let [(headF (optionOr (listHead acc) (makeWordFrequency "" 0 0))) (tailF (optionOr (listTail acc) (list)))] (if (= headF.word w) (let [(newCnt (+ headF.count 1)) (tokUnit (estimateWordTokens w)) (newToks (* newCnt tokUnit))] (cons (makeWordFrequency w newCnt newToks) tailF)) (cons headF (insertWordFreq w tailF)))))

fn computeWordFrequenciesLoop tokens: (List Str) acc: (List WordFrequency) -> (List WordFrequency)
  (if (listEmpty? tokens) acc (let [(headW (optionOr (listHead tokens) "")) (tailW (optionOr (listTail tokens) (list)))] (computeWordFrequenciesLoop tailW (insertWordFreq headW acc))))

fn computeWordFrequencies tokens: (List Str) -> (List WordFrequency)
  (computeWordFrequenciesLoop tokens (list))

fn insertFreqDesc item: WordFrequency sorted: (List WordFrequency) -> (List WordFrequency)
  (if (listEmpty? sorted) (list item) (let [(headF (optionOr (listHead sorted) (makeWordFrequency "" 0 0))) (tailF (optionOr (listTail sorted) (list)))] (if (>= item.count headF.count) (cons item sorted) (cons headF (insertFreqDesc item tailF)))))

fn sortWordFrequenciesDescLoop unsorted: (List WordFrequency) sorted: (List WordFrequency) -> (List WordFrequency)
  (if (listEmpty? unsorted) sorted (let [(headF (optionOr (listHead unsorted) (makeWordFrequency "" 0 0))) (tailF (optionOr (listTail unsorted) (list)))] (sortWordFrequenciesDescLoop tailF (insertFreqDesc headF sorted))))

fn sortWordFrequenciesDesc freqs: (List WordFrequency) -> (List WordFrequency)
  (sortWordFrequenciesDescLoop freqs (list))

fn takeTopFrequencies sorted: (List WordFrequency) n: I64 -> (List WordFrequency)
  (if (or (<= n 0) (listEmpty? sorted)) (list) (let [(headF (optionOr (listHead sorted) (makeWordFrequency "" 0 0))) (tailF (optionOr (listTail sorted) (list)))] (cons headF (takeTopFrequencies tailF (- n 1)))))

fn computeTokenProfile source: Str text: Str topN: I64 -> TokenProfile
  (let [(tokens (cleanTokenStream text)) (totChars (stringLength text)) (tokenWeights (map (fn [(w Str)] -> I64 (estimateWordTokens w)) tokens)) (totTokens (listSum tokenWeights)) (breakdown (computeTokenBreakdown tokens)) (rawFreqs (computeWordFrequencies tokens)) (sortedFreqs (sortWordFrequenciesDesc rawFreqs)) (topWords (takeTopFrequencies sortedFreqs topN)) (uniqueCnt (listLength rawFreqs)) (semanticTokens (+ breakdown.keywords (+ breakdown.identifiers breakdown.literals))) (snr (if (= totTokens 0) 1.0 (/ (int64ToFloat64 semanticTokens) (int64ToFloat64 totTokens))))] (TokenProfile :sourceDesc source :totalTokens totTokens :totalChars totChars :uniqueWords uniqueCnt :snrScore snr :breakdown breakdown :topWords topWords))

fn formatWordFrequencyAsn wf: WordFrequency -> Str
  (str "(:w :word \"" (esc/escapeAsnStr wf.word) "\"" " :count " (stringFromInt64 wf.count) " :tokens " (stringFromInt64 wf.tokens) ")")

fn formatTokenProfileAsn p: TokenProfile -> Str
  (let [(bd p.breakdown) (wfStrs (map (fn [(wf WordFrequency)] -> Str (formatWordFrequencyAsn wf)) p.topWords)) (wordsBody (stringJoin wfStrs " "))] (str "(:token-profile\n" "  :source \"" (esc/escapeAsnStr p.sourceDesc) "\"\n" "  :total-tokens " (stringFromInt64 p.totalTokens) "\n" "  :total-chars " (stringFromInt64 p.totalChars) "\n" "  :unique-words " (stringFromInt64 p.uniqueWords) "\n" "  :snr " (stringFromFloat64 p.snrScore) "\n" "  :breakdown (:keywords " (stringFromInt64 bd.keywords) " :identifiers " (stringFromInt64 bd.identifiers) " :literals " (stringFromInt64 bd.literals) " :delimiters " (stringFromInt64 bd.delimiters) ")\n" "  :top-words [" wordsBody "])\n"))
