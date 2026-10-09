(module aslCrawler/session
  :x [ServicePreset SessionState makeServicePreset getServicePreset makeSessionState formatSessionAsn isSessionValid? BrowserSessionHandle makeBrowserSessionHandle formatBrowserSessionHandleAsn]
  :i [(asl-text/escape :a esc)])

(schema ServicePreset
  (:f serviceName Str)
  (:f loginUrl Str)
  (:f domain Str)
  (:f sessionCookieNames (List Str))
  (:f checkSelector Str))

(schema SessionState
  (:f service Str)
  (:f isAuthenticated Bool)
  (:f cookiesCount I64)
  (:f lastVerifiedEpoch I64))

fn makeServicePreset name: Str url: Str domain: Str cookies: (List Str) sel: Str -> ServicePreset
  (ServicePreset :serviceName name :loginUrl url :domain domain :sessionCookieNames cookies :checkSelector sel)

fn getServicePreset service: Str -> ServicePreset
  (let [(clean (stringLower (stringTrim service)))]
    (cond
      ((or (== clean "tiktok") (== clean "tt"))
        (ServicePreset
          :serviceName "tiktok"
          :loginUrl "https://www.tiktok.com/login"
          :domain ".tiktok.com"
          :sessionCookieNames (list "sessionid" "sid_tt" "sid_guard")
          :checkSelector "[data-e2e='profile-icon']"))
      ((or (== clean "github") (== clean "gh"))
        (ServicePreset
          :serviceName "github"
          :loginUrl "https://github.com/login"
          :domain "github.com"
          :sessionCookieNames (list "user_session" "__Host-user_session_same_site")
          :checkSelector "summary[aria-label='View profile and more']"))
      ((or (== clean "x") (== clean "twitter"))
        (ServicePreset
          :serviceName "x"
          :loginUrl "https://x.com/i/flow/login"
          :domain ".x.com"
          :sessionCookieNames (list "auth_token" "ct0")
          :checkSelector "[data-testid='AppTabBar_Profile_Link']"))
      (else
        (ServicePreset
          :serviceName "generic"
          :loginUrl ""
          :domain ""
          :sessionCookieNames (list)
          :checkSelector ""))))

fn makeSessionState service: Str isAuth: Bool count: I64 now: I64 -> SessionState
  (SessionState :service service :isAuthenticated isAuth :cookiesCount count :lastVerifiedEpoch now)

fn formatSessionAsn state: SessionState -> Str
  (str "(:sessionState"
       " :service \"" (esc/escapeAsnStr state.service) "\""
       " :authenticated " (if state.isAuthenticated "true" "false")
       " :cookiesCount " (stringFromInt64 state.cookiesCount)
       " :lastVerified " (stringFromInt64 state.lastVerifiedEpoch)
       ")")

fn isSessionValid? state: SessionState maxAgeSec: I64 nowSec: I64 -> Bool
  (and state.isAuthenticated
       (> state.cookiesCount 0)
       (<= (- nowSec state.lastVerifiedEpoch) maxAgeSec))

(schema BrowserSessionHandle
  (:f sessionId Str)
  (:f tabId Str)
  (:f mode Str)
  (:f currentUrl Str)
  (:f isActive Bool))

fn makeBrowserSessionHandle sid: Str tabId: Str mode: Str url: Str -> BrowserSessionHandle
  (BrowserSessionHandle :sessionId sid :tabId tabId :mode mode :currentUrl url :isActive true)

fn formatBrowserSessionHandleAsn h: BrowserSessionHandle -> Str
  (str "(:browserSession"
       " :sessionId \"" (esc/escapeAsnStr h.sessionId) "\""
       " :tabId \"" (esc/escapeAsnStr h.tabId) "\""
       " :mode :" h.mode
       " :url \"" (esc/escapeAsnStr h.currentUrl) "\""
       " :active " (if h.isActive "true" "false")
       ")")

