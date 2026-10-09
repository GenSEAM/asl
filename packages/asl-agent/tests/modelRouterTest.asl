(module aslAgentTests/modelRouterTest :x [testModelRoutingByRole testModelOfflineFallback testFormatRouteDecision runTests] :i [(aslAgent/modelRouter :a router)])

fn testModelRoutingByRole -> Bool
  (let [(m (router/defaultRoutingMatrix)) (epDesign (router/resolveModelForRole (router/roleDesign) m false)) (epCoding (router/resolveModelForRole (router/roleCoding) m false)) (epReview (router/resolveModelForRole (router/roleReview) m false))] (assert (= epDesign.modelId "gemini-2.5-flash") "c-router-pos-001: design model is flash") (assert (= epCoding.modelId "gemma-4-31b-it") "c-router-pos-001: coding model is gemma") (assert (= epReview.modelId "gemini-2.5-pro") "c-router-pos-001: review model is pro") (assert (not (= epReview.modelId "unknown")) "c-router-pos-001: review model not unknown") true)

fn testModelOfflineFallback -> Bool
  (let [(m (router/defaultRoutingMatrix)) (epOffline (router/resolveModelForRole (router/roleReview) m true))] (assert epOffline.isLocal "c-router-neg-001: offline endpoint is local") (assert (not (= epOffline.modelId "gemini-2.5-pro")) "c-router-neg-001: offline not cloud pro") true)

fn testFormatRouteDecision -> Bool
  (let [(m (router/defaultRoutingMatrix)) (epReview (router/resolveModelForRole (router/roleReview) m false)) (report (router/formatRouteDecision (router/roleReview) epReview))] (assert (stringContains? report "Role [review]") "route decision contains role") (assert (not (= report "")) "route decision not empty") true)

fn runTests -> Bool
  (and (testModelRoutingByRole) (and (testModelOfflineFallback) (testFormatRouteDecision)))
