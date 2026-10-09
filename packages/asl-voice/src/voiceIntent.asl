(module aslVoice/voiceIntent :x [dispatchSpeechUtterance bindIntentToInflight formatVoiceIntentAsn] :i [(voice/transliterator :a tr) (voice/fastPath :a fp)])

fn formatVoiceIntentAsn goal: Str actions: (List Str) -> Str
  (tr/emitAsnIntent goal actions)

fn dispatchSpeechUtterance utterance: Str -> Str
  (tr/transliterateVoicePrompt utterance)

fn bindIntentToInflight taskId: Str intentAsn: Str -> Str
  (let [(cleanIntent (if (stringStartsWith? intentAsn "(") intentAsn (formatVoiceIntentAsn intentAsn (list intentAsn))))] (str "(:in-flight :task-id \"" taskId "\" :intent " cleanIntent " :status :active)"))
