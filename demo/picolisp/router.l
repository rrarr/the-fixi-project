# router.l -- tiny method+path router, PicoLisp port of
# demo/lib/router.mjs. Patterns are strings like "/contacts/:id/edit";
# each :name segment matches one path component and is returned in the
# Params assoc list passed to the handler.

(setq *Routes NIL)

(de r:split (Path)
   (filter '((S) (<> (pack S) "")) (split (chop Path) "/")) )

# Register a route: Method is a string "GET"/"POST"/"PUT"/"DELETE",
# Pattern a string, Handler a function taking (Sock Params Query Form).
(de route (Method Pattern Handler)
   (push '*Routes (list Method (r:split Pattern) Handler)) )

# Try to match Segments (a list of path-component strings, already
# chopped) against Pattern (also a list of chopped segments, some of
# which may be ":name"). Returns an assoc list of params, or 'fail.
(de r:match (Pattern Segments)
   (cond
      ((and (not Pattern) (not Segments)) NIL)
      ((or (not Pattern) (not Segments)) 'fail)
      (T
         (let (P (pack (car Pattern)) S (pack (car Segments)))
            (if (pre? ":" P)
               (let Rest (r:match (cdr Pattern) (cdr Segments))
                  (if (= Rest 'fail)
                     'fail
                     (cons (cons (pack (tail (- 1) (chop P))) S) Rest) ) )
               (if (= P S)
                  (r:match (cdr Pattern) (cdr Segments))
                  'fail ) ) ) ) ) )

# Dispatch (Method Path) against all registered routes, in the order
# they were registered (routes are pushed, so reverse to keep that order).
# Calls the matching handler as (Handler Sock Params Query Form) and
# returns T, or NIL if nothing matched.
(de r:dispatch (Method Path Sock Query Form)
   (let Segments (r:split Path)
      (find
         '((R)
            (and
               (= Method (car R))
               (let Params (r:match (cadr R) Segments)
                  (unless (= Params 'fail)
                     ((caddr R) Sock Params Query Form)
                     T ) ) ) )
         (flip (copy *Routes)) ) ) )
