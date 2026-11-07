# contacts.l -- in-memory contact store, direct port of
# demo/apps/contacts.mjs. Each contact is a plain assoc list:
#   (("id" . 1) ("name" . "Lena Park") ("email" . "lena@example.com") ("phone" . "555-0101"))

(setq *Contacts
   (list
      (list (cons "id" 1) (cons "name" "Lena Park")    (cons "email" "lena@example.com")        (cons "phone" "555-0101"))
      (list (cons "id" 2) (cons "name" "Kai Bennett")   (cons "email" "kai@example.com")         (cons "phone" "555-0102"))
      (list (cons "id" 3) (cons "name" "Yuki Tanaka")   (cons "email" "yuki.tanaka@example.com") (cons "phone" "555-0103"))
      (list (cons "id" 4) (cons "name" "Priya Sharma")  (cons "email" "priya@example.com")       (cons "phone" "555-0104"))
      (list (cons "id" 5) (cons "name" "Diego Ramos")   (cons "email" "diego.ramos@example.com") (cons "phone" "555-0105"))
      (list (cons "id" 6) (cons "name" "Mei Chen")      (cons "email" "mei@example.com")         (cons "phone" "555-0106"))
      (list (cons "id" 7) (cons "name" "Olu Adesina")   (cons "email" "olu@example.com")         (cons "phone" "555-0107")) ) )

(setq *NextId 8)

(de c:get (C Key)
   (cdr (assoc Key C)) )

(de c:trim (S Max)
   (let L (clip (chop (or S "")))
      (pack (head Max L)) ) )

(de c:id (Id)
   (if (str? Id) (format Id) Id) )

(de contacts:all ()
   *Contacts )

(de contacts:find (Id)
   (let Id (c:id Id)
      (find '((C) (= (c:get C "id") Id)) *Contacts) ) )

(de contacts:search (Q)
   (if (or (not Q) (= Q ""))
      *Contacts
      (let N (lowc Q)
         (filter
            '((C)
               (or
                  (sub? N (lowc (c:get C "name")))
                  (sub? N (lowc (c:get C "email")))
                  (sub? N (c:get C "phone")) ) )
            *Contacts ) ) ) )

(de contacts:add (Name Email Phone)
   (let N (c:trim Name 80)
      (and N (<> N "")
         (let C
            (list
               (cons "id" *NextId)
               (cons "name" N)
               (cons "email" (c:trim Email 80))
               (cons "phone" (c:trim Phone 40)) )
            (inc '*NextId)
            (setq *Contacts (append *Contacts (list C)))
            C ) ) ) )

(de contacts:update (Id Name Email Phone)
   (let C (contacts:find Id)
      (and C
         (let N (c:trim Name 80)
            (con (assoc "name" C) (if (<> N "") N (c:get C "name")))
            (con (assoc "email" C) (c:trim Email 80))
            (con (assoc "phone" C) (c:trim Phone 40))
            C ) ) ) )

(de contacts:remove (Id)
   (let C (contacts:find Id)
      (and C
         (setq *Contacts (delete C *Contacts))
         T ) ) )
