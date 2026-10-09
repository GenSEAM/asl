(module asl-target-swift/tests/swiftAudioCockpitTest :x [runTests] :i [(asl-target-swift/audio :a a) (asl-target-swift/cockpitView :a cv)])

fn testSwiftAudioHeader -> Bool
  (let [(hdr (a/emitSwiftAudioHeader))]
    (assert (stringContains? hdr "import Foundation") "Header includes Foundation")
    (assert (stringContains? hdr "import AVFoundation") "Header includes AVFoundation")
    (assert (stringContains? hdr "import CoreAudio") "Header includes CoreAudio")
    (assert (stringContains? hdr "import Combine") "Header includes Combine")
    (refute (stringContains? hdr "import pyaudio") "Refutes Python pyaudio")
    (refute (stringContains? hdr "#include <alsa/asound.h>") "Refutes ALSA C headers")
    true)

fn testSwiftAudioModeEnum -> Bool
  (let [(enums (a/emitSwiftAudioModeEnum))]
    (assert (stringContains? enums "enum AudioIngressMode") "Contains AudioIngressMode enum")
    (assert (stringContains? enums "case pushToTalk = \"ptt\"") "Contains PTT mode")
    (assert (stringContains? enums "case alwaysListening = \"always\"") "Contains Always-Listening mode")
    (assert (stringContains? enums "enum AudioIngressStatus") "Contains AudioIngressStatus enum")
    (assert (stringContains? enums "case transmitting") "Contains transmitting status")
    (assert (stringContains? enums "enum SpeechLanguageMode") "Contains SpeechLanguageMode enum")
    (assert (stringContains? enums "case autoDetect = \"auto\"") "Contains autoDetect default mode")
    (assert (stringContains? enums "case ruRU = \"ru-RU\"") "Contains specific language option ru-RU")
    (refute (stringContains? enums "raw_string_mode") "Refutes raw string mode")
    true)

fn testSwiftAudioIngressCodegen -> Bool
  (let [(code (a/emitSwiftAudioIngress "127.0.0.1" "8765"))]
    (assert (stringContains? code "AudioIngressController: NSObject, ObservableObject") "Controller conforms to ObservableObject")
    (assert (stringContains? code "@MainActor") "MainActor thread isolation enforced")
    (assert (stringContains? code "speechLanguage: SpeechLanguageMode = .autoDetect") "Defaults to auto-detect language mode")
    (assert (stringContains? code "detectedLanguageTag: String = \"auto\"") "Tracks live detected language tag")
    (assert (stringContains? code "setVoiceProcessingEnabled(true)") "macOS hardware AUVoiceProcessingIO enabled")
    (assert (stringContains? code "targetSampleRate: Double = 16000.0") "Target sample rate is 16kHz")
    (assert (stringContains? code "duckingVolumeDeltaDb: Float = -12.0") "Barge-in ducking is -12dB")
    (assert (stringContains? code "/api/asl/voice/stream") "Gateway stream path embedded")
    (assert (stringContains? code "gatewayHost: String = \"127.0.0.1\"") "Default gateway host embedded")
    (assert (stringContains? code "func setPushToTalkActive") "PTT handler implemented")
    (assert (stringContains? code "func duckAudio") "Audio ducking handler implemented")
    (assert (stringContains? code "func streamPcmBuffer") "PCM streaming pipeline implemented")
    (assert (stringContains? code "AUVoiceProcessingIO") "AUVoiceProcessingIO documented and configured")
    (refute (stringContains? code "44100.0") "Refutes 44.1kHz sample rate")
    (refute (stringContains? code "subprocess.Popen") "Refutes python subprocess calls")
    (refute (stringContains? code "WebAssembly") "Refutes WebAssembly in native swift")
    true)

fn testSwiftVoiceBarViewCodegen -> Bool
  (let [(vb (cv/emitSwiftVoiceBarView))]
    (assert (stringContains? vb "struct VoiceBarView: View") "Declares SwiftUI VoiceBarView")
    (assert (stringContains? vb "normalizedLevel") "Calculates normalized dBFS meter level")
    (assert (stringContains? vb "Text(ingress.mode == .pushToTalk ? \"PTT\" : \"ALWAYS\")") "Renders PTT and ALWAYS badges")
    (assert (stringContains? vb "speakerVerified ? \"Verified\" : \"Unknown\"") "Renders speaker biometric badge")
    (assert (stringContains? vb "ingress.currentDbfs") "Displays live numeric dBFS readout")
    (assert (stringContains? vb "ingress.speechLanguage == .autoDetect") "VoiceBar shows dynamic speech language auto/locked badge")
    (assert (stringContains? vb "NSColor.windowBackgroundColor") "Uses native macOS window background")
    (refute (stringContains? vb "HTMLTableElement") "Refutes HTML in SwiftUI")
    (refute (stringContains? vb "tkinter") "Refutes Tkinter in SwiftUI")
    true)

fn testSwiftAttentionRailViewCodegen -> Bool
  (let [(ar (cv/emitSwiftAttentionRailView))]
    (assert (stringContains? ar "struct AttentionRailView: View") "Declares SwiftUI AttentionRailView")
    (assert (stringContains? ar "Attention Rail: Two-Phase Commit Required") "Contains 2PC header title")
    (assert (stringContains? ar "Tier-2 Destructive") "Categorizes Tier-2 Destructive actions")
    (assert (stringContains? ar "Tier-1 Safe") "Categorizes Tier-1 Safe actions")
    (assert (stringContains? ar "Commit (Enter)") "Includes English spoken commit text")
    (assert (stringContains? ar "Cancel (Escape)") "Includes English spoken cancel text")
    (assert (stringContains? ar ".keyboardShortcut(.defaultAction)") "Binds Enter keyboard shortcut")
    (assert (stringContains? ar ".keyboardShortcut(.cancelAction)") "Binds Escape keyboard shortcut")
    (refute (stringContains? ar "window.confirm") "Refutes JavaScript browser confirm")
    (refute (stringContains? ar "alert(\"Confirm?\")") "Refutes basic JS alert")
    true)

fn testSwiftCockpitAudioViewsCombined -> Bool
  (let [(combined (cv/emitSwiftCockpitAudioViews))]
    (assert (stringContains? combined "struct VoiceBarView: View") "Combined contains VoiceBarView")
    (assert (stringContains? combined "struct AttentionRailView: View") "Combined contains AttentionRailView")
    (refute (stringContains? combined "undefined") "Combined refutes undefined")
    true)

fn runTests -> Bool
  (let [(r1 (testSwiftAudioHeader))
        (r2 (testSwiftAudioModeEnum))
        (r3 (testSwiftAudioIngressCodegen))
        (r4 (testSwiftVoiceBarViewCodegen))
        (r5 (testSwiftAttentionRailViewCodegen))
        (r6 (testSwiftCockpitAudioViewsCombined))]
    (assert r1 "testSwiftAudioHeader passed")
    (assert r2 "testSwiftAudioModeEnum passed")
    (assert r3 "testSwiftAudioIngressCodegen passed")
    (assert r4 "testSwiftVoiceBarViewCodegen passed")
    (assert r5 "testSwiftAttentionRailViewCodegen passed")
    (assert r6 "testSwiftCockpitAudioViewsCombined passed")
    true)
