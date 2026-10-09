(module asl-cli/conform :x [runConformCmd parseConformArgs] :i [(aslConform/main :a conf)])

(schema ConformOptions (:f profile Str) (:f rule Str) (:f invert Bool))

fn parseConformArgs args: (List Str) profile: Str rule: Str invert: Bool -> ConformOptions
  (mt (listHead args) ((none) (ConformOptions :profile (if (= profile "") "py" profile) :rule rule :invert invert)) ((some flag) (let [(rest (optionOr (listTail args) (list)))] (cond ((stringStartsWith? flag "--profile=") (let [(val (stringReplace flag "--profile=" ""))] (parseConformArgs rest val rule invert))) ((= flag "--profile") (let [(val (optionOr (listHead rest) "py")) (nextRest (optionOr (listTail rest) (list)))] (parseConformArgs nextRest val rule invert))) ((stringStartsWith? flag "--rule=") (let [(val (stringReplace flag "--rule=" ""))] (parseConformArgs rest profile val invert))) ((= flag "--rule") (let [(val (optionOr (listHead rest) "")) (nextRest (optionOr (listTail rest) (list)))] (parseConformArgs nextRest profile val invert))) ((= flag "--invert") (parseConformArgs rest profile rule true)) (else (parseConformArgs rest profile rule invert))))))

fn ! runConformCmd args: (List Str) -> (Result Str Str)
  (let [(opts (parseConformArgs args "" "" false)) (profile opts.profile) (rule opts.rule) (invert opts.invert)] (conf/runConform! profile rule invert))
