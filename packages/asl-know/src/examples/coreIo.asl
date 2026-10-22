(module asl-know/examples/coreIo :x [lineCount! selfTest] :i [])

fn ! lineCount! path: String -> Int64
  (match (fileReadString path)
    ((err _) -1)
    ((ok text) (listCount (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines text))))

fn ! selfTest -> Bool
  (let [(dir ".asl/run/knowExample")
        (path (str dir "/a.txt"))
        (made (dirCreate dir))
        (wrote (fileWrite path "one\ntwo\n"))
        (names (resultOr (dirList dir) []))
        (n (lineCount! path))
        (gone (pathRemove dir))]
    (and (ok? made) (ok? wrote) (= names ["a.txt"]) (= n 2) (ok? gone) (= (lineCount! path) -1)))
