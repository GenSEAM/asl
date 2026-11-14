enum Light (red) (green) (yellow)

fn trafficLightNext light: Light steps: Int64 -> Light
  (cond ((= steps 0) light)
        (else (trafficLightNext (match light
                                  ((red) (green))
                                  ((green) (yellow))
                                  ((yellow) (red)))
                                (- steps 1))))
