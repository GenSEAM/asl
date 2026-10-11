(module asl-compiler/checkCache :x [Verdict cacheDir! verdictKey! keyText encodeVerdict decodeVerdict lookup! store! replay!] :i [(asl-checker/resolve :a r)])

(schema Verdict (:f exitCode Int64) (:f body String))

fn magic -> String
  "aslCheckVerdict 1"

fn ! cacheDir! -> String
  (let [(configured (optionOr (envGet "ASL_CHECK_CACHE") ""))]
    (if (stringEmpty? configured) (str (optionOr (envGet "HOME") ".") "/.asl/cache/check") configured))

fn ! shaOf! memo: (Map String String) path: String -> (Option (Pair String (Map String String)))
  (mt (mapGet memo path)
    ((some d) (some (pair d memo)))
    ((none) (mt (fileReadBytes path)
      ((err _) (none))
      ((ok bytes) (let [(d (bytesSha256 bytes))] (some (pair d (mapSet memo path d))))))))

fn ! hashLines! paths: (List String) memo: (Map String String) acc: String -> (Option (Pair String (Map String String)))
  (mt (listHead paths)
    ((none) (some (pair acc memo)))
    ((some p) (mt (shaOf! memo p)
      ((none) (none))
      ((some got) (hashLines! (optionOr (listTail paths) (list)) (pairSecond got) (str acc p "=" (pairFirst got) "\n"))))))

fn ! closureOf! real: String -> (Option (List String))
  (let [(cl (r/loadModuleClosure! real false))]
    (if (and (listEmpty? cl.unresolved) (listEmpty? cl.errors)) (some (listSort (cons real cl.paths))) (none)))

fn ! checkerSource! -> (Option String)
  (let [(p "./asl/packages/asl-compiler/src/asl1.asl")]
    (if (fileExists? p) (resultToOption (realPath p)) (none)))

fn keyText entryReal: String deps: String checker: String -> String
  (str (magic) "\nentry " entryReal "\ndeps\n" deps "checker\n" checker)

fn ! verdictKey! entry: String -> (Option String)
  (mt (resultToOption (realPath entry))
    ((none) (none))
    ((some entryReal) (mt (closureOf! entryReal)
      ((none) (none))
      ((some deps) (mt (checkerSource!)
        ((none) (none))
        ((some checkerReal) (mt (if (= checkerReal entryReal) (some deps) (closureOf! checkerReal))
          ((none) (none))
          ((some checkerDeps) (mt (hashLines! deps (mapEmpty) "")
            ((none) (none))
            ((some d) (mt (hashLines! checkerDeps (pairSecond d) "")
              ((none) (none))
              ((some c) (some (bytesSha256 (stringToBytes (keyText entryReal (pairFirst d) (pairFirst c)))))))))))))))))

fn entryPath dir: String key: String -> String
  (str dir "/" key ".verdict")

fn encodeVerdict key: String v: Verdict -> String
  (str (magic) "\n" key "\n" (stringFromInt64 v.exitCode) "\n" (bytesSha256 (stringToBytes v.body)) "\n" v.body)

fn lineAt s: String from: Int64 -> (Option (Pair String Int64))
  (mt (stringSlice s from (stringLength s))
    ((none) (none))
    ((some rest) (mt (stringIndexOf rest "\n")
      ((none) (none))
      ((some i) (optionMap (fn [(l String)] -> (Pair String Int64) (pair l (+ from (+ i 1)))) (stringSlice s from (+ from i)))))))

fn decodeVerdict key: String text: String -> (Option Verdict)
  (mt (lineAt text 0)
    ((none) (none))
    ((some l1) (mt (lineAt text (pairSecond l1))
      ((none) (none))
      ((some l2) (mt (lineAt text (pairSecond l2))
        ((none) (none))
        ((some l3) (mt (lineAt text (pairSecond l3))
          ((none) (none))
          ((some l4) (mt (stringSlice text (pairSecond l4) (stringLength text))
            ((none) (none))
            ((some body) (mt (stringToInt64 (pairFirst l3))
              ((none) (none))
              ((some code) (if (and (= (pairFirst l1) (magic)) (and (= (pairFirst l2) key) (= (pairFirst l4) (bytesSha256 (stringToBytes body)))))
                             (some (Verdict :exitCode code :body body))
                             (none))))))))))))))

fn ! lookup! key: String -> (Option Verdict)
  (mt (fileReadString (entryPath (cacheDir!) key))
    ((err _) (none))
    ((ok text) (decodeVerdict key text)))

fn ! dropTmp! tmp: String -> Unit
  (if (fileExists? tmp) (mt (pathRemove tmp) ((ok _) ()) ((err _) ())) ())

fn ! store! key: String v: Verdict -> (Result Unit String)
  (let [(dir (cacheDir!))
        (tmp (str (entryPath dir key) ".tmp." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))]
    (mt (dirCreate dir)
      ((err e) (err (str "cannot create " dir ": " e)))
      ((ok _) (mt (fileWrite tmp (encodeVerdict key v))
        ((err _) (do (dropTmp! tmp) (err (str "cannot write " tmp))))
        ((ok _) (mt (pathRename tmp (entryPath dir key))
          ((err e) (do (dropTmp! tmp) (err (str "cannot rename " tmp ": " e))))
          ((ok _) (ok ()))))))))

fn ! replay! v: Verdict -> (Result Int64 String)
  (do (if (stringEmpty? v.body) ()
        (do (eprintln (optionOr (stringSlice v.body 0 (- (stringLength v.body) (if (stringEndsWith? v.body "\n") 1 0))) v.body)) ()))
      (ok v.exitCode))
