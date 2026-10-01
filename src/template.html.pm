◊(define title "Headlines Since")
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>◊|title|</title>
    <link rel="stylesheet" type="text/css" href="styles.css">
  </head>
  <body>
    <main>
      ◊(->html doc)
    </main>
    ◊(->html (select-from-doc 'script doc))
  </body>
</html>