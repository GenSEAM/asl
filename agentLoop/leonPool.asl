(module asl/agentLoop/leonPool
  :x [Live Book leonOpen! leonTurn! leonExit]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/sessionPool :a sp) (asl/agentLoop/runLoop :a rl)
      (asl/agentLoop/loopState :a ls) (asl/agentLoop/providers :a pv) (asl/agentLoop/retry :a rt)])

; (:m :ref SE3-POOL-DRIVER :do "one Leon run per session id, driven by sessionPool: the pool's turn function is leonTurn! over a book of live runs, so many runs share one process and none blocks while a model call is in flight. A turn ends at the hub post (askHub: the pool sends it and wakes the run with the raw reply) or at the end of the run (the receipt is the session's result); script, replay and CLI providers answer at once and the run goes on inside the same call. A run reads the same journal as liveTurn! gives, because setup, head, ask, apply and finish are the very functions the blocking path composes; what the pool path does not do yet is route, provider retry, and the parent watcher")
(schema Live
  (:f sess m/LiveSession)
  (:f wrapped rl/ProviderRun)
  (:f ask (Option m/LiveAsk))
  (:f provider pv/Provider)
  (:f exit Int64)
  (:f retries Int64)
  (:f left (Option Int64))
  (:f askedAt Float64))

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

; (:m :ref SE3-POOL-DRIVER :do "start a run: the invocation form goes through the CLI check chain (syntax, keys, bounds, root, wall), then is set up as the blocking path sets it up (journal, provider, system prompt, loop env, baseline); a rejected or early-finished run comes back as its result and is never submitted, a ready one is added to the book and the caller submits its id to the pool. resume and dryRun are the CLI's, not the pool's")
fn ! leonOpen! book: (List (Pair String Live)) id: String form: String repoRoot: String rootDir: String env: pv/ProviderEnv -> (Pair (List (Pair String Live)) (Option m/MainResult))
  (match (m/checkInvocation (m/parseInvocation form rootDir) repoRoot rootDir)
    ((m/invalid r) (pair book (some r)))
    ((m/valid c)
      (if (or (m/paramHas c.ps "resume") (m/paramHas c.ps "dryRun"))
        (pair book (some (reject "ERR_POOL_MODE" "resume and dryRun are not supported by the pool driver")))
        (match (m/liveSetup! (m/runArgsOf c.ps c.timeout c.queueTimeout c.plan) c.repoRoot c.rootDir env)
          ((m/prepRejected r) (pair book (some r)))
          ((m/prepared sess)
            (match (rl/loopOpen! sess.env sess.turnProvider sess.ra.parentPid)
              ((rl/openDone result) (pair book (some (m/liveResult sess result))))
              ((rl/openRun wrapped) (pair (bookPut book id (Live :sess sess :wrapped wrapped :ask none :provider sess.turnProvider :exit -1 :retries 0 :left none :askedAt 0.0)) none))))))))

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
      (decide! book id live ask t 0)))

fn budgetOpen left: (Option Int64) -> Bool
  (match left ((some n) (> n 0)) ((none) true))

; (:m :ref HUB-RETRY-POOL :do "a hub 429 or 503 carrying Retry-After N holds the run at least N seconds (capped by the wall left) as the same Turn.holdMs the backoff uses, so the pool thread never sleeps for it")
; (:m :ref SE3F-POOL-PARITY :do "provider retry as retryTurn! decides it, from the same functions: a transient error is retried up to 3 times under the wall budget with the pause list 1 2 4; the retried call is issued at once and a hub request carries the pause as its hold, so the pool waits without blocking; a provider that answers in the call (script, replay, CLI) pauses after the retried call instead of before it, which changes timing only. The retry rows go to the journal before the apply, as liveTurn! writes them")
fn ! decide! book: (List (Pair String Live)) id: String live: Live ask: m/LiveAsk t: pv/Turn pause: Int64 -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(sess live.sess)
        (slept (if (> pause 0) (sess.env.sleep pause) true))]
    (match t.reply
      ((ok _) (settled! book id live ask t))
      ((err error)
        (let [(spent (rt/chargeSeconds (- (sess.env.now) live.askedAt)))
              (afterCall (match live.left ((some n) (some (max 0 (- n spent)))) ((none) none)))
              (transient (rt/errorTransient (pv/errorCode error) (pv/errorMessage error)))
              (backoff (rt/providerRetryPause transient (+ live.retries 1) (list 1 2 4) afterCall))
              (hinted (pv/retryAfterSec (pv/errorMessage error)))
              (wait (max backoff (min hinted (match afterCall ((some n) n) ((none) hinted)))))]
          (if (and (< live.retries 3) (and transient (budgetOpen afterCall)))
            (callAsk! book id live live.wrapped ask t.provider (+ live.retries 1) (match afterCall ((some n) (some (max 0 (- n wait)))) ((none) none)) wait)
            (settled! book id live ask t))))))

fn ! settled! book: (List (Pair String Live)) id: String live: Live ask: m/LiveAsk t: pv/Turn -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(sess live.sess)
        (logged (m/appendRetryLines! sess.path live.wrapped.run.state.turn live.retries))]
    (appliedTo! book id (with live :ask none) (m/liveApply! sess.ra sess.repoRoot sess.rootDir sess.path sess.env live.wrapped ask t live.retries)))

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
    (cond
      ((m/parentGone? sess.ra.parentPid)
        (appliedTo! book id live (m/liveGone! sess.ra sess.path headed)))
      ((some? sess.ra.route)
        (appliedTo! book id live (m/liveTurn! sess.ra sess.repoRoot sess.rootDir sess.path sess.system sess.env sess.providerCall headed)))
      (else
        (let [(state headed.run.state)
              (left (match sess.env.wallBudget
                      ((some w) (some (max 0 (- w (optionOr (float64ToInt64 (- (sess.env.now) state.runStarted)) 0)))))
                      ((none) none)))]
          (callAsk! book id live headed (m/liveAsk! sess.ra sess.repoRoot sess.rootDir sess.path sess.system sess.env headed) headed.provider 0 left 0)))))

; (:m :ref SE3F-POOL-PARITY :do "a routed run takes its whole model call through liveTurn! (route, gates and retry as the blocking path does them), so it blocks the pool for that call; every other run is asked here")
fn ! callAsk! book: (List (Pair String Live)) id: String live: Live headed: rl/ProviderRun ask: m/LiveAsk prov: pv/Provider retries: Int64 left: (Option Int64) pause: Int64 -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(sess live.sess)
        (state headed.run.state)
        (wall (m/wallLeft sess.env.wallBudget (- (sess.env.now) state.runStarted)))
        (next (with live :wrapped headed :ask (some ask) :provider prov :retries retries :left left :askedAt (sess.env.now)))]
    (match (pv/nextTurnAsk! (m/attractorProvider prov ask.prefill wall) ask.sysA ask.user)
      ((pv/askDone t) (decide! book id next ask t pause))
      ((pv/askHub p call)
        (pair (bookPut book id (with next :provider p))
              (sp/Turn :state id :request (some call.body) :exec none :result none :headers call.headers :holdMs (* 1000 pause))))))

fn ! endRun! book: (List (Pair String Live)) id: String live: Live finished: rl/ProviderRun -> (Pair (List (Pair String Live)) sp/Turn)
  (let [(res (m/liveResult live.sess (rl/loopFinish! live.sess.env finished)))]
    (pair (bookPut book id (with live :wrapped finished :ask none :exit res.exitCode)) (resultTurn id res.stdout)))
