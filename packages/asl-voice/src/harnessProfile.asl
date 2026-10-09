(module aslVoice/harnessProfile :x [HarnessPhoneticAlias HarnessHardwareEndpoint HarnessProfile makePhoneticAlias makeHardwareEndpoint makeDefaultHarnessProfile makeDefaultHynessProfile addPhoneticAlias addHardwareEndpoint resolveHarnessAlias applyHarnessAliases findEndpointByKind formatHarnessProfileAsn formatHynessProfileAsn] :i [(asl-text/string :a s)])

(schema HarnessPhoneticAlias (:f spoken Str) (:f mapsTo Str))

(schema HarnessHardwareEndpoint (:f kind Str) (:f name Str) (:f endpoint Str))

(schema HarnessProfile (:f profileName Str) (:f primaryLocale Str) (:f secondaryLocale Str) (:f isMixedMode Bool) (:f aliases (List HarnessPhoneticAlias)) (:f endpoints (List HarnessHardwareEndpoint)) (:f speakerVoiceprintPath Str))

fn makePhoneticAlias spoken: Str mapsTo: Str -> HarnessPhoneticAlias
  (HarnessPhoneticAlias :spoken spoken :mapsTo mapsTo)

fn makeHardwareEndpoint kind: Str name: Str endpoint: Str -> HarnessHardwareEndpoint
  (HarnessHardwareEndpoint :kind kind :name name :endpoint endpoint)

fn makeDefaultHarnessProfile -> HarnessProfile
  (let [(a1 (makePhoneticAlias "асекс" "genseam")) (a2 (makePhoneticAlias "хайнесс" "harness")) (a3 (makePhoneticAlias "шроуди" "shrody")) (a4 (makePhoneticAlias "датахаб" "datahub")) (a5 (makePhoneticAlias "пцп" "pcp")) (a6 (makePhoneticAlias "ханес" "harness")) (aliases (list a1 a2 a3 a4 a5 a6)) (epIn (makeHardwareEndpoint "input" "Default Microphone" "coreaudio://default-input")) (epOut (makeHardwareEndpoint "output" "Default Speaker" "coreaudio://default-output")) (epCdp (makeHardwareEndpoint "cdp" "Chrome DevTools" "ws://127.0.0.1:9222/devtools/browser")) (epSlm (makeHardwareEndpoint "slm" "Local MLX Qwen" "http://127.0.0.1:8081/v1/chat/completions")) (epHub (makeHardwareEndpoint "hub" "ASL Domain Socket Hub" "~/.asl/run/hub.sock")) (endpoints (list epIn epOut epCdp epSlm epHub))] (HarnessProfile :profileName "harness-workstation" :primaryLocale "en" :secondaryLocale "ru" :isMixedMode true :aliases aliases :endpoints endpoints :speakerVoiceprintPath "~/.asl/harness/speaker_voiceprint.onnx"))

fn makeDefaultHynessProfile -> HarnessProfile
  (makeDefaultHarnessProfile)

fn addPhoneticAlias prof: HarnessProfile alias: HarnessPhoneticAlias -> HarnessProfile
  (let [(updated (listAppend prof.aliases (list alias)))] (with prof :aliases updated))

fn addHardwareEndpoint prof: HarnessProfile ep: HarnessHardwareEndpoint -> HarnessProfile
  (let [(updated (listAppend prof.endpoints (list ep)))] (with prof :endpoints updated))

fn resolveHarnessAlias prof: HarnessProfile word: Str -> Str
  (let [(matches (filter (fn [(a HarnessPhoneticAlias)] -> Bool (= (stringLower a.spoken) (stringLower word))) prof.aliases))] (if (listEmpty? matches) word (mt (listHead matches) ((some a) a.mapsTo) ((none) word))))

fn applyHarnessAliases prof: HarnessProfile text: Str -> Str
  (fold (fn [(acc Str) (alias HarnessPhoneticAlias)] -> Str (stringReplace acc alias.spoken alias.mapsTo)) text prof.aliases)

fn findEndpointByKind prof: HarnessProfile targetKind: Str -> Str
  (let [(matches (filter (fn [(ep HarnessHardwareEndpoint)] -> Bool (= ep.kind targetKind)) prof.endpoints))] (if (listEmpty? matches) "" (mt (listHead matches) ((some ep) ep.endpoint) ((none) ""))))

fn formatHarnessProfileAsn prof: HarnessProfile -> Str
  (let [(aLen (stringFromInt64 (listLength prof.aliases))) (eLen (stringFromInt64 (listLength prof.endpoints))) (mmStr (if prof.isMixedMode "true" "false"))] (str "(:harness-profile :name \"" prof.profileName "\" :primary \"" prof.primaryLocale "\" :secondary \"" prof.secondaryLocale "\" :mixed-mode " mmStr " :alias-count " aLen " :endpoint-count " eLen ")"))

fn formatHynessProfileAsn prof: HarnessProfile -> Str
  (formatHarnessProfileAsn prof)
