# views.l -- near line-for-line port of demo/views/contacts/*.eta to
# PicoLisp tag functions (html.l). Each view function returns a
# fragment (see html.l); call (html Frag) to get the final string.

(load "html.l")
(load "contacts.l")
(load "util.l")

(de v:row (C)
   (let Id (c:get C "id")
      (<div> (list (cons "class" "row") (cons "id" (pack "c-" Id)))
         (<div> "cell" (c:get C "name"))
         (<div> "cell" (c:get C "email"))
         (<div> "cell" (c:get C "phone"))
         (<div> "actions"
            (<button>
               (list
                  (cons "fx-action" (pack "/contacts/" Id "/edit"))
                  (cons "fx-target" (pack "#c-" Id)) )
               "edit" )
            (<button>
               (list
                  (cons "class" "danger")
                  (cons "fx-action" (pack "/contacts/" Id))
                  (cons "fx-method" "DELETE")
                  (cons "fx-target" (pack "#c-" Id))
                  (cons "on-fx:config" "cfg.confirm = () => confirm('Delete this contact?')") )
               (ht:ent "&times;") ) ) ) ) )

# --- fast row rendering -------------------------------------------------
#
# v:row above is the readable, line-for-line port and is kept as the
# source of truth. But it's called once per contact per request, and
# profiling showed the generic tag-function machinery (curry/apply over
# every attribute and child, recursive ht:render dispatch) dominates
# per-request time once the page shell itself was cached (see v:page).
#
# A contact row's markup is otherwise fixed: only id/name/email/phone
# vary, each slotted into the same handful of spots every time. So at
# load time, render v:row once against fake "marker" values, tokenize
# the resulting string into literal chunks + marker positions, and at
# request time just walk that token list substituting real values in --
# no tag functions, no attribute lists, no recursion.

(de v:indexOf (Needle Hay)
   (v:indexOfLoop (chop Needle) Hay 0) )

(de v:indexOfLoop (N Hay Pos)
   (cond
      ((not Hay) -1)
      ((= N (head (length N) Hay)) Pos)
      (T (v:indexOfLoop N (cdr Hay) (inc Pos))) ) )

# Tokenize Chars (a char list) against Markers (list of (MarkerStr . Sym))
# into a list mixing literal strings and marker symbols, in order.
(de v:tokenize (Chars Markers)
   (if (not Chars)
      NIL
      (let (Best NIL  BestPos NIL  BestLen NIL)
         (for M Markers
            (let Pos (v:indexOf (car M) Chars)
               (when (and (>= Pos 0) (or (not Best) (< Pos BestPos)))
                  (setq Best M  BestPos Pos  BestLen (length (chop (car M)))) ) ) )
         (if (not Best)
            (list (pack Chars))
            (cons
               (pack (head BestPos Chars))
               (cons (cdr Best)
                  (v:tokenize (tail (- (+ BestPos BestLen)) Chars) Markers) ) ) ) ) ) )

(setq *RowMarkers
   (list
      (cons "@@MARKER-ID@@"    'ID)
      (cons "@@MARKER-NAME@@"  'NAME)
      (cons "@@MARKER-EMAIL@@" 'EMAIL)
      (cons "@@MARKER-PHONE@@" 'PHONE) ) )

(setq *RowTokens
   (v:tokenize
      (chop
         (html
            (v:row
               (list
                  (cons "id" "@@MARKER-ID@@")
                  (cons "name" "@@MARKER-NAME@@")
                  (cons "email" "@@MARKER-EMAIL@@")
                  (cons "phone" "@@MARKER-PHONE@@") ) ) ) )
      *RowMarkers ) )

(de v:rowFast (C)
   (let
      (Id (c:get C "id")
         Name (ht:esc (c:get C "name"))
         Email (ht:esc (c:get C "email"))
         Phone (ht:esc (c:get C "phone")) )
      (pack
         (mapcar
            '((Tok)
               (cond
                  ((= Tok 'ID) Id)
                  ((= Tok 'NAME) Name)
                  ((= Tok 'EMAIL) Email)
                  ((= Tok 'PHONE) Phone)
                  (T Tok) ) )
            *RowTokens ) ) ) )

(de v:list (Contacts)
   (if Contacts
      (pack "<div id=\"contacts-list\">" (apply pack (mapcar v:rowFast Contacts)) "</div>")
      (pack "<div id=\"contacts-list\">" (html (<div> "row empty" "No matches.")) "</div>") ) )

(de v:edit (C)
   (let Id (c:get C "id")
      (<form>
         (list
            (cons "class" "row editing")
            (cons "id" (pack "c-" Id))
            (cons "fx-action" (pack "/contacts/" Id))
            (cons "fx-method" "PUT") )
         (<div> "cell"
            (<input> (list (cons "name" "name") (cons "value" (c:get C "name")) (cons "autofocus" "autofocus") (cons "required" "required"))) )
         (<div> "cell"
            (<input> (list (cons "name" "email") (cons "value" (c:get C "email")) (cons "type" "email") (cons "required" "required"))) )
         (<div> "cell"
            (<input> (list (cons "name" "phone") (cons "value" (c:get C "phone")) (cons "type" "tel") (cons "required" "required"))) )
         (<div> "actions"
            (<button> (list (cons "live" "this.disabled = !this.form.checkValidity()")) "save")
            (<button>
               (list
                  (cons "type" "button")
                  (cons "fx-action" (pack "/contacts/" Id))
                  (cons "fx-target" (pack "#c-" Id)) )
               "cancel" ) ) ) ) )

# Everything in the page except the contact list itself is identical on
# every request (same nav, head, toolbar, form markup). Rebuilding all of
# that through the tag-function machinery (curry/apply/mapcar + attribute
# packing) on every single request measured as the dominant per-request
# cost -- far more than rendering the actual rows. Build it once at load
# time, split around a marker where the list goes, and on each request
# just pack the two static halves around the freshly rendered list.
(de v:pageHalves ()
   (let Marker "@@FIXI-CONTACTS-LIST@@"
      (let Full
         (html
            (ht:page "Contacts" "contacts"
               (<div> "contacts"
                  (<h1> NIL "📒 Contacts")
                  (<div> "toolbar"
                     (<input>
                        (list
                           (cons "id" "search") (cons "name" "q") (cons "type" "search")
                           (cons "placeholder" "Search name, email, phone…")
                           (cons "autofocus" "autofocus")
                           (cons "fx-action" "/contacts")
                           (cons "fx-trigger" "search")
                           (cons "fx-target" "#contacts-list")
                           (cons "fx-swap" "morph")
                           (cons "on-input" "await debounce(180); trigger('search')") ) )
                     (<form>
                        (list
                           (cons "class" "new")
                           (cons "fx-action" "/contacts")
                           (cons "fx-method" "POST")
                           (cons "fx-target" "#contacts-list")
                           (cons "fx-swap" "morph")
                           (cons "on-fx:swapped" "this.reset(); q('first input').focus()") )
                        (<input> (list (cons "name" "name") (cons "placeholder" "New name") (cons "required" "required")))
                        (<input> (list (cons "name" "email") (cons "placeholder" "email") (cons "type" "email") (cons "required" "required")))
                        (<input> (list (cons "name" "phone") (cons "placeholder" "phone") (cons "type" "tel") (cons "required" "required")))
                        (<button> (list (cons "live" "this.disabled = !this.form.checkValidity()")) "+ Add") ) )
                  (<div> "row header"
                     (<div> NIL "Name") (<div> NIL "Email") (<div> NIL "Phone") (<div> NIL "") )
                  (ht:ent Marker) ) ) )
         (list (pack (u:before Marker (chop Full))) (pack (u:after Marker (chop Full)))) ) ) )

(setq *PageHalves (v:pageHalves))

(de v:page (Contacts)
   (pack (car *PageHalves) (html (v:list Contacts)) (cadr *PageHalves)) )
