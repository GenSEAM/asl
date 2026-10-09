(module asl-crypto/aes
  :x [aesExpandKey aesEncryptBlock aesDecryptBlock aesCbcDecrypt aesCbcEncrypt aesCtrCrypt aesGcmEncrypt aesGcmDecrypt]
  :i [])

fn aesSbox x: Int64 -> Int64
  (optionOr (listGet [99 124 119 123 242 107 111 197 48 1 103 43 254 215 171 118 202 130 201 125 250 89 71 240 173 212 162 175 156 164 114 192 183 253 147 38 54 63 247 204 52 165 229 241 113 216 49 21 4 199 35 195 24 150 5 154 7 18 128 226 235 39 178 117 9 131 44 26 27 110 90 160 82 59 214 179 41 227 47 132 83 209 0 237 32 252 177 91 106 203 190 57 74 76 88 207 208 239 170 251 67 77 51 133 69 249 2 127 80 60 159 168 81 163 64 143 146 157 56 245 188 182 218 33 16 255 243 210 205 12 19 236 95 151 68 23 196 167 126 61 100 93 25 115 96 129 79 220 34 42 144 136 70 238 184 20 222 94 11 219 224 50 58 10 73 6 36 92 194 211 172 98 145 149 228 121 231 200 55 109 141 213 78 169 108 86 244 234 101 122 174 8 186 120 37 46 28 166 180 198 232 221 116 31 75 189 139 138 112 62 181 102 72 3 246 14 97 53 87 185 134 193 29 158 225 248 152 17 105 217 142 148 155 30 135 233 206 85 40 223 140 161 137 13 191 230 66 104 65 153 45 15 176 84 187 22] x) 0)

fn aesInvSbox x: Int64 -> Int64
  (optionOr (listGet [82 9 106 213 48 54 165 56 191 64 163 158 129 243 215 251 124 227 57 130 155 47 255 135 52 142 67 68 196 222 233 203 84 123 148 50 166 194 35 61 238 76 149 11 66 250 195 78 8 46 161 102 40 217 36 178 118 91 162 73 109 139 209 37 114 248 246 100 134 104 152 22 212 164 92 204 93 101 182 146 108 112 72 80 253 237 185 218 94 21 70 87 167 141 157 132 144 216 171 0 140 188 211 10 247 228 88 5 184 179 69 6 208 44 30 143 202 63 15 2 193 175 189 3 1 19 138 107 58 145 17 65 79 103 220 234 151 242 207 206 240 180 230 115 150 172 116 34 231 173 53 133 226 249 55 232 28 117 223 110 71 241 26 113 29 41 197 137 111 183 98 14 170 24 190 27 252 86 62 75 198 210 121 32 154 219 192 254 120 205 90 244 31 221 168 51 136 7 199 49 177 18 16 89 39 128 236 95 96 81 127 169 25 181 74 13 45 229 122 159 147 201 156 239 160 224 59 77 174 42 245 176 200 235 187 60 131 83 153 97 23 43 4 126 186 119 214 38 225 105 20 99 85 33 12 125] x) 0)

fn aesRcon round: Int64 -> Int64
  (if (= round 1) 1 (if (= round 2) 2 (if (= round 3) 4 (if (= round 4) 8 (if (= round 5) 16 (if (= round 6) 32 (if (= round 7) 64 (if (= round 8) 128 (if (= round 9) 27 (if (= round 10) 54 0))))))))))

fn aesGfMul a: Int64 b: Int64 -> Int64
  (let [(loop (fn [loop x y acc] -> Int64
    (if (= y 0) acc
      (let [(nextAcc (if (= (mod y 2) 1) (^ acc x) acc))
            (nextX (if (>= x 128) (^ (mod (* x 2) 256) 27) (mod (* x 2) 256)))]
        (loop loop nextX (/ y 2) nextAcc)))))]
    (loop loop a b 0))

fn ! aesExpandKey key: Bytes -> (Result Bytes String)
  (let [(keyLength (bytesLength key))]
    (if (not (or (= keyLength 16) (or (= keyLength 24) (= keyLength 32)))) (err "invalidKeyLength")
      (let [(nk (/ keyLength 4)) (nr (+ (/ keyLength 4) 6)) (words (* (+ (/ keyLength 4) 7) 4))
            (expanded (bytesAlloc (* words 4)))]
        (let [(copy (fn [copy i] -> Unit
          (if (< i keyLength) (do (bytesSet expanded i (bytesGet key i)) (copy copy (+ i 1))) ())))
              (expand (fn [expand i] -> Unit
                (if (< i words)
                  (let [(prev (* (- i 1) 4))
                        (t0 (bytesGet expanded prev)) (t1 (bytesGet expanded (+ prev 1)))
                        (t2 (bytesGet expanded (+ prev 2))) (t3 (bytesGet expanded (+ prev 3)))
                        (rotate (= (mod i nk) 0)) (subOnly (and (> nk 6) (= (mod i nk) 4)))
                        (a (if rotate (^ (aesSbox t1) (aesRcon (/ i nk))) (if subOnly (aesSbox t0) t0)))
                        (b (if rotate (aesSbox t2) (if subOnly (aesSbox t1) t1)))
                        (c (if rotate (aesSbox t3) (if subOnly (aesSbox t2) t2)))
                        (d (if rotate (aesSbox t0) (if subOnly (aesSbox t3) t3)))
                        (base (* i 4)) (from (* (- i nk) 4))]
                    (do (bytesSet expanded base (^ (bytesGet expanded from) a))
                        (bytesSet expanded (+ base 1) (^ (bytesGet expanded (+ from 1)) b))
                        (bytesSet expanded (+ base 2) (^ (bytesGet expanded (+ from 2)) c))
                        (bytesSet expanded (+ base 3) (^ (bytesGet expanded (+ from 3)) d))
                        (expand expand (+ i 1)))) ())))]
          (do (copy copy 0) (expand expand nk) (ok expanded))))))

fn ! aesAddRoundKey! state: Bytes keys: Bytes round: Int64 -> Unit
  (let [(loop (fn [loop i] -> Unit
    (if (< i 16) (do (bytesSet state i (^ (bytesGet state i) (bytesGet keys (+ (* round 16) i)))) (loop loop (+ i 1))) ())))]
    (loop loop 0))

fn ! aesSubBytes! state: Bytes inverse: Bool -> Unit
  (let [(loop (fn [loop i] -> Unit
    (if (< i 16) (do (bytesSet state i (if inverse (aesInvSbox (bytesGet state i)) (aesSbox (bytesGet state i)))) (loop loop (+ i 1))) ())))]
    (loop loop 0))

fn ! aesShiftRows! state: Bytes inverse: Bool -> Unit
  (let [(copy (bytesAlloc 16))
        (loop (fn [loop col row] -> Unit
          (if (< col 4)
            (if (< row 4)
              (let [(sourceCol (if inverse (mod (+ col (- 4 row)) 4) (mod (+ col row) 4)))]
                (do (bytesSet copy (+ (* col 4) row) (bytesGet state (+ (* sourceCol 4) row)))
                    (loop loop col (+ row 1))))
              (loop loop (+ col 1) 0)) ())))]
    (do (loop loop 0 0)
        (let [(copyBack (fn [copyBack i] -> Unit
          (if (< i 16) (do (bytesSet state i (bytesGet copy i)) (copyBack copyBack (+ i 1))) ())))]
          (copyBack copyBack 0))))

fn ! aesMixColumns! state: Bytes inverse: Bool -> Unit
  (let [(loop (fn [loop col] -> Unit
    (if (< col 4)
      (let [(i (* col 4)) (a (bytesGet state i)) (b (bytesGet state (+ i 1))) (c (bytesGet state (+ i 2))) (d (bytesGet state (+ i 3)))]
        (do
          (bytesSet state i (if inverse (^ (^ (aesGfMul a 14) (aesGfMul b 11)) (^ (aesGfMul c 13) (aesGfMul d 9))) (^ (^ (aesGfMul a 2) (aesGfMul b 3)) (^ c d))))
          (bytesSet state (+ i 1) (if inverse (^ (^ (aesGfMul a 9) (aesGfMul b 14)) (^ (aesGfMul c 11) (aesGfMul d 13))) (^ (^ a (aesGfMul b 2)) (^ (aesGfMul c 3) d))))
          (bytesSet state (+ i 2) (if inverse (^ (^ (aesGfMul a 13) (aesGfMul b 9)) (^ (aesGfMul c 14) (aesGfMul d 11))) (^ (^ a b) (^ (aesGfMul c 2) (aesGfMul d 3)))))
          (bytesSet state (+ i 3) (if inverse (^ (^ (aesGfMul a 11) (aesGfMul b 13)) (^ (aesGfMul c 9) (aesGfMul d 14))) (^ (^ (aesGfMul a 3) b) (^ c (aesGfMul d 2)))))
          (loop loop (+ col 1)))) ())))]
    (loop loop 0))

fn ! aesEncryptBlock key: Bytes block: Bytes -> (Result Bytes String)
  (if (!= (bytesLength block) 16) (err "invalidBlockLength")
    (mt (aesExpandKey key)
      ((err e) (err e))
      ((ok keys)
        (let [(rounds (- (/ (bytesLength keys) 16) 1)) (state (bytesAlloc 16))]
          (let [(copy (fn [copy i] -> Unit
            (if (< i 16) (do (bytesSet state i (bytesGet block i)) (copy copy (+ i 1))) ())))
                (run (fn [run r] -> Unit
                  (if (< r (- rounds 1))
                    (do (aesSubBytes! state false) (aesShiftRows! state false) (aesMixColumns! state false) (aesAddRoundKey! state keys (+ r 1)) (run run (+ r 1))) ())))]
            (do (copy copy 0) (aesAddRoundKey! state keys 0) (run run 0) (aesSubBytes! state false) (aesShiftRows! state false) (aesAddRoundKey! state keys rounds) (ok state)))))))

fn ! aesDecryptBlock key: Bytes block: Bytes -> (Result Bytes String)
  (if (!= (bytesLength block) 16) (err "invalidBlockLength")
    (mt (aesExpandKey key)
      ((err e) (err e))
      ((ok keys)
        (let [(rounds (- (/ (bytesLength keys) 16) 1)) (state (bytesAlloc 16))]
          (let [(copy (fn [copy i] -> Unit
            (if (< i 16) (do (bytesSet state i (bytesGet block i)) (copy copy (+ i 1))) ())))
                (run (fn [run r] -> Unit
                  (if (> r 0)
                    (do (aesShiftRows! state true) (aesSubBytes! state true) (aesAddRoundKey! state keys r) (aesMixColumns! state true) (run run (- r 1))) ())))]
            (do (copy copy 0) (aesAddRoundKey! state keys rounds) (run run (- rounds 1)) (aesShiftRows! state true) (aesSubBytes! state true) (aesAddRoundKey! state keys 0) (ok state)))))))

fn ! aesCbcDecrypt key: Bytes iv: Bytes ciphertext: Bytes -> (Result Bytes String)
  (let [(length (bytesLength ciphertext))]
    (if (or (!= (bytesLength iv) 16) (= length 0) (!= (mod length 16) 0)) (err "invalidCbcInput")
      (mt (aesExpandKey key)
        ((err e) (err e))
        ((ok _) (let [(plain (bytesAlloc length))
                      (loop (fn [loop offset] -> (Result Bytes String)
                        (if (>= offset length) (ok plain)
                          (mt (aesDecryptBlock key (let [(block (bytesAlloc 16))
                            (copy (fn [copy i] -> Unit (if (< i 16) (do (bytesSet block i (bytesGet ciphertext (+ offset i))) (copy copy (+ i 1))) ())))]
                            (do (copy copy 0) block)))
                            ((err e) (err e))
                            ((ok dec) (let [(prior (if (= offset 0) iv ciphertext))
                              (copy (fn [copy i] -> Unit
                                (if (< i 16) (do (bytesSet plain (+ offset i) (^ (bytesGet dec i) (bytesGet prior (+ (if (= offset 0) 0 (- offset 16)) i)))) (copy copy (+ i 1))) ())))]
                              (do (copy copy 0) (loop loop (+ offset 16))))))))) ]
          (mt (loop loop 0)
            ((err e) (err e))
            ((ok padded)
              (let [(padding (bytesGet padded (- length 1)))
                    (valid (and (>= padding 1) (<= padding 16)))
                    (check (fn [check i mismatch] -> Int64
                      (if (>= i 16) mismatch
                        (let [(inside (and valid (< i padding)))
                              (diff (if inside (^ (bytesGet padded (- (- length 1) i)) padding) 0))]
                          (check check (+ i 1) (if (= diff 0) mismatch (+ mismatch 1)))))))]
                (if (and valid (= (check check 0 0) 0))
                  (ok (let [(out (bytesAlloc (- length padding)))
                            (copy (fn [copy i] -> Unit (if (< i (- length padding)) (do (bytesSet out i (bytesGet padded i)) (copy copy (+ i 1))) ())))]
                        (do (copy copy 0) out))) (err "badPadding"))))))))))

fn ! aesCtrCrypt key: Bytes counterBlock: Bytes input: Bytes -> (Result Bytes String)
  (let [(length (bytesLength input))]
    (if (!= (bytesLength counterBlock) 16) (err "invalidCtrCounter")
      (mt (aesExpandKey key)
        ((err e) (err e))
        ((ok _) (let [(counter (bytesAlloc 16)) (output (bytesAlloc length))
            (copyCounter (fn [copyCounter i] -> Unit
              (if (< i 16) (do (bytesSet counter i (bytesGet counterBlock i)) (copyCounter copyCounter (+ i 1))) ())))
            (increment (fn [increment i] -> Unit
              (if (>= i 0)
                (let [(value (+ (bytesGet counter i) 1))]
                  (do (bytesSet counter i (mod value 256)) (if (>= value 256) (increment increment (- i 1)) ()))) ()) ))]
        (do (copyCounter copyCounter 0)
          (let [(loop (fn [loop offset] -> (Result Bytes String)
            (if (>= offset length) (ok output)
              (mt (aesEncryptBlock key counter)
                ((err e) (err e))
                ((ok stream)
                  (let [(count (if (< (- length offset) 16) (- length offset) 16))
                        (copy (fn [copy i] -> Unit
                          (if (< i count)
                            (do (bytesSet output (+ offset i) (^ (bytesGet input (+ offset i)) (bytesGet stream i))) (copy copy (+ i 1))) ())))]
                    (do (copy copy 0) (increment increment 15) (loop loop (+ offset count)))))))))]
            (loop loop 0))))))))

fn ! aesCbcEncrypt key: Bytes iv: Bytes plaintext: Bytes -> (Result Bytes String)
  (if (!= (bytesLength iv) 16) (err "invalidCbcIv")
    (let [(length (bytesLength plaintext)) (padding (- 16 (mod (bytesLength plaintext) 16)))
          (total (+ (bytesLength plaintext) (- 16 (mod (bytesLength plaintext) 16))))
          (padded (bytesAlloc (+ (bytesLength plaintext) (- 16 (mod (bytesLength plaintext) 16)))))
          (output (bytesAlloc (+ (bytesLength plaintext) (- 16 (mod (bytesLength plaintext) 16)))))]
      (let [(fill (fn [fill i] -> Unit
        (if (< i total)
          (do (bytesSet padded i (if (< i length) (bytesGet plaintext i) padding)) (fill fill (+ i 1))) ())))
            (loop (fn [loop offset] -> (Result Bytes String)
              (if (>= offset total) (ok output)
                (let [(block (bytesAlloc 16)) (prior (if (= offset 0) iv output))
                      (copy (fn [copy i] -> Unit
                        (if (< i 16)
                          (do (bytesSet block i (^ (bytesGet padded (+ offset i)) (bytesGet prior (+ (if (= offset 0) 0 (- offset 16)) i)))) (copy copy (+ i 1))) ()) ))]
                  (mt (aesEncryptBlock key (do (copy copy 0) block))
                    ((err e) (err e))
                    ((ok encrypted) (let [(write (fn [write i] -> Unit
                      (if (< i 16) (do (bytesSet output (+ offset i) (bytesGet encrypted i)) (write write (+ i 1))) ())))]
                      (do (write write 0) (loop loop (+ offset 16))))))))))]
        (do (fill fill 0) (loop loop 0)))))

fn ! aesGf128Multiply! x: Bytes h: Bytes -> Bytes
  (let [(z (bytesAlloc 16)) (v (bytesAlloc 16))
        (copy (fn [copy i] -> Unit (if (< i 16) (do (bytesSet v i (bytesGet h i)) (copy copy (+ i 1))) ())))
        (loop (fn [loop i] -> Bytes
          (if (>= i 128) z
            (let [(bitByte (bytesGet x (/ i 8)))
                  (mask (if (= (mod i 8) 0) 128 (if (= (mod i 8) 1) 64 (if (= (mod i 8) 2) 32 (if (= (mod i 8) 3) 16 (if (= (mod i 8) 4) 8 (if (= (mod i 8) 5) 4 (if (= (mod i 8) 6) 2 1))))))))
                  (xorZ (fn [xorZ j] -> Unit (if (< j 16) (do (bytesSet z j (^ (bytesGet z j) (bytesGet v j))) (xorZ xorZ (+ j 1))) ())))
                  (shift (fn [shift j carry] -> Unit
                    (if (< j 16)
                      (let [(old (bytesGet v j)) (next (+ (/ old 2) carry))]
                        (do (bytesSet v j next) (shift shift (+ j 1) (if (= (mod old 2) 1) 128 0)))) ())))]
              (do (if (= (mod (/ bitByte mask) 2) 1) (xorZ xorZ 0) ())
                  (let [(lastBit (mod (bytesGet v 15) 2))]
                    (do (shift shift 0 0) (if (= lastBit 1) (bytesSet v 0 (^ (bytesGet v 0) 225)) ())
                        (loop loop (+ i 1)))))))))]
    (do (copy copy 0) (loop loop 0)))

fn ! aesGhashData! y: Bytes data: Bytes h: Bytes -> Unit
  (let [(length (bytesLength data))
        (loop (fn [loop offset] -> Unit
          (if (< offset length)
            (let [(block (bytesAlloc 16)) (count (if (< (- length offset) 16) (- length offset) 16))
                  (copy (fn [copy i] -> Unit
                    (if (< i count) (do (bytesSet block i (bytesGet data (+ offset i))) (copy copy (+ i 1))) ())))
                  (xorY (fn [xorY i] -> Unit
                    (if (< i 16) (do (bytesSet block i (^ (bytesGet block i) (bytesGet y i))) (xorY xorY (+ i 1))) ())))
                  (updateY (fn [updateY product i] -> Unit
                    (if (< i 16) (do (bytesSet y i (bytesGet product i)) (updateY updateY product (+ i 1))) ())))]
              (do (copy copy 0) (xorY xorY 0) (updateY updateY (aesGf128Multiply! block h) 0) (loop loop (+ offset 16))))) ()))]
    (loop loop 0))

fn ! aesGhash! aad: Bytes ciphertext: Bytes h: Bytes -> Bytes
  (let [(y (bytesAlloc 16)) (lengthBlock (bytesAlloc 16))
        (writeLength (fn [writeLength i value base] -> Unit
          (if (>= i 0) (do (bytesSet lengthBlock (+ base i) (mod value 256)) (writeLength writeLength (- i 1) (/ value 256) base)) ())))
        (finish (fn [finish i] -> Unit
          (if (< i 16) (do (bytesSet lengthBlock i (^ (bytesGet lengthBlock i) (bytesGet y i))) (finish finish (+ i 1))) ())))]
    (do (aesGhashData! y aad h) (aesGhashData! y ciphertext h)
        (writeLength writeLength 7 (* (bytesLength aad) 8) 0)
        (writeLength writeLength 7 (* (bytesLength ciphertext) 8) 8)
        (finish finish 0) (aesGf128Multiply! lengthBlock h)))

fn ! aesGcmStart! key: Bytes iv: Bytes -> (Result Bytes String)
  (if (!= (bytesLength iv) 12) (err "invalidGcmIv")
    (let [(j0 (bytesAlloc 16)) (copy (fn [copy i] -> Unit
      (if (< i 12) (do (bytesSet j0 i (bytesGet iv i)) (copy copy (+ i 1))) ()) ))]
      (do (copy copy 0) (bytesSet j0 15 1) (ok j0))))

fn ! aesGcmEncrypt key: Bytes iv: Bytes aad: Bytes plaintext: Bytes -> (Result Bytes String)
  (mt (aesGcmStart! key iv)
    ((err e) (err e))
    ((ok j0)
      (let [(zero (bytesAlloc 16)) (counter (bytesAlloc 16)) (output (bytesAlloc (+ (bytesLength plaintext) 16)))
            (copy (fn [copy i] -> Unit
              (if (< i 16) (do (bytesSet counter i (bytesGet j0 i)) (copy copy (+ i 1))) ())))]
        (mt (aesEncryptBlock key zero)
          ((err e) (err e))
          ((ok h)
            (do (copy copy 0) (bytesSet counter 15 2)
              (mt (aesCtrCrypt key counter plaintext)
                ((err e) (err e))
                ((ok ciphertext)
                  (let [(tagMask (aesEncryptBlock key j0))
                        (tag (aesGhash! aad ciphertext h))]
                    (mt tagMask
                      ((err e) (err e))
                      ((ok mask)
                        (let [(copyCipher (fn [copyCipher i] -> Unit
                          (if (< i (bytesLength ciphertext)) (do (bytesSet output i (bytesGet ciphertext i)) (copyCipher copyCipher (+ i 1))) ())))
                              (copyTag (fn [copyTag i] -> Unit
                                (if (< i 16) (do (bytesSet output (+ (bytesLength ciphertext) i) (^ (bytesGet tag i) (bytesGet mask i))) (copyTag copyTag (+ i 1))) ())))]
                          (do (copyCipher copyCipher 0) (copyTag copyTag 0) (ok output))))))))))))))

fn ! aesGcmDecrypt key: Bytes iv: Bytes aad: Bytes ciphertextAndTag: Bytes -> (Result Bytes String)
  (let [(total (bytesLength ciphertextAndTag))]
    (if (< total 16) (err "authFailed")
      (mt (aesGcmStart! key iv)
        ((err e) (err e))
        ((ok j0)
          (let [(cipherLength (- total 16)) (ciphertext (bytesAlloc (- total 16))) (tag (bytesAlloc 16))
                (copy (fn [copy i] -> Unit
                  (if (< i cipherLength) (do (bytesSet ciphertext i (bytesGet ciphertextAndTag i)) (copy copy (+ i 1))) ())))
                (copyTag (fn [copyTag i] -> Unit
                  (if (< i 16) (do (bytesSet tag i (bytesGet ciphertextAndTag (+ cipherLength i))) (copyTag copyTag (+ i 1))) ())))
                (counter (bytesAlloc 16)) (zero (bytesAlloc 16))]
            (mt (aesEncryptBlock key zero)
              ((err e) (err e))
              ((ok h)
                (let [(copyCounter (fn [copyCounter i] -> Unit
                  (if (< i 16) (do (bytesSet counter i (bytesGet j0 i)) (copyCounter copyCounter (+ i 1))) ())))]
                  (do (copy copy 0) (copyTag copyTag 0) (copyCounter copyCounter 0) (bytesSet counter 15 2)
                    (mt (aesEncryptBlock key j0)
                      ((err e) (err e))
                      ((ok mask)
                        (let [(expected (aesGhash! aad ciphertext h))
                              (diff (fn [diff i acc] -> Int64
                                (if (< i 16) (diff diff (+ i 1) (| acc (^ (^ (bytesGet expected i) (bytesGet mask i)) (bytesGet tag i)))) acc)))]
                          (if (!= (diff diff 0 0) 0) (err "authFailed")
                            (aesCtrCrypt key counter ciphertext))))))))))))))
