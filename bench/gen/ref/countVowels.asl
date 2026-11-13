fn countVowels text: String -> Int64
  (listCount (fn [c] (stringContains? "aeiou" c)) (stringChars (stringLower text)))
