(module aslCrawler/stealth :x [StealthKind StealthProfile stealthGooglebot stealthChrome stealthSafari stealthMobile googlebotProfile chromeProfile safariProfile curlHeaders makeGooglebotProfile makeChromeProfile makeSafariProfile makeProfile buildHeaders formatCurlHeaderArgs ExtensionRelayMessage ExtensionRelayResponse formatRelayRequest parseRelayResponse] :i [])

(enum StealthKind (:c googleBot [] "GoogleBot search indexing spider") (:c chromeStealth [] "Desktop Chrome macOS/Windows stealth browser") (:c safariStealth [] "Desktop Safari macOS modern WebKit") (:c mobileSafari [] "Mobile iPhone Safari"))

(schema StealthProfile (:f kind StealthKind) (:f userAgent Str) (:f accept Str) (:f acceptLanguage Str) (:f secChUa Str) (:f secFetchDest Str) (:f secFetchMode Str) (:f secFetchSite Str))

fn stealthGooglebot -> StealthKind
  (googleBot)

fn stealthChrome -> StealthKind
  (chromeStealth)

fn stealthSafari -> StealthKind
  (safariStealth)

fn stealthMobile -> StealthKind
  (mobileSafari)

fn makeGooglebotProfile -> StealthProfile
  (StealthProfile :kind (googleBot) :userAgent "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" :accept "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" :acceptLanguage "en-US,en;q=0.5" :secChUa "" :secFetchDest "document" :secFetchMode "navigate" :secFetchSite "none")

fn makeChromeProfile -> StealthProfile
  (StealthProfile :kind (chromeStealth) :userAgent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" :accept "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" :acceptLanguage "en-US,en;q=0.9" :secChUa "\"Chromium\";v=\"128\", \"Not;A=Brand\";v=\"24\", \"Google Chrome\";v=\"128\"" :secFetchDest "document" :secFetchMode "navigate" :secFetchSite "none")

fn makeSafariProfile -> StealthProfile
  (StealthProfile :kind (safariStealth) :userAgent "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15" :accept "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" :acceptLanguage "en-US,en;q=0.9" :secChUa "" :secFetchDest "document" :secFetchMode "navigate" :secFetchSite "none")

fn makeMobileSafariProfile -> StealthProfile
  (StealthProfile :kind (mobileSafari) :userAgent "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" :accept "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" :acceptLanguage "en-US,en;q=0.9" :secChUa "" :secFetchDest "document" :secFetchMode "navigate" :secFetchSite "cross-site")

fn makeProfile kind: StealthKind -> StealthProfile
  (mt kind ((googleBot) (makeGooglebotProfile)) ((chromeStealth) (makeChromeProfile)) ((safariStealth) (makeSafariProfile)) ((mobileSafari) (makeMobileSafariProfile)))

fn buildHeaders profile: StealthProfile -> (List Str)
  (let [(base (list (str "User-Agent: " profile.userAgent) (str "Accept: " profile.accept) (str "Accept-Language: " profile.acceptLanguage) "Upgrade-Insecure-Requests: 1" (str "Sec-Fetch-Dest: " profile.secFetchDest) (str "Sec-Fetch-Mode: " profile.secFetchMode) (str "Sec-Fetch-Site: " profile.secFetchSite))) (chUa profile.secChUa)] (if (> (stringLength chUa) 0) (cons (str "Sec-CH-UA: " chUa) base) base))

fn googlebotProfile -> StealthProfile
  (makeGooglebotProfile)

fn chromeProfile -> StealthProfile
  (makeChromeProfile)

fn safariProfile -> StealthProfile
  (makeSafariProfile)

fn curlHeaders headers: (List Str) -> (List Str)
  (formatCurlHeaderArgs headers)

fn formatCurlHeaderArgs headers: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (hdr Str)] -> (List Str) (listAppend acc (list "-H" hdr))) (list) headers)

(schema ExtensionRelayMessage (:f action Str) (:f url Str) (:f method Str) (:f headers (List Str)) (:f body Str))

(schema ExtensionRelayResponse (:f statusCode I64) (:f headers (List Str)) (:f body Str) (:f success Bool))

fn formatRelayRequest url: Str method: Str headers: (List Str) body: Str -> ExtensionRelayMessage
  (ExtensionRelayMessage :action "asl_fetch_relay" :url url :method method :headers headers :body body)

fn parseRelayResponse statusCode: I64 headers: (List Str) body: Str -> ExtensionRelayResponse
  (ExtensionRelayResponse :statusCode statusCode :headers headers :body body :success (and (>= statusCode 200) (< statusCode 300)))
