(module rcDirRead
  :x [main]
  :i [])

fn ! main -> (Result Unit String)
  (do (println (match (fileReadBytes ".") ((err e) (str "err " e)) ((ok b) (str "ok " (bytesLength b)))))
      (println (match (fileReadString ".") ((err e) (str "err " e)) ((ok s) (str "ok " (stringLength s)))))
      (ok ()))
