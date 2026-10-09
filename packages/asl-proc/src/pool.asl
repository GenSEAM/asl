(module asl-proc/pool
  :x [PoolResult runPool!]
  :i [])

(schema PoolResult (:f index Int64) (:f argv (List String)) (:f exitCode Int64) (:f stdout String) (:f stderr String) (:f spawnError (Option String)) (:f durationMs Int64))

(schema PoolSlot (:f index Int64) (:f argv (List String)) (:f pid Int64) (:f outFd Int64) (:f errFd Int64) (:f out String) (:f errText String) (:f outOpen Bool) (:f errOpen Bool) (:f code (Option Int64)) (:f startNs Int64))

(schema PoolState (:f pending (List (Pair Int64 (List String)))) (:f running (List PoolSlot)) (:f done (List PoolResult)))

fn slotWith s: PoolSlot out: String errText: String outOpen: Bool errOpen: Bool code: (Option Int64) -> PoolSlot
  (with s :out out :errText errText :outOpen outOpen :errOpen errOpen :code code)

fn ! startJob! job: (Pair Int64 (List String)) -> (Result PoolSlot PoolResult)
  (let [(idx (pairFirst job)) (argv (pairSecond job)) (t0 (monotonicNs))]
    (mt (procSpawnv argv (none) (none))
      ((err e) (err (PoolResult :index idx :argv argv :exitCode -1 :stdout "" :stderr "" :spawnError (some e) :durationMs 0)))
      ((ok sp)
        (mt (fdClose sp.stdin)
          ((err e) (do (procKill (- 0 sp.pid) "SIGKILL") (procWaitPid sp.pid false) (fdClose sp.stdout) (fdClose sp.stderr) (err (PoolResult :index idx :argv argv :exitCode -1 :stdout "" :stderr "" :spawnError (some e) :durationMs 0))))
          ((ok _) (ok (PoolSlot :index idx :argv argv :pid sp.pid :outFd sp.stdout :errFd sp.stderr :out "" :errText "" :outOpen true :errOpen true :code (none) :startNs t0)))))))

fn ! fill! k: Int64 st: PoolState -> PoolState
  (mt (listHead st.pending)
    ((none) st)
    ((some job)
      (if (>= (listLength st.running) k)
        st
        (let [(rest (optionOr (listTail st.pending) (list)))]
          (mt (startJob! job)
            ((ok slot) (fill! k (with st :pending rest :running (listAppend st.running (list slot)))))
            ((err failed) (fill! k (with st :pending rest :done (listAppend st.done (list failed))))))))))

fn watchFds slots: (List PoolSlot) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (s PoolSlot)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if s.outOpen (list (pair s.outFd 1)) (list)) (if s.errOpen (list (pair s.errFd 1)) (list)))))
        (list) slots)

fn livePids slots: (List PoolSlot) -> (List Int64)
  (map (fn [(s PoolSlot)] -> Int64 s.pid) (filter (fn [(s PoolSlot)] -> Bool (none? s.code)) slots))

fn fdReady? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn exitOf exited: (List (Pair Int64 Int64)) pid: Int64 -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (p (Pair Int64 Int64))] -> (Option Int64) (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) exited)

fn ! readSide! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((err e) (err (str "read fd " (stringFromInt64 fd) ": " e)))
    ((ok chunk)
      (if (> (stringLength chunk) 0)
        (ok (some chunk))
        (mt (fdClose fd) ((err e) (err (str "close fd " (stringFromInt64 fd) ": " e))) ((ok _) (ok (none)))))))

fn ! absorbSlot! s: PoolSlot readyFds: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) -> (Result PoolSlot String)
  (let [(outR (if (and s.outOpen (fdReady? readyFds s.outFd)) (readSide! s.outFd) (ok (some ""))))
        (errR (if (and s.errOpen (fdReady? readyFds s.errFd)) (readSide! s.errFd) (ok (some ""))))
        (code (if (some? s.code) s.code (exitOf exited s.pid)))]
    (mt outR
      ((err e) (err e))
      ((ok outChunk)
        (mt errR
          ((err e) (err e))
          ((ok errChunk)
            (ok (slotWith s (str s.out (optionOr outChunk "")) (str s.errText (optionOr errChunk "")) (and s.outOpen (some? outChunk)) (and s.errOpen (some? errChunk)) code)))))))

fn ! absorbAll! slots: (List PoolSlot) readyFds: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) acc: (List PoolSlot) -> (Result (List PoolSlot) String)
  (mt (listHead slots)
    ((none) (ok acc))
    ((some h)
      (mt (absorbSlot! h readyFds exited)
        ((err e) (err e))
        ((ok s) (absorbAll! (optionOr (listTail slots) (list)) readyFds exited (listAppend acc (list s)))))))

fn finished? s: PoolSlot -> Bool
  (and (some? s.code) (not s.outOpen) (not s.errOpen))

fn ! toResult! s: PoolSlot -> PoolResult
  (PoolResult :index s.index :argv s.argv :exitCode (optionOr s.code -1) :stdout s.out :stderr s.errText :spawnError (none) :durationMs (/ (- (monotonicNs) s.startNs) 1000000))

fn ! abandonSlot! s: PoolSlot -> Bool
  (let [(killed (if (none? s.code) (do (procKill (- 0 s.pid) "SIGKILL") (procWaitPid s.pid false)) (ok (none))))
        (outClosed (if s.outOpen (fdClose s.outFd) (ok ())))
        (errClosed (if s.errOpen (fdClose s.errFd) (ok ())))]
    (and (ok? killed) (ok? outClosed) (ok? errClosed)))

fn ! abandon! slots: (List PoolSlot) -> Bool
  (fold (fn [(acc Bool) (s PoolSlot)] -> Bool (and (abandonSlot! s) acc)) true slots)

fn ! poolLoop! k: Int64 st: PoolState -> (Result (List PoolResult) String)
  (let [(st1 (fill! k st)) (running st1.running)]
    (if (listEmpty? running)
      (ok st1.done)
      (mt (procPoll (watchFds running) (livePids running) -1)
        ((err e) (do (abandon! running) (err (str "procPoll: " e))))
        ((ok ready)
          (mt (absorbAll! running (pairFirst ready) (pairSecond ready) (list))
            ((err e) (do (abandon! running) (err e)))
            ((ok slots)
              (poolLoop! k (PoolState :pending st1.pending :running (filter (fn [(s PoolSlot)] -> Bool (not (finished? s))) slots) :done (listAppend st1.done (map toResult! (filter finished? slots)))))))))))

fn ! runPool! jobs: (List (List String)) k: Int64 -> (Result (List PoolResult) String)
  (if (< k 1)
    (err "runPool: k must be at least 1")
    (poolLoop! k (PoolState :pending (enumerate jobs) :running (list) :done (list))))
