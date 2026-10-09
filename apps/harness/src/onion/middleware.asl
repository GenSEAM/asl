(module aslHarness/onion/middleware :x [makeResidentTranslatorMiddleware makeGroundingMiddleware makeCacheMiddleware makeAuditMiddleware createHarnessPipeline] :i [(aslAgentCore/onion :a on)])

fn makeResidentTranslatorMiddleware -> on/Middleware
  (on/makeMiddleware "mw-resident-translator" "Resident ASN Translator Layer" (on/kindPreCall) 50 (list) (list))

fn makeGroundingMiddleware -> on/Middleware
  (on/makeMiddleware "mw-grounding" "Epistemic Grounding Firewall" (on/kindFilter) 200 (list) (list "mw-cache"))

fn makeCacheMiddleware -> on/Middleware
  (on/makeMiddleware "mw-cache" "Namespace Prompt Cache" (on/kindPreCall) 100 (list) (list))

fn makeAuditMiddleware -> on/Middleware
  (on/makeMiddleware "mw-audit" "Execution Audit Logger" (on/kindAudit) 500 (list) (list "mw-grounding"))

fn createHarnessPipeline -> on/OnionPipeline
  (let [(p0 (on/OnionPipeline :middlewares (list) :sorted (list))) (p1 (on/addMiddleware p0 (makeResidentTranslatorMiddleware))) (p2 (on/addMiddleware p1 (makeCacheMiddleware))) (p3 (on/addMiddleware p2 (makeGroundingMiddleware))) (p4 (on/addMiddleware p3 (makeAuditMiddleware)))] p4)
