(module asl-slm
  :d "Top-level facade for asl-slm package"
  :x [GrammarPda MaskerState TokenMaskBitset
      compileGrammarToDfa maskerInit advanceMaskerState advanceMaskerSubword
      resetMaskerBuffer computeTokenMaskBitset isTokenAllowed isTokenValidAtState
      isSubwordPrefixValid isGrammarTerminalAllowed
      runTests RunTests]
  :i [(asl-slm/masker :a msk)])

(df compileGrammarToDfa [(grammarStr Str)] -> msk/GrammarPda
  (msk/compileGrammarToDfa grammarStr))

(df maskerInit [(pda msk/GrammarPda) (eosTokenId Int)] -> msk/MaskerState
  (msk/maskerInit pda eosTokenId))

(df resetMaskerBuffer [(st msk/MaskerState)] -> msk/MaskerState
  (msk/resetMaskerBuffer st))

(df advanceMaskerState [(pda msk/GrammarPda) (st msk/MaskerState) (tokenText Str)] -> msk/MaskerState
  (msk/advanceMaskerState pda st tokenText))

(df advanceMaskerSubword [(pda msk/GrammarPda) (st msk/MaskerState) (subword Str)] -> msk/MaskerState
  (msk/advanceMaskerSubword pda st subword))

(df computeTokenMaskBitset [(pda msk/GrammarPda) (st msk/MaskerState) (vocab (List (Pair Int Str)))] -> msk/TokenMaskBitset
  (msk/computeTokenMaskBitset pda st vocab))

(df isTokenAllowed [(mask msk/TokenMaskBitset) (tokenId Int)] -> Bool
  (msk/isTokenAllowed mask tokenId))

(df isTokenValidAtState [(pda msk/GrammarPda) (st msk/MaskerState) (tokenId Int) (tokenText Str)] -> Bool
  (msk/isTokenValidAtState pda st tokenId tokenText))

(df isSubwordPrefixValid [(pda msk/GrammarPda) (prefix Str)] -> Bool
  (msk/isSubwordPrefixValid pda prefix))

(df isGrammarTerminalAllowed [(pda msk/GrammarPda) (tok Str)] -> Bool
  (msk/isGrammarTerminalAllowed pda tok))

(df runTests [] -> Bool
  true)

(df RunTests [] -> Bool
  (runTests))
