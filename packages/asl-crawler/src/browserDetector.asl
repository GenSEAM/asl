(module aslCrawler/browserDetector :x [BrowserKind BrowserCandidate kindChrome kindBrave kindEdge kindSafari kindChromium makeCandidate macosBrowsers linuxBrowsers cdpArgs getMacosCandidates getLinuxCandidates buildCdpLaunchArgs] :i [])

(enum BrowserKind (:c browserChrome [] "Google Chrome") (:c browserBrave [] "Brave Privacy Browser") (:c browserEdge [] "Microsoft Edge") (:c browserSafari [] "Apple Safari") (:c browserChromium [] "Open-source Chromium"))

(schema BrowserCandidate (:f name Str) (:f path Str) (:f kind BrowserKind) (:f os Str))

fn kindChrome -> BrowserKind
  (browserChrome)

fn kindBrave -> BrowserKind
  (browserBrave)

fn kindEdge -> BrowserKind
  (browserEdge)

fn kindSafari -> BrowserKind
  (browserSafari)

fn kindChromium -> BrowserKind
  (browserChromium)

fn makeCandidate name: Str path: Str kind: BrowserKind os: Str -> BrowserCandidate
  (BrowserCandidate :name name :path path :kind kind :os os)

fn getMacosCandidates -> (List BrowserCandidate)
  (list (makeCandidate "Google Chrome" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" (browserChrome) "macos") (makeCandidate "Google Chrome (User)" "~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" (browserChrome) "macos") (makeCandidate "Brave Browser" "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" (browserBrave) "macos") (makeCandidate "Microsoft Edge" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" (browserEdge) "macos") (makeCandidate "Chromium" "/Applications/Chromium.app/Contents/MacOS/Chromium" (browserChromium) "macos") (makeCandidate "Safari" "/Applications/Safari.app/Contents/MacOS/Safari" (browserSafari) "macos"))

fn getLinuxCandidates -> (List BrowserCandidate)
  (list (makeCandidate "Google Chrome" "/usr/bin/google-chrome" (browserChrome) "linux") (makeCandidate "Chromium" "/usr/bin/chromium-browser" (browserChromium) "linux") (makeCandidate "Brave" "/usr/bin/brave-browser" (browserBrave) "linux") (makeCandidate "Chromium Binary" "/usr/bin/chromium" (browserChromium) "linux"))

fn macosBrowsers -> (List BrowserCandidate)
  (getMacosCandidates)

fn linuxBrowsers -> (List BrowserCandidate)
  (getLinuxCandidates)

fn cdpArgs browser: BrowserCandidate port: I64 url: Str headless: Bool -> (List Str)
  (buildCdpLaunchArgs browser port url headless)

fn buildCdpLaunchArgs browser: BrowserCandidate port: I64 url: Str headless: Bool -> (List Str)
  (let [(isChromium (mt browser.kind ((browserChrome) true) ((browserBrave) true) ((browserEdge) true) ((browserChromium) true) ((browserSafari) false))) (flags (if isChromium (let [(baseFlags (list (str "--remote-debugging-port=" (stringFromInt64 port)) "--no-first-run" "--no-default-browser-check" "--disable-blink-features=AutomationControlled" "--disable-infobars" "--window-size=1920,1080"))] (if headless (listAppend baseFlags (list "--headless=new")) baseFlags)) (list)))] (listAppend (cons browser.path flags) (list url)))
