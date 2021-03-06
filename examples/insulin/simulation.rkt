#lang racket


;; Natural (in days) [Real] -> (Listof (vector Natural Natural)) (Listof (vector Natural Natural))
;; takes the number of days to run the simulation and returns:
;; 1. Time x insulin infusion rate (units/kg/hour). Each point is when the infusion changes
;; 2. Time x aBg count (seconds). Each point is when the test was asked for, and what the results are be
;; all lists are ordered by time

(provide simulate)

(require "insulin.pop" pop-pl/private/shared pop-pl/system-unit racket/runtime-path)
(define-values/invoke-unit/infer system@)

(define time-advance 60);in seconds
(define perterb-percent 0.2)
(define basic-factor 25)


(define (simulate days [factor basic-factor])
  (define fulltime (* days 24 60 60))
  (define log (run-simulation-for fulltime factor))
  (define-values (ic bg)
    (for/fold ([infusion null] [blood-glucose null])
              ([m log])
      (match m
        [(or (message '(change) (list insulin (in:number amount _))   t)
             (message '(start)  (list insulin (in:number amount _) _) t))
         (values (cons (vector t amount) infusion)
                 blood-glucose)]
        [(message '(bg) (list amount) t)
         (values infusion
                 (cons (vector t amount) blood-glucose))]
        [else (values infusion blood-glucose)])))
  (define last (vector fulltime (vector-ref (first ic) 1)))
  (values (cons last (reverse ic))
          (reverse bg)))

(define the-network (new-network))
(define-runtime-path insulin.pop "insulin.pop")
(define (run-simulation-for time factor)
  (define-values (res _in-system _cont-dosage _next)
    (for/fold ([outgoing (spawn-actor! the-network insulin.pop)]
               [insulin-in-system 0] [insulin-continous 0] [next null])
              ([_ (in-range 0 time 60)])
      (define tlog (inc-time))
      (define log
        (append tlog
                (for/fold ([r null]) ([msg next])
                  (append r (send-message! the-network msg) (list msg)))))
      (define-values (o his hc n)
        (eval-log (reverse log) outgoing insulin-in-system insulin-continous factor))
      (values o
              (insulin-values-after his hc time-advance)
              hc
              n)))
  (set! the-network (new-network))
  res)

(define (inc-time)
  (advance! the-network time-advance))

(define (eval-log new-log outgoing insulin-in-system insulin-continous factor [handle-next null])
  (define restart-amount 0)
  (define (eval-log* ic)
    (eval-log (rest new-log)
              (cons (first new-log) outgoing)
              insulin-in-system
              ic
              factor
              handle-next))
  (if (null? new-log)
      (values outgoing insulin-in-system insulin-continous handle-next)
      (let ([msg (first new-log)])
        (match msg
          [(or (message '(change) (list insulin (in:number n _))   t)
               (message '(start)  (list insulin (in:number n _) _) t))
           (eval-log* n)]
          [(message '(hold) _ _)
           (eval-log* 0)]
          [(message '(checkbg) _ t)
           (eval-log (rest new-log)
                     (cons msg outgoing)
                     insulin-in-system
                     insulin-continous
                     factor
                     (cons (new-bg (calculate-bg insulin-in-system factor) t) handle-next))]
          [else (eval-log* insulin-continous)]))))

(define (new-bg value time)
  (message '(bg) (list value) (add1 time)))

(define (calculate-bg h factor)
  (* (perterb-random)
     (- 125 (* h factor))))

(define halflife (* 6 60));90 minutes in seconds
(define (insulin-values-after current continous seconds)
  (* (perterb-random)
     current))

(define (perterb-random [% perterb-percent])
  (+ 1 (* (- (* 2 (random)) 1) %)))
