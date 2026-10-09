(module asl-target-llvm/target
  :x [TargetFacts nativeTargetFacts wasm32TargetFacts isWasm32 growsLinearMemory lowerLlvmText]
  :i [])

schema TargetFacts
  triple: String
  pointerWidth: Int64
  pageSource: String
  trapMechanism: String

fn nativeTargetFacts triple: String -> TargetFacts
  (TargetFacts :triple triple :pointerWidth 64 :pageSource "mmap" :trapMechanism "setjmp")

fn wasm32TargetFacts -> TargetFacts
  (TargetFacts :triple "wasm32-unknown-unknown" :pointerWidth 32 :pageSource "memory.grow" :trapMechanism "wasm-trap")

fn isWasm32 facts: TargetFacts -> Bool
  (and (= facts.triple "wasm32-unknown-unknown") (= facts.pointerWidth 32))

fn growsLinearMemory facts: TargetFacts -> Bool
  (= facts.pageSource "memory.grow")

fn lowerLlvmLine facts: TargetFacts line: String -> String
  (if (stringStartsWith? line "@")
    line
    (let [(named (if (growsLinearMemory facts) (stringReplace line "llvm$2Ewasm$2Ememory$2Egrow$2Ei32" "llvm.wasm.memory.grow.i32") line))]
      (if (isWasm32 facts)
        (let [(convention (stringReplace named "tailcc " ""))]
          (if (and (stringStartsWith? (stringTrim convention) "define ") (not (stringContains? convention "\"target-features\"=")))
            (stringReplace convention " {" " \"target-features\"=\"+tail-call\" {")
            convention))
        named)))

fn byteIndexOf bs: Bytes byte: Int64 start: Int64 limit: Int64 -> Int64
  (if (>= start limit)
    -1
    (if (= (bytesGet bs start) byte)
      start
      (byteIndexOf bs byte (+ start 1) limit)))

fn findMatchingLoop bs: Bytes i: Int64 len: Int64 depth: Int64 -> Int64
  (if (>= i len)
    -1
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 40) (findMatchingLoop bs (+ i 1) len (+ depth 1)))
        ((= b 41) (if (= depth 1) i (findMatchingLoop bs (+ i 1) len (- depth 1))))
        (else (findMatchingLoop bs (+ i 1) len depth)))))

fn findMatchingParen s: String openIdx: Int64 -> Int64
  (let [(bs (stringToBytes s))]
    (findMatchingLoop bs (+ openIdx 1) (bytesLength bs) 1))

fn splitParamsLoop bs: Bytes i: Int64 len: Int64 depth: Int64 start: Int64 s: String acc: (List String) -> (List String)
  (if (>= i len)
    (let [(tail (stringTrim (optionOr (stringSlice s start len) "")))]
      (listReverse (if (stringEmpty? tail) acc (cons tail acc))))
    (let [(b (bytesGet bs i))]
      (cond
        ((or (= b 40) (or (= b 123) (or (= b 91) (= b 60))))
          (splitParamsLoop bs (+ i 1) len (+ depth 1) start s acc))
        ((or (= b 41) (or (= b 125) (or (= b 93) (= b 62))))
          (splitParamsLoop bs (+ i 1) len (max 0 (- depth 1)) start s acc))
        ((and (= b 44) (= depth 0))
          (let [(part (stringTrim (optionOr (stringSlice s start i) "")))]
            (splitParamsLoop bs (+ i 1) len 0 (+ i 1) s (cons part acc))))
        (else
          (splitParamsLoop bs (+ i 1) len depth start s acc)))))

fn splitParameters s: String -> (List String)
  (let [(bs (stringToBytes s))]
    (splitParamsLoop bs 0 (bytesLength bs) 0 0 s (list)))

fn lastSpaceAtDepthZeroLoop bs: Bytes i: Int64 depth: Int64 lastSp: Int64 -> Int64
  (if (< i 0)
    lastSp
    (let [(b (bytesGet bs i))]
      (cond
        ((or (= b 41) (or (= b 125) (or (= b 93) (= b 62))))
          (lastSpaceAtDepthZeroLoop bs (- i 1) (+ depth 1) lastSp))
        ((or (= b 40) (or (= b 123) (or (= b 91) (= b 60))))
          (lastSpaceAtDepthZeroLoop bs (- i 1) (max 0 (- depth 1)) lastSp))
        ((and (or (= b 32) (= b 9)) (= depth 0))
          (if (< lastSp 0)
            (lastSpaceAtDepthZeroLoop bs (- i 1) 0 i)
            (lastSpaceAtDepthZeroLoop bs (- i 1) 0 lastSp)))
        (else
          (lastSpaceAtDepthZeroLoop bs (- i 1) depth lastSp)))))

fn isParamOrArgName? s: String -> Bool
  (if (stringEmpty? s)
    false
    (let [(first (optionOr (stringSlice s 0 1) ""))]
      (or (= first "%")
          (or (= first "@")
              (or (= first "-")
                  (or (and (>= first "0") (<= first "9"))
                      (or (= s "true")
                          (or (= s "false")
                              (or (= s "null")
                                  (or (= s "undef")
                                      (or (= s "poison")
                                          (= s "zeroinitializer"))))))))))))

fn extractParameterType raw: String -> String
  (let [(param (stringTrim raw))
        (bs (stringToBytes param))
        (lastSp (lastSpaceAtDepthZeroLoop bs (- (bytesLength bs) 1) 0 -1))]
    (if (< lastSp 0)
      param
      (let [(valPart (stringTrim (optionOr (stringSlice param (+ lastSp 1) (stringLength param)) "")))
            (typePart (stringTrim (optionOr (stringSlice param 0 lastSp) "")))]
        (if (and (isParamOrArgName? valPart) (not (stringEmpty? typePart)))
          typePart
          param))))

fn stripModifiersLoop words: (List String) modifiers: (List String) -> (List String)
  (mt (listHead words)
    ((none) (list))
    ((some w)
      (if (listContains? modifiers w)
        (stripModifiersLoop (optionOr (listTail words) (list)) modifiers)
        words)))

fn llvmModifiers -> (List String)
  (list "tailcc" "fastcc" "coldcc" "ccc" "internal" "private" "external"
        "linkonce" "linkonce_odr" "weak" "weak_odr" "common" "appending"
        "extern_weak" "available_externally" "dso_local" "dso_preemptable"
        "default" "hidden" "protected" "zeroext" "signext" "inreg")

fn extractReturnType prefix: String -> String
  (let [(trimmed (stringTrim prefix))
        (cleanPrefix (if (stringStartsWith? trimmed "define ")
                       (stringTrim (optionOr (stringSlice trimmed 7 (stringLength trimmed)) ""))
                       (mt (stringIndexOf trimmed "musttail call ")
                         ((some at) (stringTrim (optionOr (stringSlice trimmed (+ at 14) (stringLength trimmed)) "")))
                         ((none) (mt (stringIndexOf trimmed "call ")
                                   ((some at) (stringTrim (optionOr (stringSlice trimmed (+ at 5) (stringLength trimmed)) "")))
                                   ((none) trimmed))))))
        (words (stringSplit cleanPrefix " "))
        (restWords (stripModifiersLoop words (llvmModifiers)))]
    (stringJoin restWords " "))

fn llvmDefineSignature line: String -> (Option (Pair String (List String)))
  (let [(bs (stringToBytes line))
        (len (bytesLength bs))
        (atIdx (byteIndexOf bs 64 0 len))]
    (if (< atIdx 0)
      (none)
      (let [(openIdx (byteIndexOf bs 40 atIdx len))]
        (if (< openIdx 0)
          (none)
          (let [(closeIdx (findMatchingParen line openIdx))]
            (if (< closeIdx 0)
              (none)
              (let [(prefix (optionOr (stringSlice line 0 atIdx) ""))
                    (retTy (extractReturnType prefix))
                    (paramsStr (optionOr (stringSlice line (+ openIdx 1) closeIdx) ""))
                    (paramTypes (if (stringEmpty? (stringTrim paramsStr))
                                  (list)
                                  (map extractParameterType (splitParameters paramsStr))))]
                (some (pair retTy paramTypes)))))))))

fn llvmCallSignature line: String -> (Option (Pair String (List String)))
  (let [(bs (stringToBytes line))
        (len (bytesLength bs))
        (atIdx (byteIndexOf bs 64 0 len))]
    (if (< atIdx 0)
      (none)
      (let [(openIdx (byteIndexOf bs 40 atIdx len))]
        (if (< openIdx 0)
          (none)
          (let [(closeIdx (findMatchingParen line openIdx))]
            (if (< closeIdx 0)
              (none)
              (let [(prefix (optionOr (stringSlice line 0 atIdx) ""))
                    (retTy (extractReturnType prefix))
                    (paramsStr (optionOr (stringSlice line (+ openIdx 1) closeIdx) ""))
                    (paramTypes (if (stringEmpty? (stringTrim paramsStr))
                                  (list)
                                  (map extractParameterType (splitParameters paramsStr))))]
                (some (pair retTy paramTypes)))))))))

fn signaturesMatch? callerSig: (Option (Pair String (List String))) calleeSig: (Option (Pair String (List String))) -> Bool
  (mt callerSig
    ((none) false)
    ((some c)
      (mt calleeSig
        ((none) false)
        ((some k)
          (and (= (pairFirst c) (pairFirst k))
               (= (pairSecond c) (pairSecond k)))))))

fn lowerLlvmLinesLoop facts: TargetFacts lines: (List String) currentSig: (Option (Pair String (List String))) acc: (List String) -> (List String)
  (mt (listHead lines)
    ((none) (listReverse acc))
    ((some line)
      (let [(definition (stringTrim line))
            (sig (if (stringStartsWith? definition "define ") (llvmDefineSignature definition) currentSig))
            (lowered (lowerLlvmLine facts line))
            (safeLine (if (and (isWasm32 facts)
                               (stringContains? line "musttail call")
                               (not (signaturesMatch? sig (llvmCallSignature line))))
                        (stringReplace lowered "musttail " "")
                        lowered))]
        (lowerLlvmLinesLoop facts (optionOr (listTail lines) (list)) sig (cons safeLine acc)))))

fn lowerLlvmLines facts: TargetFacts lines: (List String) currentSig: (Option (Pair String (List String))) -> (List String)
  (lowerLlvmLinesLoop facts lines currentSig (list))

fn lowerLlvmText text: String facts: TargetFacts -> String
  (if (or (growsLinearMemory facts) (isWasm32 facts))
    (stringJoin (lowerLlvmLines facts (stringSplit text "\n") (none)) "\n")
    text)
