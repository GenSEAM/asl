(module aslWebApiSearch/transport :x [RuntimeKind TransportStrategy resolveRuntimeStrategy buildTransportFetchCmd isCorsRestricted? isOfflineTransport?] :i [])

(enum RuntimeKind (:c desktopHost [] "Unrestricted host Node / CLI execution") (:c browserExtension [] "WebExtension background worker with <all_urls> permission") (:c browserWebpage [] "In-page DOM / WebLLM sandbox subject to CORS") (:c airgapSandbox [] "Restricted container / ERGP without outbound internet"))

(enum TransportStrategy (:c directCurl [] "Host direct curl / socket fetch") (:c extensionRelay [] "Relay through browser-plugin background worker") (:c corsSafeDirect [] "Direct fetch to CORS-enabled endpoints") (:c localDaemonBridge [] "Proxy through local ASL daemon on 127.0.0.1:8765") (:c memoryCacheOnly [] "Immediate offline fallback to resident research memory"))

fn isCorsRestricted? runtime: RuntimeKind -> Bool
  (mt runtime ((browserWebpage) true) ((airgapSandbox) true) ((desktopHost) false) ((browserExtension) false))

fn resolveRuntimeStrategy runtime: RuntimeKind hasExtension: Bool isCorsEndpoint: Bool -> TransportStrategy
  (mt runtime ((airgapSandbox) (memoryCacheOnly)) ((desktopHost) (directCurl)) ((browserExtension) (extensionRelay)) ((browserWebpage) (if hasExtension (extensionRelay) (if isCorsEndpoint (corsSafeDirect) (localDaemonBridge)))))

fn buildTransportFetchCmd strategy: TransportStrategy url: Str headers: (List Str) -> (List Str)
  (mt strategy ((directCurl) (let [(base (list "curl" "-sSL" "--max-time" "10")) (withHeaders (fold (fn [(acc (List Str)) (h Str)] -> (List Str) (listAppend acc (list "-H" h))) base headers))] (listAppend withHeaders (list "--" url)))) ((extensionRelay) (list "asl_extension_relay" "fetch" url)) ((corsSafeDirect) (list "fetch" url "cors:origin=*")) ((localDaemonBridge) (let [(u1 (stringReplace url "%" "%25")) (u2 (stringReplace u1 "&" "%26")) (u3 (stringReplace u2 "?" "%3F")) (u4 (stringReplace u3 "#" "%23")) (u5 (stringReplace u4 "=" "%3D"))] (list "curl" "-sSL" (str "http://127.0.0.1:8765/proxy?url=" u5)))) ((memoryCacheOnly) (list "mem_cache_hit" url)))

fn isOfflineTransport? strategy: TransportStrategy -> Bool
  (mt strategy ((memoryCacheOnly) true) (else false))
