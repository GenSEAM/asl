(module asl-syntax/core/bench
  :x [BenchFigure
      makeBenchFigure
      figureMethod
      figureScope
      figureDate
      figureSamples
      figureMedianNs
      figureMedianMs
      figureBytes
      figureMsPer100Kb
      computeMedian
      computeMsPer100Kb
      benchRun!
      benchMedian5!
      renderBenchFigure]
  :i [])

(schema BenchFigure
  (:f method String)
  (:f scope String)
  (:f date String)
  (:f samples (List Int64))
  (:f medianNs Int64)
  (:f medianMs Float64)
  (:f bytes Int64)
  (:f msPer100Kb Float64))

fn makeBenchFigure method: String scope: String date: String samples: (List Int64) medianNs: Int64 medianMs: Float64 bytes: Int64 msPer100Kb: Float64 -> BenchFigure
  (BenchFigure :method method
               :scope scope
               :date date
               :samples samples
               :medianNs medianNs
               :medianMs medianMs
               :bytes bytes
               :msPer100Kb msPer100Kb)

fn figureMethod fig: BenchFigure -> String
  fig.method

fn figureScope fig: BenchFigure -> String
  fig.scope

fn figureDate fig: BenchFigure -> String
  fig.date

fn figureSamples fig: BenchFigure -> (List Int64)
  fig.samples

fn figureMedianNs fig: BenchFigure -> Int64
  fig.medianNs

fn figureMedianMs fig: BenchFigure -> Float64
  fig.medianMs

fn figureBytes fig: BenchFigure -> Int64
  fig.bytes

fn figureMsPer100Kb fig: BenchFigure -> Float64
  fig.msPer100Kb

fn computeMedian samples: (List Int64) -> Int64
  (if (listEmpty? samples)
    0
    (let [(sorted (listSort samples))
          (n (listLength sorted))
          (mid (/ n 2))]
      (optionOr (listGet sorted mid) 0)))

fn computeMsPer100Kb medianMs: Float64 bytes: Int64 -> Float64
  (if (<= bytes 0)
    0.0
    (/ (* medianMs 102400.0) (int64ToFloat64 bytes)))

fn benchLoop! fnToBench: (fn [] -> Unit) remaining: Int64 acc: (List Int64) -> (List Int64)
  (if (<= remaining 0)
    (listReverse acc)
    (let [(t0 (monotonicNs))
          (dummy (fnToBench))
          (t1 (monotonicNs))
          (elapsed (- t1 t0))]
      (benchLoop! fnToBench (- remaining 1) (cons elapsed acc))))

fn benchRun! fnToBench: (fn [] -> Unit) runs: Int64 bytes: Int64 scope: String method: String date: String -> BenchFigure
  (let [(effectiveRuns (if (<= runs 0) 1 runs))
        (samples (benchLoop! fnToBench effectiveRuns (list)))
        (medianNs (computeMedian samples))
        (medianMs (/ (int64ToFloat64 medianNs) 1000000.0))
        (msPer100Kb (computeMsPer100Kb medianMs bytes))]
    (BenchFigure :method method
                 :scope scope
                 :date date
                 :samples samples
                 :medianNs medianNs
                 :medianMs medianMs
                 :bytes bytes
                 :msPer100Kb msPer100Kb))

fn benchMedian5! fnToBench: (fn [] -> Unit) bytes: Int64 scope: String date: String -> BenchFigure
  (benchRun! fnToBench 5 bytes scope "median of 5 runs, monotonicNs" date)

fn renderBenchFigure fig: BenchFigure -> String
  (str "(:benchFigure"
       " :method \"" fig.method "\""
       " :scope \"" fig.scope "\""
       " :date \"" fig.date "\""
       " :medianNs " (stringFromInt64 fig.medianNs)
       " :medianMs " (stringFromFloat64 fig.medianMs)
       " :bytes " (stringFromInt64 fig.bytes)
       " :msPer100Kb " (stringFromFloat64 fig.msPer100Kb)
       ")")
