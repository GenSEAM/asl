(module asl-target-llvm/bitRt
  :x [kindWidth kindSigned? llvmIntType binaryOpText binaryOpsText rotateText rotateLeft rotateRight countText bitCount leadingZeros trailingZeros byteSwapText byteSwap clzFunc ctzFunc]
  :i [])

; (:m :ref LL-BIT-RT :do "LLVM text for the integral bit surface: per-kind &, |, ^, ~, << and >> (ashr for signed kinds, lshr for unsigned), the fshl/fshr rotations, the ctpop/ctlz/cttz counts with a defined zero result, and llvm.bswap; every function returns text a caller splices into a module")

fn kindWidth name: String -> Int64
  (if (= name "U8") 8
    (if (= name "U16") 16
      (if (= name "U32") 32
        (if (= name "U64") 64
          (if (= name "I8") 8
            (if (= name "I16") 16
              (if (= name "I32") 32
                (if (= name "I64") 64 0))))))))

fn kindSigned? name: String -> Bool
  (if (= name "I8") true
    (if (= name "I16") true
      (if (= name "I32") true
        (if (= name "I64") true false))))

fn llvmIntType name: String -> String
  (stringConcat "i" (stringFromInt64 (kindWidth name)))

fn binaryOpText op: String kind: String -> String
  (let [(t (llvmIntType kind))]
    (if (= op "&") (str "and " t " %a, %b")
      (if (= op "|") (str "or " t " %a, %b")
        (if (= op "^") (str "xor " t " %a, %b")
          (if (= op "~") (str "xor " t " %a, -1")
            (if (= op "<<") (str "shl " t " %a, %b")
              (if (= op ">>")
                (if (kindSigned? kind) (str "ashr " t " %a, %b") (str "lshr " t " %a, %b"))
                "")))))))

fn binaryOpsText kind: String -> (List String)
  (list (binaryOpText "&" kind)
        (binaryOpText "|" kind)
        (binaryOpText "^" kind)
        (binaryOpText "~" kind)
        (binaryOpText "<<" kind)
        (binaryOpText ">>" kind))

fn rotateText dir: String kind: String -> String
  (let [(t (llvmIntType kind))
        (intr (if (= dir "left") "fshl" "fshr"))]
    (str "call " t " @llvm." intr "." t "(" t " %a, " t " %a, " t " %b)"))

fn rotateLeft kind: String -> String
  (rotateText "left" kind)

fn rotateRight kind: String -> String
  (rotateText "right" kind)

fn clzFunc kind: String -> String
  (let [(t (llvmIntType kind))]
    (str "declare " t " @llvm.ctlz." t "(" t ", i1)"))

fn ctzFunc kind: String -> String
  (let [(t (llvmIntType kind))]
    (str "declare " t " @llvm.cttz." t "(" t ", i1)"))

fn countText kind: String -> (List String)
  (let [(t (llvmIntType kind))]
    (list (str "call " t " @llvm.ctlz." t "(" t " %a, i1 false)")
          (str "call " t " @llvm.cttz." t "(" t " %a, i1 false)")))

fn bitCount kind: String -> String
  (let [(t (llvmIntType kind))]
    (str "call " t " @llvm.ctpop." t "(" t " %a)"))

fn leadingZeros kind: String -> String
  (let [(t (llvmIntType kind))]
    (str "call " t " @llvm.ctlz." t "(" t " %a, i1 false)"))

fn trailingZeros kind: String -> String
  (let [(t (llvmIntType kind))]
    (str "call " t " @llvm.cttz." t "(" t " %a, i1 false)"))

fn byteSwapText kind: String -> String
  (let [(t (llvmIntType kind))]
    (str "call " t " @llvm.bswap." t "(" t " %a)"))

fn byteSwap kind: String -> String
  (byteSwapText kind)
