#lang pollen

◊define-meta[title]{Headlines Since}

◊h1{Headlines Since}

◊p{After being away, catch up on the biggest stories since a date you choose.}

◊(define hs-form
   `(form ((id "hs-form"))
      (label ((for "start-date")) "Start date (up to 1 year ago)")
      (input ((type "date") (id "start-date") (name "start-date") (required "required")))
      (label ((for "count")) "Number of stories")
      (input ((type "number") (id "count") (name "count") (min "5") (max "20") (value "10") (required "required")))
      (button ((type "submit")) "Find headlines")))

◊hs-form

◊(define hs-status
   `(div ((id "hs-status") (aria-live "polite"))))

◊hs-status

◊(define hs-results
   `(div ((id "hs-results"))))

◊hs-results

◊(define hs-about
   `(section
     (p "Biggest individual stories ranked by significance (no forced topic diversification).")))

◊hs-about

◊(define hs-script
   `(script ((src "js/app.js") (type "module"))))

◊hs-script