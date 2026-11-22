(module asl-cli/tests/fixtures/objStoreRace
  :x [main]
  :i [(asl/packages/asl-cli/src/objStore :a os)])

; (:m :ref BUILD-CACHE :do "one process of the object store race: a writer runs the part protocol of linkCached! (partState!, then installObj! of a miss) over shared keys, an observer checks that no object is ever visible without its meta row; buildCacheTest starts two writers and one observer on one temp store")
(schema Tally
  (:f hits Int64)
  (:f installed Int64)
  (:f corrupt Int64)
  (:f lost Int64)
  (:f failed Int64))

fn keyOf r: Int64 i: Int64 -> String
  (str "k" (stringFromInt64 r) "x" (stringFromInt64 i))

fn indexAt down: Bool n: Int64 j: Int64 -> Int64
  (if down (- (- n 1) j) j)

fn ! step! objs: String key: String t: Tally -> Tally
  (let [(st (os/partState! objs key))]
    (cond
      ((= st 0) (if (fileExists? (os/objPath objs key))
                  (Tally :hits (+ t.hits 1) :installed t.installed :corrupt t.corrupt :lost t.lost :failed t.failed)
                  (Tally :hits t.hits :installed t.installed :corrupt t.corrupt :lost (+ t.lost 1) :failed t.failed)))
      (else (let [(tmp (os/objTmpPath objs key (procSelf)))
                  (wrote (fileWrite tmp (str "object " key "\n" (stringRepeat "o" 512))))
                  (done (if (ok? wrote) (os/installObj! objs key tmp) (err "tmp write failed")))
                  (bad (if (= st 2) 1 0))]
              (if (ok? done)
                (Tally :hits t.hits :installed (+ t.installed 1) :corrupt (+ t.corrupt bad) :lost t.lost :failed t.failed)
                (Tally :hits t.hits :installed t.installed :corrupt (+ t.corrupt bad) :lost t.lost :failed (+ t.failed 1)))))))

fn ! writer! objs: String rounds: Int64 n: Int64 down: Bool -> Tally
  (fold (fn [(t Tally) (r Int64)] -> Tally
          (fold (fn [(u Tally) (j Int64)] -> Tally (step! objs (keyOf r (indexAt down n j)) u)) t (range 0 n)))
        (Tally :hits 0 :installed 0 :corrupt 0 :lost 0 :failed 0) (range 0 rounds))

fn ! doneCount store: String -> Int64
  (listLength (filter (fn [(f String)] -> Bool (stringStartsWith? f "done.")) (resultOr (dirList store) (list))))

fn ! observe! store: String objs: String rounds: Int64 n: Int64 writers: Int64 deadline: Int64 checks: Int64 seen: Int64 -> (Pair Int64 Int64)
  (if (or (>= (doneCount store) writers) (> (monotonicNs) deadline))
    (pair checks seen)
    (let [(found (fold (fn [(acc Int64) (k Int64)] -> Int64
                         (let [(key (keyOf (/ k n) (mod k n)))]
                           (if (and (fileExists? (os/objPath objs key)) (not (fileExists? (os/metaPath objs key)))) (+ acc 1) acc)))
                       0 (range 0 (* rounds n))))]
      (observe! store objs rounds n writers deadline (+ checks (* rounds n)) (+ seen found))))

fn ! arg args: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (listGet args i) "")) 0)

fn ! main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listGet args 0) ""))
        (store (optionOr (listGet args 1) ""))
        (objs (str store "/obj"))
        (rounds (arg args 2))
        (n (arg args 3))]
    (cond
      ((or (stringEmpty? store) (or (<= rounds 0) (<= n 0))) (err "usage: objStoreRace writer|observer STORE ROUNDS N TAG|WRITERS"))
      ((= mode "writer")
        (let [(tag (optionOr (listGet args 4) "0"))
              (t (writer! objs rounds n (= tag "1")))
              (_ (fileWrite (str store "/done." tag) "1\n"))]
          (do (println (str "(:writer :tag " tag " :hits " (stringFromInt64 t.hits) " :installed " (stringFromInt64 t.installed) " :corrupt " (stringFromInt64 t.corrupt)
                            " :lost " (stringFromInt64 t.lost) " :failed " (stringFromInt64 t.failed) ")"))
              (ok 0))))
      ((= mode "observer")
        (let [(r (observe! store objs rounds n (arg args 4) (+ (monotonicNs) 90000000000) 0 0))]
          (do (println (str "(:observer :checks " (stringFromInt64 (pairFirst r)) " :violations " (stringFromInt64 (pairSecond r)) ")"))
              (ok 0))))
      (else (err (str "unknown mode " mode)))))
