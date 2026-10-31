(module aslGateway/tests/limitFixtures
  :x [Fx fixtures nowSec]
  :i [])

; (:m :ref GW-429-BODY-SAMPLES :do "rows of limit-class responses with the answer the gateway must give: wide = the whole provider pool trips, daily = the free-tier daily-cap kind or empty, retry = the same request is retried, park = seconds a daily cap parks the model at nowSec; src captured = seen verbatim in the 2026-10-28 FREE-CAL bench logs (the gateway renders only status and the first ~500 body bytes there, so headers were not kept and a body can end mid-word), derived = a captured body with one fact changed, recalled = the vendor's documented wording written from memory, not captured on this machine")
(schema Fx
  (:f id String)
  (:f provider String)
  (:f src String)
  (:f status Int64)
  (:f headers (List (Pair String String)))
  (:f body String)
  (:f wide Bool)
  (:f daily String)
  (:f retry Bool)
  (:f park Int64))

fn nowSec -> Float64
  1700000000.0

fn fixtures -> (List Fx)
  (list
    (Fx :id "geminiDailyCaptured" :provider "gemini" :src "captured" :status 429 :headers (list) :body "Gateway HTTP error 429: Too Many Requests [{\n  \"error\": {\n    \"code\": 429,\n    \"message\": \"You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. To monitor your current usage, head to: https://ai.dev/rate-limit. \\n* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20, model: gemini-3.6-flash, description: Generate content requests per day limit exceeded on Free Tie" :wide false :daily "gemini" :retry false :park 35200)
    (Fx :id "geminiMinuteDerived" :provider "gemini" :src "derived" :status 429 :headers (list) :body "Gateway HTTP error 429: Too Many Requests [{\n  \"error\": {\n    \"code\": 429,\n    \"message\": \"You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. To monitor your current usage, head to: https://ai.dev/rate-limit. \\n* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 5, model: gemini-3.6-flash, description: Generate content requests per minute limit exceeded on Free Tie" :wide false :daily "" :retry true :park 0)
    (Fx :id "commandCodeUpstreamCaptured" :provider "commandCode" :src "captured" :status 429 :headers (list) :body "Upstream model provider is temporarily unavailable. Please try again in a moment." :wide false :daily "" :retry true :park 0)
    (Fx :id "serviceUnavailableCaptured" :provider "commandCode" :src "captured" :status 503 :headers (list) :body "Service temporarily unavailable. Please try again shortly." :wide false :daily "" :retry true :park 0)
    (Fx :id "workerLimitCaptured" :provider "ifm" :src "captured" :status 503 :headers (list) :body "ResourceExhausted: Worker local total request limit reached (16/16)" :wide false :daily "" :retry true :park 0)
    (Fx :id "groqMinuteRecalled" :provider "groq" :src "recalled" :status 429 :headers (list (pair "retry-after" "4")) :body "{\"error\":{\"message\":\"Rate limit reached for model `llama-3.3-70b-versatile` in organization `org_x` service tier `on_demand` on tokens per minute (TPM): Limit 12000, Used 11500, Requested 1200. Please try again in 3.5s. Need more tokens? Visit https://console.groq.com/settings/billing to upgrade your plan.\",\"type\":\"tokens\",\"code\":\"rate_limit_exceeded\"}}" :wide false :daily "" :retry true :park 0)
    (Fx :id "groqDailyRecalled" :provider "groq" :src "recalled" :status 429 :headers (list) :body "{\"error\":{\"message\":\"Rate limit reached for model `llama-3.3-70b-versatile` in organization `org_x` service tier `on_demand` on tokens per day (TPD): Limit 100000, Used 99800, Requested 500. Please try again in 7m12.96s. Need more tokens? Upgrade to Dev Tier today at https://console.groq.com/settings/billing\",\"type\":\"tokens\",\"code\":\"rate_limit_exceeded\"}}" :wide false :daily "groq" :retry false :park 433)
    (Fx :id "openrouterPlatformDailyRecalled" :provider "openrouter" :src "recalled" :status 429 :headers (list (pair "X-RateLimit-Reset" "1700007200000")) :body "{\"error\":{\"message\":\"Rate limit exceeded: free-models-per-day\",\"metadata\":{\"headers\":{\"X-RateLimit-Limit\":\"50\"},\"quota\":\"free_model_daily_requests\"}}}" :wide false :daily "openrouter" :retry false :park 7200)
    (Fx :id "openrouterUpstreamRecalled" :provider "openrouter" :src "recalled" :status 429 :headers (list) :body "{\"error\":{\"message\":\"Provider returned error\",\"code\":429,\"metadata\":{\"provider_name\":\"Venice\",\"raw\":\"model is temporarily rate-limited upstream\"}}}" :wide false :daily "" :retry true :park 0)
    (Fx :id "vercelRateRecalled" :provider "vercel" :src "recalled" :status 429 :headers (list (pair "retry-after" "2")) :body "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_exceeded\"}}" :wide false :daily "" :retry true :park 0)
    (Fx :id "insufficientQuotaRecalled" :provider "openai-style" :src "recalled" :status 429 :headers (list) :body "{\"error\":{\"message\":\"You exceeded your current quota, please check your plan and billing details.\",\"type\":\"insufficient_quota\",\"code\":\"insufficient_quota\"}}" :wide true :daily "" :retry false :park 0)
    (Fx :id "ollamaMonthlyCaptured" :provider "ollama" :src "captured" :status 429 :headers (list) :body "Hub HTTP error 429: Too Many Requests you (USER) have reached your monthly usage limit, upgrade for higher limits: https://ollama.com/upgrade or add usage credits: https://ollama.com/settings (ref: REF)" :wide false :daily "monthly" :retry false :park 1388800))
