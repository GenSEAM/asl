(module aslHarness/tokenProfilerTest :x [testWordTokenEstimation testTokenCategoryPredicates testTokenStreamExtraction testTokenBreakdownAndSnr testFrequencySortingDescending testFullTokenProfileAndAsnFormatting runTests] :i [(tokenProfiler :a tp)])

fn testWordTokenEstimation -> Bool
  (let [(tokEmpty (tp/estimateWordTokens "")) (tokShort (tp/estimateWordTokens "cat")) (tokFour (tp/estimateWordTokens "four")) (tokEight (tp/estimateWordTokens "eightlet")) (tokLong (tp/estimateWordTokens "supercalifragilistic"))] (do (assert (= tokEmpty 0) "Empty string must yield 0 tokens") (assert (= tokShort 1) "3-char word must yield 1 token") (assert (= tokFour 1) "4-char word must yield 1 token") (assert (>= tokEight 2) "8-char word must yield at least 2 tokens") (assert (<= tokEight 3) "8-char word must yield at most 3 tokens") (assert (>= tokLong 4) "Long word must yield at least 4 tokens") true))

fn testTokenCategoryPredicates -> Bool
  (let [(kw (tp/isKeywordToken? ":action")) (notKw (tp/isKeywordToken? "action")) (delim (tp/isDelimiterToken? "(")) (notDelim (tp/isDelimiterToken? "foo")) (litStr (tp/isLiteralToken? "\"hello\"")) (litNum (tp/isLiteralToken? "42")) (notLit (tp/isLiteralToken? "my-func"))] (do (assert kw "Colon prefixed word must be keyword") (assert (not notKw) "Normal word is not keyword") (assert delim "Paren must be delimiter") (assert (not notDelim) "Word is not delimiter") (assert litStr "Quoted string must be literal") (assert litNum "Number must be literal") (assert (not notLit) "Identifier is not literal") true))

fn testTokenStreamExtraction -> Bool
  (let [(text "(:finding :cat \"crutch\" :line 10)") (tokens (tp/cleanTokenStream text))] (do (assert (> (listLength tokens) 5) "Clean token stream must extract isolated tokens") (assert (= (optionOr (listHead tokens) "") "(") "First token must be open paren") (assert (tp/isKeywordToken? (optionOr (listHead (optionOr (listTail tokens) (list))) "")) "Second token must be keyword") true))

fn testTokenBreakdownAndSnr -> Bool
  (let [(tokens (tp/cleanTokenStream "(:op :id \"find\" :count 5) (run-test)")) (bd (tp/computeTokenBreakdown tokens))] (do (assert (> bd.keywords 0) "Must count keywords") (assert (> bd.delimiters 0) "Must count delimiters") (assert (> bd.literals 0) "Must count literals") (assert (> bd.identifiers 0) "Must count identifiers") true))

fn testFrequencySortingDescending -> Bool
  (let [(text ":tag :tag :tag :tag :sec :sec :other") (tokens (tp/cleanTokenStream text)) (freqs (tp/computeWordFrequencies tokens)) (sorted (tp/sortWordFrequenciesDesc freqs)) (firstItem (optionOr (listHead sorted) (tp/makeWordFrequency "" 0 0))) (secondItem (optionOr (listHead (optionOr (listTail sorted) (list))) (tp/makeWordFrequency "" 0 0)))] (do (assert (= firstItem.word ":tag") "Top word must be :tag with highest frequency") (assert (= firstItem.count 4) "Top word count must be 4") (assert (= secondItem.word ":sec") "Second word must be :sec with count 2") (assert (= secondItem.count 2) "Second word count must be 2") (assert (>= firstItem.count secondItem.count) "Frequency must be strictly descending") true))

fn testFullTokenProfileAndAsnFormatting -> Bool
  (let [(input "(:task :id \"t-01\" :status :ready :count 10)") (prof (tp/computeTokenProfile "test-payload" input 3)) (asnStr (tp/formatTokenProfileAsn prof))] (do (assert (> prof.totalTokens 0) "Total tokens must be positive") (assert (> prof.totalChars 0) "Total chars must be positive") (assert (> prof.uniqueWords 0) "Unique words must be positive") (assert (> prof.snrScore 0.0) "SNR must be positive") (assert (stringContains? asnStr "(:token-profile") "ASN output must contain :token-profile") (assert (stringContains? asnStr ":total-tokens") "ASN output must contain :total-tokens") (assert (stringContains? asnStr ":breakdown (:keywords") "ASN output must contain breakdown") (assert (stringContains? asnStr ":top-words [") "ASN output must contain top-words array") true))

fn runTests -> Bool
  (do (assert (testWordTokenEstimation)) (assert (testTokenCategoryPredicates)) (assert (testTokenStreamExtraction)) (assert (testTokenBreakdownAndSnr)) (assert (testFrequencySortingDescending)) (assert (testFullTokenProfileAndAsnFormatting)) true)
