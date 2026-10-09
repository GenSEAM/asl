(module asl-syntax/tests/asl/corpusCache
  :x [Cache
      cacheDisabled
      cacheAt
      cacheFromEnv!
      defaultRoots
      fingerprintRoots!
      rootsAvailable?!
      evictStale!
      verdictKey
      entryPath
      lookupVerdict!
      storeVerdict!]
  :i [])

(schema Cache
  (:f enabled Bool)
  (:f dir String)
  (:f fingerprint String))

fn cacheDisabled -> Cache
  (Cache :enabled false :dir "" :fingerprint "")

fn cacheAt dir: String fingerprint: String -> Cache
  (Cache :enabled true :dir dir :fingerprint fingerprint)

fn defaultRoots -> (List (Pair String String))
  (list (pair "asl/prelude" "")
        (pair "asl/host/src" "")
        (pair "asl/host" "build.sh")
        (pair "asl/host/out/asl-host" "")
        (pair "asl/packages/asl-parser/src" "")
        (pair "asl/packages/asl-syntax/src" "")
        (pair "asl/packages/asl-json/src" "")
        (pair "asl/packages/asl-forms/src" "")
        (pair "asl/packages/asl-syntax/tests/asl" "corpusCache")
        (pair "asl/packages/asl-syntax/tests/asl" "layoutCorpus")
        (pair "asl/packages/asl-parser/tests" "printReparse")
        (pair "asl/packages/asl-parser/tests" "liftLower"))

fn fileLine! path: String -> String
  (mt (fileReadBytes path)
    ((ok b) (str path " " (bytesSha256 b)))
    ((err e) (str path " unreadable " e)))

fn dirLines! dir: String prefix: String recurse: Bool -> (List String)
  (mt (dirList dir)
    ((err e) (list (str dir " unlistable " e)))
    ((ok names)
     (fold (fn [(acc (List String)) (name String)] -> (List String)
             (let [(child (str dir "/" name))]
               (mt (fileStat child)
                 ((err e) (listAppend acc (list (str child " unstatable " e))))
                 ((ok st)
                  (if st.isDir
                    (if recurse (listAppend acc (dirLines! child prefix recurse)) acc)
                    (if (stringStartsWith? name prefix) (listAppend acc (list (fileLine! child))) acc))))))
           (list) names)))

fn rootLines! root: (Pair String String) -> (List String)
  (let [(path (pairFirst root)) (prefix (pairSecond root))]
    (mt (fileStat path)
      ((err e) (list (str path " missing " e)))
      ((ok st)
       (if st.isDir
         (dirLines! path prefix (stringEmpty? prefix))
         (list (fileLine! path))))))

fn linesDigest lines: (List String) -> String
  (bytesSha256 (stringToBytes (stringJoin lines "\n")))

fn fingerprintRoots! roots: (List (Pair String String)) -> String
  (linesDigest (fold (fn [(acc (List String)) (r (Pair String String))] -> (List String) (listAppend acc (rootLines! r))) (list) roots))

fn availableLines! roots: (List (Pair String String)) -> (Option (List String))
  (fold (fn [(acc (Option (List String))) (r (Pair String String))] -> (Option (List String))
          (mt acc
            ((none) (none))
            ((some ls)
             (if (not (ok? (fileStat (pairFirst r))))
               (none)
               (let [(rl (rootLines! r))]
                 (if (listEmpty? rl) (none) (some (listAppend ls rl))))))))
        (some (list)) roots)

fn rootsAvailable?! roots: (List (Pair String String)) -> Bool
  (some? (availableLines! roots))

fn evictAgeNs -> Int64
  (* 7 86400000000000)

fn hexDigit? k: Int64 -> Bool
  (or (and (>= k 48) (<= k 57)) (and (>= k 97) (<= k 102)))

fn fingerprintName? name: String -> Bool
  (let [(bs (stringToBytes name))]
    (and (= (bytesLength bs) 64) (listAll? (fn [(i Int64)] -> Bool (hexDigit? (bytesGet bs i))) (range 0 64))))

fn evictOne! dir: String name: String -> Bool
  (let [(child (str dir "/" name))
        (doomed (str child ".evict." (stringFromInt64 (monotonicNs))))]
    (mt (pathRename child doomed)
      ((err e) (do (print (str "corpusCache: evict rename failed for " child ": " e "\n")) false))
      ((ok _)
       (mt (pathRemove doomed)
         ((err e) (do (print (str "corpusCache: evict remove failed for " doomed ": " e "\n")) false))
         ((ok _) true)))))

fn evictStale! dir: String keep: String now: Int64 -> Int64
  (mt (fileStat dir)
    ((err _) 0)
    ((ok _)
     (mt (dirList dir)
       ((err e) (do (print (str "corpusCache: cannot list " dir ": " e "\n")) 0))
       ((ok names)
        (fold (fn [(n Int64) (name String)] -> Int64
                (if (or (= name keep) (not (fingerprintName? name)))
                  n
                  (mt (fileStat (str dir "/" name))
                    ((err _) n)
                    ((ok st)
                     (if (and st.isDir (and (> (- now st.mtimeNs) (evictAgeNs)) (evictOne! dir name)))
                       (+ n 1)
                       n)))))
              0 names)))))

fn openCache! dir: String -> Cache
  (mt (availableLines! (defaultRoots))
    ((none) (cacheDisabled))
    ((some lines)
     (let [(fp (linesDigest lines))
           (evicted (evictStale! dir fp (nowNs)))]
       (cacheAt dir fp))))

fn defaultCacheDir! -> String
  (mt (envGet "HOME")
    ((some home) (if (stringEmpty? home) ".asl/cache/corpus" (str home "/.asl/run/corpusCache")))
    ((none) ".asl/cache/corpus"))

fn cacheFromEnv! -> Cache
  (mt (envGet "ASL_CORPUS_CACHE")
    ((some v)
     (cond
       ((= v "0") (cacheDisabled))
       ((stringEmpty? v) (openCache! (defaultCacheDir!)))
       (else (openCache! v))))
    ((none) (openCache! (defaultCacheDir!))))

fn verdictKey c: Cache suite: String path: String src: String -> String
  (bytesSha256 (stringToBytes (str "corpusVerdict/1\n" suite "\n" path "\n" c.fingerprint "\n" (bytesSha256 (stringToBytes src)))))

fn entryDir c: Cache -> String
  (str c.dir "/" c.fingerprint)

fn entryPath c: Cache key: String -> String
  (str (entryDir c) "/" key)

fn entryText suite: String key: String outcome: String -> String
  (str "(:corpusVerdict :v 1 :suite \"" suite "\" :key \"" key "\" :outcome " outcome ")\n")

fn lookupVerdict! c: Cache suite: String path: String src: String outcomes: (List String) -> (Option String)
  (if (not c.enabled)
    (none)
    (let [(key (verdictKey c suite path src))]
      (mt (fileReadString (entryPath c key))
        ((err _) (none))
        ((ok text)
         (listHead (filter (fn [(o String)] -> Bool (= text (entryText suite key o))) outcomes))))))

fn writeEntry! c: Cache key: String text: String -> (Result Unit String)
  (let [(final (entryPath c key))
        (tmp (str final ".tmp." (stringFromInt64 (monotonicNs))))]
    (mt (dirCreate (entryDir c))
      ((err e) (err e))
      ((ok _)
       (mt (fileWrite tmp text)
         ((err e) (err e))
         ((ok _) (pathRename tmp final))))))

fn storeVerdict! c: Cache suite: String path: String src: String outcome: String -> Bool
  (if (not c.enabled)
    false
    (let [(key (verdictKey c suite path src))]
      (mt (writeEntry! c key (entryText suite key outcome))
        ((ok _) true)
        ((err e) (do (print (str "corpusCache: store failed for " path ": " e "\n")) false)))))
