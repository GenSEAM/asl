enum Light (red) (green) (yellow)

fn lightIndex light: Light -> Int64
  (match light
    ((red) 0)
    ((green) 1)
    ((yellow) 2))

fn lightFromIndex i: Int64 -> Light
  (cond ((= i 0) (red)) ((= i 1) (green)) (else (yellow)))

fn trafficLightNext light: Light steps: Int64 -> Light
  (let [(s (- steps (* (/ steps 3) 3)))
        (i (+ (lightIndex light) s))]
    (lightFromIndex (- i (* (/ i 3) 3))))
