(module aslGateway/tests/fixtures/launch/launchFixture
  :x [fixtureFamily main]
  :i [(aslGateway/server :a srv) (aslGateway/dispatch :a dp) (aslGateway/plugin :a p) (aslGateway/upstream :a u) (asl-parser/reader :a rd)])

fn fixtureFamily -> dp/LifecycleFamily
  (dp/LifecycleFamily :name "fixture"
    :make (fn [(props (Map String rd/SExpr)) (row u/UpstreamProvider) (st u/UpstreamSettings) (env (Map String String))] -> (Result dp/LifecycleSpec String)
            (ok (dp/LifecycleSpec
                  :lifecycle (p/Lifecycle
                               :deploy (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (err "fixture does not deploy"))
                               :start (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (ok (p/LifecycleStatus :endpoint r.endpoint :state (p/warming) :detail "")))
                               :stop (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (ok (p/LifecycleStatus :endpoint r.endpoint :state (p/down) :detail "")))
                               :status (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (ok (p/LifecycleStatus :endpoint r.endpoint :state (p/warm) :detail ""))))
                  :scale (p/serverless 60 5000) :startCost 500 :unit "start"))))

fn ! main args: (List String) -> (Result Int64 String)
  (srv/mainWith args "asl/packages/asl-gateway/tests/fixtures/launch/launchFixture.asl" (list (fixtureFamily)))
