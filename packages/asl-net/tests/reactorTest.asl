(module asl-net/tests/reactorTest
  :x [runTests RunTests! testReactorLifecycle testReactorRegistrationValidation testReactorPollingAndDispatch! testReactorReportsKernelMask! testDualPolarityRefutations]
  :i [(asl-net/reactor :a r)])

fn testReactorLifecycle -> Bool
  (let [(reactor0 (r/makeReactor 128))]
    (assert (= (r/reactorActiveCount reactor0) 0) "initial reactor has 0 active registrations")
    (refute (!= (r/reactorActiveCount reactor0) 0) "initial reactor refutes non-zero count")
    (let [(regRes (r/reactorRegister reactor0 10 (r/EVENT_READ) "listener"))]
      (assert (ok? regRes) "reactorRegister returns ok")
      (refute (err? regRes) "reactorRegister refutes error")
      (mt regRes
        ((ok reactor1)
          (assert (= (r/reactorActiveCount reactor1) 1) "reactor has 1 active registration after add")
          (refute (!= (r/reactorActiveCount reactor1) 1) "active count refutes mismatch")
          (let [(unregRes (r/reactorUnregister reactor1 10))]
            (assert (ok? unregRes) "reactorUnregister returns ok")
            (refute (err? unregRes) "reactorUnregister refutes error")
            (mt unregRes
              ((ok reactor2)
                (assert (= (r/reactorActiveCount reactor2) 0) "reactor has 0 registrations after remove")
                (refute (!= (r/reactorActiveCount reactor2) 0) "active count refutes non-zero after unregister"))
              ((err _)
                (assert false "unexpected unregister error")
                (refute true "unexpected unregister error")))))
        ((err _)
          (assert false "unexpected register error")
          (refute true "unexpected register error")))))
  true

fn testReactorRegistrationValidation -> Bool
  (let [(reactor (r/makeReactor 64))
        (badFdRes (r/reactorRegister reactor 1 (r/EVENT_READ) "low-fd"))
        (highFdRes (r/reactorRegister reactor 300 (r/EVENT_READ) "high-fd"))
        (zeroMaskRes (r/reactorRegister reactor 12 0 "zero-mask"))]
    (assert (err? badFdRes) "bad low fd (<3) is rejected")
    (refute (ok? badFdRes) "bad low fd refutes ok")
    (assert (err? highFdRes) "bad high fd (>256) is rejected")
    (refute (ok? highFdRes) "bad high fd refutes ok")
    (assert (err? zeroMaskRes) "zero interest mask is rejected")
    (refute (ok? zeroMaskRes) "zero interest mask refutes ok"))
  true

fn ! testReactorPollingAndDispatch! -> Bool
  (mt (tcpListen 0)
    ((err e) (do (assert false (str "tcpListen: " e)) false))
    ((ok lfd)
      (let [(port (resultOr (sockLocalPort lfd) 0))
            (reactor1 (mt (r/reactorRegister (r/makeReactor 256) lfd (r/EVENT_READ) "listener") ((ok x) x) ((err _) (r/makeReactor 256))))
            (quiet (r/reactorPoll reactor1 0))
            (client (tcpConnect port))
            (busy (r/reactorPoll reactor1 1000))
            (step (r/reactorNextEvent! (mt busy ((ok p) (pairFirst p)) ((err _) reactor1))))
            (_a (mt (sockAccept lfd) ((ok c) (fdClose c)) ((err e) (err e))))
            (_c (mt client ((ok c) (fdClose c)) ((err e) (err e))))
            (badTimeout (r/reactorPoll reactor1 -1))
            (_l (fdClose lfd))]
        (do
          (assert (= (r/reactorActiveCount reactor1) 1) "the real listener is registered")
          (assert (= (mt quiet ((ok p) (listLength (pairSecond p))) ((err _) -1)) 0) "a listener with no pending connection yields no event")
          (assert (ok? client) "the client connects to the registered listener")
          (assert (= (mt busy ((ok p) (listLength (pairSecond p))) ((err _) -1)) 1) "a pending connection yields one event")
          (assert (mt busy ((ok p) (mt (listHead (pairSecond p)) ((some e) (and (= e.fd lfd) (and (= e.readyMask (r/EVENT_READ)) (= e.tag "listener")))) ((none) false))) ((err _) false)) "the event names the listener fd, EVENT_READ and the registration tag")
          (assert (mt step ((ok p) (mt (pairSecond p) ((some e) (= e.fd lfd)) ((none) false))) ((err _) false)) "reactorNextEvent! yields the queued listener event")
          (assert (err? badTimeout) "a negative poll timeout is rejected")
          true))))

fn ! testReactorReportsKernelMask! -> Bool
  (mt (tcpListen 0)
    ((err e) (do (assert false (str "tcpListen: " e)) false))
    ((ok lfd)
      (let [(client (tcpConnect (resultOr (sockLocalPort lfd) 0)))
            (conn (sockAccept lfd))
            (connFd (resultOr conn -1))
            (reactor1 (mt (r/reactorRegister (r/makeReactor 256) lfd (r/EVENT_READ) "listener") ((ok x) x) ((err _) (r/makeReactor 256))))
            (reactor2 (mt (r/reactorRegister reactor1 connFd (+ (r/EVENT_READ) (r/EVENT_WRITE)) "conn") ((ok x) x) ((err _) reactor1)))
            (polled (r/reactorPoll reactor2 1000))
            (events (mt polled ((ok p) (pairSecond p)) ((err _) (list))))
            (_n (mt conn ((ok c) (fdClose c)) ((err e) (err e))))
            (_c (mt client ((ok c) (fdClose c)) ((err e) (err e))))
            (_l (fdClose lfd))]
        (do
          (assert (ok? client) "the client connects to the listener")
          (assert (ok? conn) "the listener accepts the client")
          (assert (= (r/reactorActiveCount reactor2) 2) "the listener and the accepted socket are registered")
          (assert (ok? polled) "reactorPoll over both registrations succeeds")
          (assert (= (listLength events) 1) (str "only the ready registration yields an event, got " (stringFromInt64 (listLength events))))
          (assert (mt (listHead events) ((some e) (and (= e.fd connFd) (= e.tag "conn"))) ((none) false)) "the event names the accepted socket, not the idle listener")
          (assert (mt (listHead events) ((some e) (= e.readyMask (r/EVENT_WRITE))) ((none) false)) "the event mask is the kernel's EVENT_WRITE, not the registered interest")
          true))))

fn testReactorPollErrorPropagation! -> Bool
  (let [(server (r/Server :listenerFd 0 :nextConnId 1 :connections (list) :procs (list) :config (r/makeServerConfig)))
        (result (r/reactorStep! server -2))]
    (assert (err? result) "reactorStep propagates fdPoll errors"))
  true

fn testHttpClose! -> Bool
  (mt (tcpListen 0)
    ((err e) (do (assert false (str "tcpListen failed: " e)) false))
    ((ok sock)
      (let [(conn (r/Connection :fd sock :connId 1 :buffer "bad request" :lastActivityNs 0 :chunkedMode false))
            (server (r/Server :listenerFd -1 :nextConnId 2 :connections (list conn) :procs (list) :config (r/makeServerConfig)))
            (result (r/httpClose! server 1))
            (closedServer (mt result ((ok s) s) ((err _) server)))]
        (assert (ok? result) "httpClose closes the connection fd")
        (assert (err? (fdClose sock)) "httpClose closed the connection's own socket")
        (assert (= (r/serverConnCount closedServer) 0) "httpClose removes the connection")
        true)))

fn testDualPolarityRefutations -> Bool
  (let [(reactor (r/makeReactor 16))
        (unregNonExistent (r/reactorUnregister reactor 99))]
    (assert (err? unregNonExistent) "unregistering unregistered fd returns err")
    (refute (ok? unregNonExistent) "unregistering unregistered fd refutes ok"))
  (let [(reactor (r/makeReactor 16))
        (reg1 (r/reactorRegister reactor 50 (r/EVENT_READ) "tag1"))
        (r1 (mt reg1 ((ok r) r) ((err _) reactor)))
        (dupReg (r/reactorRegister r1 50 (r/EVENT_WRITE) "tag2"))]
    (assert (err? dupReg) "duplicate fd registration is rejected")
    (refute (ok? dupReg) "duplicate fd registration refutes ok"))
  true

fn ! testReactorDeadlineCaps! -> Bool
  (let [(now (monotonicNs))
        (procs (list (r/ProcEntry :handle 999999 :stdoutFd -1 :stderrFd -1 :stdout "" :stderr "" :deadlineNs (+ now 100000000))))
        (finite (r/reactorPollTimeoutMs procs now 5000))
        (infinite (r/reactorPollTimeoutMs procs now -1))
        (due (r/reactorPollTimeoutMs (list (r/ProcEntry :handle 999999 :stdoutFd -1 :stderrFd -1 :stdout "" :stderr "" :deadlineNs (- now 1))) now 5000))
        (noDeadline (r/reactorPollTimeoutMs (list (r/ProcEntry :handle 999999 :stdoutFd -1 :stderrFd -1 :stdout "" :stderr "" :deadlineNs 0)) now 5000))]
    (do
      (assert (and (> finite 0) (<= finite 100)) (str "a 100 ms proc deadline caps a 5000 ms poll: " (stringFromInt64 finite)))
      (assert (and (> infinite 0) (<= infinite 100)) (str "a proc deadline replaces an unbounded poll: " (stringFromInt64 infinite)))
      (assert (= due 0) "a passed deadline polls without waiting")
      (assert (= noDeadline 5000) "a proc without a deadline leaves the requested poll")
      (assert (= (r/reactorPollTimeoutMs (list) now -1) -1) "no process deadline preserves infinite poll")
      true))

fn ! runTests -> Bool
  (do
    (assert (testReactorLifecycle) "testReactorLifecycle passed")
    (assert (testReactorRegistrationValidation) "testReactorRegistrationValidation passed")
    (assert (testReactorPollingAndDispatch!) "testReactorPollingAndDispatch passed")
    (assert (testReactorReportsKernelMask!) "testReactorReportsKernelMask passed")
    (assert (testReactorPollErrorPropagation!) "testReactorPollErrorPropagation passed")
    (let [(stdinBefore (ok? (fileStat "/dev/fd/0")))]
      (do (assert (testHttpClose!) "testHttpClose passed")
          (assert (= (ok? (fileStat "/dev/fd/0")) stdinBefore) "testHttpClose leaves the test process stdin as it found it")))
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    (assert (testReactorDeadlineCaps!) "process deadline caps reactor waits")
    true)

fn RunTests! -> Bool
  (runTests)
