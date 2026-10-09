(module aslVdom/physicsReactor :x [Particle Spring Force2D makeParticle coulombRepulsion hookeSpringForce eulerIntegrate] :i [])

(schema Particle (:f x F64) (:f y F64) (:f vx F64) (:f vy F64) (:f mass F64))

(schema Spring (:f fromIdx I64) (:f toIdx I64) (:f restLength F64) (:f stiffness F64))

(schema Force2D (:f fx F64) (:f fy F64))

fn makeParticle x: F64 y: F64 -> Particle
  (Particle :x x :y y :vx 0.0 :vy 0.0 :mass 1.0)

fn coulombRepulsion p1: Particle p2: Particle k: F64 -> Force2D
  (let [(dx (- p1.x p2.x)) (dy (- p1.y p2.y)) (distSq (+ (* dx dx) (+ (* dy dy) 0.01))) (force (/ k distSq))] (Force2D :fx (* dx force) :fy (* dy force)))

fn hookeSpringForce p1: Particle p2: Particle rest: F64 k: F64 -> Force2D
  (let [(dx (- p2.x p1.x)) (dy (- p2.y p1.y)) (dist (sqrt (+ (* dx dx) (* dy dy)))) (displacement (- dist rest))] (Force2D :fx (* (* dx k) displacement) :fy (* (* dy k) displacement)))

fn eulerIntegrate p: Particle f: Force2D dt: F64 damping: F64 -> Particle
  (let [(newVx (* (+ p.vx (* (/ f.fx p.mass) dt)) damping)) (newVy (* (+ p.vy (* (/ f.fy p.mass) dt)) damping)) (newX (+ p.x (* newVx dt))) (newY (+ p.y (* newVy dt)))] (with p :x newX :y newY :vx newVx :vy newVy))
