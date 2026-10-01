#lang racketscript

(provide format-date-iso days-ago parse-rss-date normalize-title jaccard-tokens)

(define (pad2 n)
  (let ([s (number->string n)])
    (if (< n 10) (string-append "0" s) s)))

(define (format-date-iso d)
  (string-append
   (number->string (.getFullYear d)) "-"
   (pad2 (+ 1 (.getMonth d))) "-"
   (pad2 (.getDate d))))

(define (days-ago n)
  (let ([d (new Date)])
    (.setDate d (- (.getDate d) n))
    d))

(define (parse-rss-date s)
  (if (or (not s) (= (string-length s) 0))
      #f
      (let ([d (new Date s)])
        (if (js-isNaN (.getTime d)) #f d))))

(define (normalize-title t)
  (if (not t)
      ""
      (let* ([no-tags (t.replace #rx"<[^>]+>" "")]
             [collapsed (no-tags.replace #rx"\s+" " ")])
        (.trim collapsed))))

(define (tokenize-low t)
  (let ([m (t.match #rx"[A-Za-z0-9']{3,}")])
    (if (not m) '() (array->list m))))

(define (jaccard-tokens a b)
  (let ([A (list->set (tokenize-low (string-downcase (or a "")))))]
       [B (list->set (tokenize-low (string-downcase (or b ""))))]))
  (if (and (set-empty? A) (set-empty? B))
      0
      (let ([inter (set-intersect A B)]
            [union (set-union A B)])
        (/ (set-count inter) (set-count union)))))