(module asl-crypto/random
  :x [randomBytes uuidV4]
  :i [(asl-crypto/hmac :a h)])

fn ! randomBytes n: Int64 -> (Result Bytes String)
  (if (or (< n 0) (> n 1048576))
    (err "randomBytes: n must be between 0 and 1048576")
    (fileReadRange "/dev/urandom" 0 n))

fn uuidText hex: String -> String
  (str (optionOr (stringSlice hex 0 8) "") "-"
       (optionOr (stringSlice hex 8 12) "") "-"
       (optionOr (stringSlice hex 12 16) "") "-"
       (optionOr (stringSlice hex 16 20) "") "-"
       (optionOr (stringSlice hex 20 32) ""))

fn ! uuidV4 -> (Result String String)
  (match (randomBytes 16)
    ((err e) (err e))
    ((ok b)
      (do
        (bytesSet b 6 (| (& (bytesGet b 6) 15) 64))
        (bytesSet b 8 (| (& (bytesGet b 8) 63) 128))
        (ok (uuidText (h/bytesToHex b))))))
