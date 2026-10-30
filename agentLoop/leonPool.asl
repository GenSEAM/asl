(module asl/agentLoop/leonPool
  :x [Live Book leonOpen! leonTurn! leonExit]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/sessionPool :a sp) (asl/agentLoop/runLoop :a rl)
      (asl/agentLoop/loopState :a ls) (asl/agentLoop/providers :a pv)])

; (:m :ref SE3-POOL-DRIVER :do "one Leon run per session id, driven by sessionPool: the pool's turn function is leonTurn! over a book of live runs, so many runs share one process and none blocks while a model call is in flight. A turn ends at the hub post (askHub: the pool sends it and wakes the run with the raw reply) or at the end of the run (the receipt is the session's result); script, replay and CLI providers answer at once and the run goes on inside the same call. A run reads the same journal as liveTurn! gives, because setup, head, ask, apply and finish are the very functions the blocking path composes; what the pool path does not do yet is route, provider retry, and the parent watcher")
(schema Live
  (:f sess m/LiveSession)
  (:f wrapped rl/ProviderRun)
  (:f ask (Option m/LiveAsk))
  (:f provider pv/Provider)
  (:f exit Int64))

fn bookGet book: (List (Pair String Live)) id: String -> (Option Live)
  (optionMap (fn [(e (Pair String Live))] -> Live (pairSecond e)) (listFind (fn [(e (Pair String Live))] -> Bool (= (pairFirst e) id)) book))

fn bookPut book: (List (Pair String Live)) id: String live: Live -> (List (Pair String Live))
  (listAppend (filter (fn [(e (Pair String Live))] -> Bool (!= (pairFirst e) id)) book) (list (pair id live)))

fn leonExit book: (List (Pair String Live)) id: String -> Int64
  (match (bookGet book id)
    ((some l) l.exit)
    ((none) -1))

fn resultTurn id: String text: String -> sp/Turn
  (sp/Turn :state id :request none :exec none :result (some text))

fn reject code: String text: String -> m/MainResult
  (m/MainResult :stdout (str "(:result :status :rejected :error " code " :message \"" (asnQuote text) "\")") :exitCode 2)

fn asnQuote text: String -> String
  (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"")

; (:m :ref SE3-POOL-DRIVER :do "start a run: the invocation form is parsed and set up exactly as the blocking path does (journal, provider, system prompt, loop env, baseline); a rejected or early-finished run comes back as its result and is never submitted, a ready one is added to the book and the caller submits its id to the pool. The check chain of the CLI (bounds, root, ownership of keys) is not applied here yet")
fn ! leonOpen! book: (List (Pair String Live)) id: String form: String repoRoot: String rootDir: String env: pv/ProviderEnv -> (Pair (List (Pair String Live)) (Option m/MainResult))
  (let [(inv (m/parseInvocation form rootDir))]
    (if (some? inv.syntaxError)
      (pair book (some (reject "ERR_SYNTAX" (optionOr inv.syntaxError ""))))
      (match (m/liveSetup! (m/runArgsOf inv.params 600 1200 false) repoRoot rootDir env)
        ((m/prepRejected r) (pair book (some r)))
        ((m/prepared sess)
          (if (some? sess.ra.route)
            (pair book (some (reject "ERR_POOL_ROUTE" "a routed run is not supported by the pool driver yet")))
            (match (rl/loopOpen! sess.env sess.turnProvider sess.ra.parentPid)
              ((rl/openDone result) (pair book (some (m/liveResult sess result))))
              ((rl/openRun wrapped) (pair (bookPut book id (Live :sess sess :wrapped wrapped :ask none :provider sess.turnProvider :exit -1)) none))))))))

; (:m :ref SE3-POOL-DRIVER :do "the pool's turn function: state is the session id; a reply of '' starts or continues the run, any other text is the raw hub response to the ask this run left outstanding (a 503 keeps the ask and waits)")
fn ! leonTurn! book: (List (Pair String Live)) id: String raw: String -> (Pair (List (Pair String Live)) sp/Turn)
  (match (bookGet book id)
    ((none) (pair book (resultTurn id "(:err \"no such session\")")))
    ((some live)
      (match live.ask
        ((none) (headOn! book id live live.wrapped))
        ((some ask) (replyTo! book id live ask raw)))))

fn ! replyTo! book: (List (Pair String Live)) id: String live: Live ask: m/LiveAsk raw: String -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(t (pv/nextTurnReply live.provider raw))]
    (if (pv/hubBusy? t)
      (pair book (sp/Turn :state id :request none :exec none :result none :busy true))
      (appliedTo! book id (with live :ask none) (m/liveApply! live.sess.ra live.sess.repoRoot live.sess.rootDir live.sess.path live.sess.env live.wrapped ask t 0))))

fn ! appliedTo! book: (List (Pair String Live)) id: String live: Live applied: (Pair rl/ProviderRun ls/Step) -> (Pair (List (Pair String Live)) sp/Turn)
  (match (pairSecond applied)
    ((stop) (endRun! book id live (pairFirst applied)))
    ((nextTurn) (headOn! book id live (pairFirst applied)))
    ((proceed) (headOn! book id live (pairFirst applied))))

; (:m :ref SE3-POOL-DRIVER :do "head of the next turn, as runBodyWithProvider! takes it: proceed asks the model, nextTurn and stop end the run")
fn ! headOn! book: (List (Pair String Live)) id: String live: Live wrapped: rl/ProviderRun -> (Pair (List (Pair String Live)) sp/Turn)
  (match (rl/loopHead! live.sess.env wrapped)
    ((pair headed step)
      (match step
        ((proceed) (bodyOn! book id live headed))
        ((nextTurn) (endRun! book id live headed))
        ((stop) (endRun! book id live headed)))))

fn ! bodyOn! book: (List (Pair String Live)) id: String live: Live headed: rl/ProviderRun -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(sess live.sess)]
    (if (m/parentGone? sess.ra.parentPid)
      (appliedTo! book id live (m/liveGone! sess.ra sess.path headed))
      (askOn! book id live headed (m/liveAsk! sess.ra sess.repoRoot sess.rootDir sess.path sess.system sess.env headed))))

fn ! askOn! book: (List (Pair String Live)) id: String live: Live headed: rl/ProviderRun ask: m/LiveAsk -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(sess live.sess)
        (state headed.run.state)
        (wall (m/wallLeft sess.env.wallBudget (- (sess.env.now) state.runStarted)))]
    (match (pv/nextTurnAsk! (m/attractorProvider headed.provider ask.prefill wall) ask.sysA ask.user)
      ((pv/askDone t) (appliedTo! book id live (m/liveApply! sess.ra sess.repoRoot sess.rootDir sess.path sess.env headed ask t 0)))
      ((pv/askHub p call)
        (pair (bookPut book id (with live :wrapped headed :ask (some ask) :provider p))
              (sp/Turn :state id :request (some call.body) :exec none :result none :headers call.headers)))))

fn ! endRun! book: (List (Pair String Live)) id: String live: Live finished: rl/ProviderRun -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(res (m/liveResult live.sess (rl/loopFinish! live.sess.env finished)))]
    (pair (bookPut book id (with live :wrapped finished :ask none :exit res.exitCode)) (resultTurn id res.stdout)))
