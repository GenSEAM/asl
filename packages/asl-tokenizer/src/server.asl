(module asl-tokenizer/server
  :x [main]
  :i [(asl-tokenizer/tokenizer :a tok)])

fn readExact! fd: Int64 needed: Int64 acc: String -> (Result String String)
  (if (<= needed 0) (ok acc)
    (let [(r (fdRead fd needed))]
      (mt r
        ((err e) (err e))
        ((ok s)
          (let [(got (stringLength s))]
            (if (<= got 0)
              (err "unexpectedEOF")
              (readExact! fd (- needed got) (str acc s))))))))

fn readI32! fd: Int64 -> (Result Int64 String)
  (let [(r (readExact! fd 4 ""))]
    (mt r
      ((err e) (err e))
      ((ok s)
        (let [(b (stringToBytes s))
              (val (+ (+ (* (bytesGet b 0) 16777216) (* (bytesGet b 1) 65536))
                      (+ (* (bytesGet b 2) 256) (bytesGet b 3))))]
          (ok val)))))

fn serverLoop! tokenizer: tok/Tokenizer -> (Result Int64 String)
  (let [(rCmd (readExact! 0 1 ""))]
    (mt rCmd
      ((err e) (ok 0))
      ((ok cmd)
        (cond
          ((= cmd "Q") (ok 0))
          ((= cmd "T")
            (let [(rLen (readI32! 0))]
              (mt rLen
                ((err e) (err e))
                ((ok len)
                  (let [(rText (readExact! 0 len ""))]
                    (mt rText
                      ((err e) (err e))
                      ((ok text)
                        (let [(cnt (tok/countTokens! tokenizer text))]
                          (do
                            (fdWrite 1 (str (stringFromInt64 cnt) "\n"))
                            (serverLoop! tokenizer))))))))))
          ((= cmd "F")
            (let [(rLen (readI32! 0))]
              (mt rLen
                ((err e) (err e))
                ((ok len)
                  (let [(rPath (readExact! 0 len ""))]
                    (mt rPath
                      ((err e) (err e))
                      ((ok path)
                        (let [(rBytes (fileReadBytes path))]
                          (mt rBytes
                            ((err e) (err (str "fileReadBytes " path " failed: " e)))
                            ((ok bs)
                              (let [(cnt (tok/countTokensBytes! tokenizer bs))]
                                (do
                                  (fdWrite 1 (str (stringFromInt64 cnt) "\n"))
                                  (serverLoop! tokenizer)))))))))))))
          (else (err (str "unknown command: " cmd)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(dataDir (if (listEmpty? args) "data/tokenizers" (optionOr (listHead args) "data/tokenizers")))
        (resTok (tok/loadTokenizer! dataDir))]
    (mt resTok
      ((err e) (err (str "loadTokenizer failed: " e)))
      ((ok tokenizer)
        (serverLoop! tokenizer))))
