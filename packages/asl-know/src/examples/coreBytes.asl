(module asl-know/examples/coreBytes :x [digest selfTest] :i [])

fn digest s: String -> String
  (let [(b (stringToBytes s))]
    (str (bytesLength b) ":" (bytesToBase64 b) ":" (bytesSha256 b)))

fn selfTest -> Bool
  (= (digest "abc") "3:YWJj:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
