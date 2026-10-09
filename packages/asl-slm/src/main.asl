(module asl-slm :x [GrammarPda MaskerState TokenMaskBitset compileGrammarToDfa maskerInit advanceMaskerState advanceMaskerSubword resetMaskerBuffer computeTokenMaskBitset isTokenAllowed isTokenValidAtState isSubwordPrefixValid isGrammarTerminalAllowed] :i [(asl-slm/masker :a msk)])

fn compileGrammarToDfa grammarStr: Str -> msk/GrammarPda
  (msk/compileGrammarToDfa grammarStr)

fn maskerInit pda: msk/GrammarPda eosTokenId: Int -> msk/MaskerState
  (msk/maskerInit pda eosTokenId)

fn resetMaskerBuffer st: msk/MaskerState -> msk/MaskerState
  (msk/resetMaskerBuffer st)

fn advanceMaskerState pda: msk/GrammarPda st: msk/MaskerState tokenText: Str -> msk/MaskerState
  (msk/advanceMaskerState pda st tokenText)

fn advanceMaskerSubword pda: msk/GrammarPda st: msk/MaskerState subword: Str -> msk/MaskerState
  (msk/advanceMaskerSubword pda st subword)

fn computeTokenMaskBitset pda: msk/GrammarPda st: msk/MaskerState vocab: (List (Pair Int Str)) -> msk/TokenMaskBitset
  (msk/computeTokenMaskBitset pda st vocab)

fn isTokenAllowed mask: msk/TokenMaskBitset tokenId: Int -> Bool
  (msk/isTokenAllowed mask tokenId)

fn isTokenValidAtState pda: msk/GrammarPda st: msk/MaskerState tokenId: Int tokenText: Str -> Bool
  (msk/isTokenValidAtState pda st tokenId tokenText)

fn isSubwordPrefixValid pda: msk/GrammarPda prefix: Str -> Bool
  (msk/isSubwordPrefixValid pda prefix)

fn isGrammarTerminalAllowed pda: msk/GrammarPda tok: Str -> Bool
  (msk/isGrammarTerminalAllowed pda tok)
