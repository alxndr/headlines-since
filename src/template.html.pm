#lang pollen

◊(define title "Headlines Since")

◊(define (head)
   `(head
     (meta ((charset "utf-8")))
     (meta ((name "viewport") (content "width=device-width, initial-scale=1")))
     (title ,title)
     (link ((rel "stylesheet") (type "text/css") (href "styles.css")))))

◊(define (body . content)
   `(body
     (main ,@content)))

◊(define (template doc)
   `(html ((lang "en"))
      ,(head)
      ,(apply body (select-from-doc 'root doc))))

◊(provide template)
