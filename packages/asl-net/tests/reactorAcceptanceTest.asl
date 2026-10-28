(module asl-net/tests/reactorAcceptanceTest
  :x [runTests RunTests testReactorRegistrationAndPolling testDescriptorCleanup testDualPolarityRefutations]
  :i [(asl-net/reactor :a r)])

fn ! testReactorRegistrationAndPolling -> Bool
  (match (tcpListen 0)
    ((err e) (do (assert false (str "tcpListen: " e)) false))
    ((ok lfd)
      (let [(reactor0 (r/makeReactor 128))
            (res1 (r/reactorRegister reactor0 lfd (r/EVENT_READ) "http-listener"))
            (reactor1 (match res1 ((ok x) x) ((err _) reactor0)))
            (quiet (r/reactorPoll reactor1 0))
            (client (tcpConnect (resultOr (sockLocalPort lfd) 0)))
            (busy (r/reactorPoll reactor1 1000))
            (events (match busy ((ok p) (pairSecond p)) ((err _) (list))))
            (evt (optionOr (listHead events) (r/ReactorEvent :fd 0 :readyMask 0 :tag "")))
            (_c (match client ((ok c) (fdClose c)) ((err e) (err e))))
            (_l (fdClose lfd))]
        (do
          (assert (ok? res1) "reactorRegister returns ok for the listener descriptor")
          (refute (err? res1) "reactorRegister refutes error for a valid descriptor")
          (assert (= (r/reactorActiveCount reactor1) 1) "reactor active count is 1")
          (refute (!= (r/reactorActiveCount reactor1) 1) "reactor active count refutes non-1")
          (assert (= (match quiet ((ok p) (listLength (pairSecond p))) ((err _) -1)) 0) "reactorPoll dispatches no event while no connection is pending")
          (assert (ok? client) "a client connects to the registered listener")
          (assert (ok? busy) "reactorPoll after the connect succeeds")
          (assert (= (listLength events) 1) "reactorPoll dispatches 1 event for the pending connection")
          (refute (listEmpty? events) "reactorPoll event list refutes empty")
          (assert (= evt.fd lfd) "event fd matches the registered listener")
          (refute (!= evt.fd lfd) "event fd refutes divergence")
          (assert (= evt.readyMask (r/EVENT_READ)) "event readyMask is the kernel's EVENT_READ")
          (refute (!= evt.readyMask (r/EVENT_READ)) "event readyMask refutes divergence")
          (assert (= evt.tag "http-listener") "event carries the registration tag")
          true))))

fn testDescriptorCleanup -> Bool
  (let [(reactor0 (r/makeReactor 64))
        (r1Res (r/reactorRegister reactor0 25 (r/EVENT_WRITE) "client-writer"))
        (r1 (match r1Res ((ok r) r) ((err _) reactor0)))
        (r2Res (r/reactorUnregister r1 25))]
    (assert (ok? r2Res) "reactorUnregister succeeds for registered descriptor")
    (refute (err? r2Res) "reactorUnregister refutes error for registered descriptor")
    (match r2Res
      ((ok r2)
        (assert (= (r/reactorActiveCount r2) 0) "active count is 0 after unregister")
        (refute (!= (r/reactorActiveCount r2) 0) "active count refutes non-zero after unregister"))
      ((err _)
        (assert false "unexpected unregister error")
        (refute true "unexpected unregister error"))))
  true

fn testDualPolarityRefutations -> Bool
  (let [(reactor (r/makeReactor 32))
        (unregNonExistent (r/reactorUnregister reactor 88))]
    (assert (err? unregNonExistent) "unregistering unregistered descriptor fails")
    (refute (ok? unregNonExistent) "unregistering unregistered descriptor refutes ok"))
  (let [(reactor (r/makeReactor 32))
        (reg1 (r/reactorRegister reactor 44 (r/EVENT_READ) "tag1"))
        (r1 (match reg1 ((ok r) r) ((err _) reactor)))
        (dupReg (r/reactorRegister r1 44 (r/EVENT_WRITE) "tag2"))]
    (assert (err? dupReg) "duplicate registration on same descriptor fails")
    (refute (ok? dupReg) "duplicate registration refutes ok"))
  true

fn ! runTests -> Bool
  (do
    (assert (testReactorRegistrationAndPolling) "testReactorRegistrationAndPolling passed")
    (assert (testDescriptorCleanup) "testDescriptorCleanup passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn ! RunTests -> Bool
  (runTests)
