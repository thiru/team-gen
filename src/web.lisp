;;;; Web-specific functionality.

(in-package :hockey-oracle.web)

;;; General
(defvar *debug* t)
(defvar main-acceptor nil "The global web-server instance.")
(defvar static-files-dir (merge-pathnames "www/" base-dir))

;; TODO: don't hard-code domain
(defparameter reset-pwd-msg
  (glu:str "<p>A request was made to reset your password. If you would like "
           "to continue please follow the link below. Please note, this "
           "request will expire within 24 hours.</p>"
           "<p><a href='~A://~A/reset-password?token=~A'>"
           "Reset my password</a></p>"))

(setf (html-mode) :HTML5)

(defun create-acceptor (&key (port 9090) debug)
  "Creates an 'easy-acceptor' which will listen on the specified port."
  (make-instance 'easy-acceptor
                 :port port
                 :document-root static-files-dir
                 :access-log-destination (if debug
                                             *standard-output*
                                             "~/tbnl-access.log")
                 :message-log-destination (if debug
                                              *standard-output*
                                              "~/tbnl-message.log")))

(defun start-server! (&key (port 9090) debug)
  "Starts the web server.
   @param port:
     Specifies the port for the web server.
   @param debug:
     If T, the server is started with access and message logs sent to standard
     out, and the following hunchentoot special variable settings:
     * *CATCH-ERRORS-P* => NIL
     * *SHOW-LISP-ERRORS-P* => T
   Side-effects: sets the special variable MAIN-ACCEPTOR to the created
   acceptor, and *DEBUG* to the value of DEBUG."
  (setf *debug* debug)
  (setf main-acceptor (create-acceptor :port port :debug debug))
  (when debug
    (setf *catch-errors-p* nil)
    (setf *show-lisp-errors-p* t))
  (start main-acceptor))

(defun stop-server ()
  "Stops the web server referenced by the special variable main-acceptor."
  (if main-acceptor
      (stop main-acceptor :soft t)))
;;; General ----------------------------------------------------------------- END

;;; Utils
(defmacro html-snippet (root-tag)
  "Generate HTML given a single root HTML tag."
  `(with-html-output-to-string (*standard-output* nil :indent t)
     ,root-tag))

(defmacro safe-parse-int (str &key (fallback 0))
  "Lenient parsing of 'str'."
  `(if (empty? ,str)
       ,fallback
       (or (parse-integer ,str :junk-allowed t) ,fallback)))

(defun based-on-path? (path base-path)
  "Determine whether 'path' is based on 'base-path'."
  (let ((path-segs (split-sequence #\/
                                   path
                                   :remove-empty-subseqs t)))
    (or (string-equal (first path-segs) base-path)
        (string-equal (second path-segs) base-path))))

(defun path-segments (req)
  "Gets a list of path segments, excluding query parameters."
  (split-sequence #\/ (script-name* req) :remove-empty-subseqs t))

(defun pretty-time (time-str &optional mode)
  "Formats a date/time to a user-friendly form. 'time-str' is expected to be a
   timestamp readable by LOCAL-TIME. MODE can be FULL or SHORT."
  (if (empty? time-str)
      ""
      (let* ((format-desc '())
             (timestamp (parse-timestring time-str)))

        (if (eq 'short mode)
            (setf format-desc '(:short-weekday " " :short-month " " :day " "
                                :hour12 ":" (:min 2) :ampm))
            (setf format-desc '(:long-weekday " " :short-month " " :day " "
                                :year " @ " :hour12 ":" (:min 2) :ampm)))

        (format-timestring nil timestamp :format format-desc))))

(defun parse-league (req)
  "Parses the request path to obtain the league defined as the first segment.
   The league is returned."
  (let* ((path-segs (path-segments req))
         (league-name (first path-segs)))
    (if (not (empty? league-name))
        (get-league :name league-name))))

(defun set-auth-cookie (player &key perm?)
  "Set the temporary or permanent authorisation cookie."
  (if player
      (set-cookie (if perm? "puser" "tuser")
                  :value (sf "~A-~A"
                             (player-id player)
                             (if perm?
                                 (player-perm-auth player)
                                 (player-temp-auth player)))
                  ;; Expire a month from now
                  :max-age (* 60 60 24 30)
                  :path "/"
                  :secure (not *debug*)
                  :http-only t)))

(defun remove-cookie (id)
  "Removes the cookie with the specified ID."
  (set-cookie id
              :value ""
              :max-age 0
              :path "/"
              :secure (not *debug*)
              :http-only t))

(defun remove-auth-cookies ()
  "Invalidates all authorisation cookies."
  (remove-cookie "puser")
  (remove-cookie "tuser"))
;;; Utils ------------------------------------------------------------------- END

;;; Routes
(setf *dispatch-table*
      (list (create-folder-dispatcher-and-handler "/deps/"
                                                  (merge-pathnames
                                                   "deps/"
                                                   static-files-dir))
            (create-folder-dispatcher-and-handler "/images/"
                                                  (merge-pathnames
                                                   "images/"
                                                   static-files-dir))
            (create-folder-dispatcher-and-handler "/scripts/"
                                                  (merge-pathnames
                                                   "scripts/"
                                                   static-files-dir))
            (create-folder-dispatcher-and-handler "/styles/"
                                                  (merge-pathnames
                                                   "styles/"
                                                   static-files-dir))
            (create-regex-dispatcher "^/$" 'www-home-page)
            (create-regex-dispatcher "^/about$"
                                     (lambda ()
                                       (base-league-page 'www-about-page
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/[a-zA-Z0-9-]+/about$"
                                     (lambda ()
                                       (base-league-page 'www-about-page)))
            (create-regex-dispatcher "^/logout/?$"
                                     (lambda ()
                                       (base-league-page 'www-user-logout-page
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/api/login/?$"
                                     (lambda ()
                                       (base-league-page 'api-login
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/api/forgot-password/?$"
                                     (lambda ()
                                       (base-league-page 'api-forgot-pwd
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/reset-password/?$"
                                     (lambda ()
                                       (base-league-page 'www-reset-pwd
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/api/reset-password/?$"
                                     (lambda ()
                                       (base-league-page 'api-reset-pwd
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/users/me/?$"
                                     (lambda ()
                                       (base-league-page 'www-user-detail-page
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/api/users/me/?$"
                                     (lambda ()
                                       (base-league-page 'api-user-save
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/leagues$"
                                     (lambda ()
                                       (base-league-page 'www-league-list-page
                                                         :require-league? nil)))
            (create-regex-dispatcher "^/[a-zA-Z0-9-]+/games$"
                                     (lambda ()
                                       (base-league-page 'www-game-list-page)))
            (create-regex-dispatcher "^/[a-zA-Z0-9-]+/games/[0-9-]+$"
                                     (lambda ()
                                       (base-league-page 'www-game-detail-page)))
            (create-regex-dispatcher "^/[a-zA-Z0-9-]+/api/games/[0-9-]+$"
                                     (lambda ()
                                       (base-league-page 'api-game-confirm)))
            (create-regex-dispatcher "^/[a-zA-Z0-9-]+/players$"
                                     (lambda ()
                                       (base-league-page 'www-player-list-page)))
            (create-regex-dispatcher "^/test-server-error$"
                                     (lambda ()
                                       (base-league-page
                                        'www-test-server-error
                                        :require-league? nil)))
            (create-regex-dispatcher "^/test-not-found$"
                                     (lambda ()
                                       (base-league-page
                                        'www-not-found-page
                                        :require-league? nil)))
            (create-regex-dispatcher "^/[a-zA-Z-]+/?$"
                                     (lambda ()
                                       (base-league-page
                                        'www-league-detail-page)))))
;;; Routes ------------------------------------------------------------------ END

;;; Base Page
(defun base-league-page (actual-page &key (require-league? t))
  (let* ((league (parse-league *request*))
         (me-query (get-parameter "me"))
         (perm-user-cookie (cookie-in "puser"))
         (temp-user-cookie (cookie-in "tuser"))
         (player-id 0)
         (given-auth "")
         (player nil))
    ;; TODO: remove following logging
    (log-message* :debug "=== ME-QUERY: ~A ===~%" me-query)
    (log-message* :debug "=== PERM-USER-COOKIE: ~A ===~%" perm-user-cookie)
    (log-message* :debug "=== TEMP-USER-COOKIE: ~A ===~%" temp-user-cookie)
    (when (not (empty? me-query))
      (setf player-id (subseq me-query 0 (position #\- me-query)))
      (setf given-auth (subseq me-query (1+ (or (position #\- me-query) 0))))
      (setf player (get-player :id player-id :temp-auth given-auth))
      (set-auth-cookie player))
    ;; Try to load player from long-lived cookie if player not yet found
    ;; TODO: following when clause is untested
    (when (and (null player) perm-user-cookie)
      (setf player-id
            (subseq perm-user-cookie 0 (position #\- perm-user-cookie)))
      (setf given-auth
            (subseq perm-user-cookie (1+ (or (position #\- perm-user-cookie)
                                             0))))
      (setf player (get-player :id player-id :perm-auth given-auth)))
    ;; Try to load player from short-lived cookie if player not yet found
    (when (and (null player) temp-user-cookie)
      (setf player-id
            (subseq temp-user-cookie 0 (position #\- temp-user-cookie)))
      (setf given-auth
            (subseq temp-user-cookie (1+ (or (position #\- temp-user-cookie)
                                             0))))
      (setf player (get-player :id player-id :temp-auth given-auth)))
    (cond ((and require-league? (null league))
           (www-not-found-page :player player))
          ((and require-league? (null player))
           (www-not-authorised-page))
          (t (funcall actual-page :player player :league league)))))
;;; Base Page --------------------------------------------------------------- END

;;; Template Page
(defmacro standard-page ((&key title page-id league player) &body body)
  "Creates a standard page layout.
   @param title
     Specifies the title of a page.
   @param page-id
     Specifies an id for the root element of the page. This is primarily
     intended to be used for CSS rules.
   @param body
     Contains the page body."
  `(with-html-output-to-string
       (*standard-output* nil :prologue t :indent t)
     (:html :lang "en"
            :id "root"
            :data-user (if ,player (player-id player))
            :data-league (if ,league (league-name league))
            (:head
             (:meta :charset "utf-8")
             (:meta :http-equiv "X-UA-Compatible"
                    :content "IE=edge")
             (:meta :name "viewport"
                    :content "width=device-width, initial-scale=1")
             (:title (fmt "~A - Hockey Oracle" ,title))
             (:link :rel "shortcut icon"
                    :href "/images/favicon.ico")
             (:link
              :href "/deps/fira/fira.css"
              :rel "stylesheet"
              :type "text/css")
             (:link
              :href "/deps/font-awesome/css/font-awesome.min.css"
              :rel "stylesheet"
              :type "text/css")
             (:link
              :href "/styles/main.css"
              :rel "stylesheet"
              :type "text/css")
             (:script :src "/deps/jquery/jquery-2.1.3.min.js")
             (:script :src "/deps/lodash/lodash.min.js")
             (:script :src "/scripts/utils.js")
             (:script :src "/scripts/main.js"))
            (:body
             (:div :id "overlay" "&nbsp;")
             (:div :id "top-shade")
             (:header :id "top-heading"
                      (:div :id "top-right-heading"
                            (if ,player
                                (htm
                                 (:a :href "/users/me"
                                     (esc (player-name ,player))))
                                (htm
                                 (:a :href "javascript:void(0)"
                                     :onclick "page.showLogin()"
                                     "Log in")))
                            (if ,league
                                (htm
                                 (:span " - ")
                                 (:a :href (sf "/~(~A~)"
                                               (league-name ,league))
                                     (esc (league-name ,league))))))
                      (:a :href "/"
                          (:img
                           :alt "logo"
                           :class "logo"
                           :src "/images/banner.jpg")
                          (:span :class "title" "Hockey Oracle")))
             (let ((path (script-name* *request*)))
               (htm
                (:nav
                 (:ul :class "nav-items"
                      (:li
                       (:a :href "/" (:i :class "fa fa-bars")))
                      (:li
                       (:a :class (if (based-on-path? path "leagues")
                                      "active"
                                      nil)
                           :href "/leagues" "Leagues"))
                      (if ,league
                          (htm
                           (:li
                            (:a :class (if (based-on-path? path "games")
                                           "active"
                                           nil)
                                :href (sf "/~A/games"
                                          (string-downcase (league-name ,league)))
                                "Games"))
                           (:li
                            (:a :class (if (based-on-path? path "players")
                                           "active"
                                           nil)
                                :href (sf "/~A/players"
                                          (string-downcase (league-name
                                                            ,league)))
                                "Players"))
                           (:li
                            (:a :class (if (based-on-path? path "about")
                                           "active"
                                           nil)
                                :href (sf "/~A/about"
                                          (string-downcase (league-name
                                                            ,league)))
                                "About"))
                           ))
                      (if (null ,league)
                          (htm (:li (:a :class (if (based-on-path? path
                                                                   "about")
                                                   "active"
                                                   nil)
                                        :href "/about" "About"))))))))
             (:section :id "login-dialog"
                       :class "dialog"
                       (:h2 "Welcome!")
                       (:p
                        (:input :id "login-user-name"
                                :class "full-width"
                                :onkeyup "onEnter(event, page.login)"
                                :placeholder "User name"
                                :title "User name"
                                :type "text"))
                       (:p
                        (:input :id "login-pwd"
                                :class "full-width"
                                :onkeyup "onEnter(event, page.login)"
                                :placeholder "Password"
                                :title "Password"
                                :type "password"))
                       (:p :id "login-result")
                       (:p
                        (:button :id "login-btn"
                                 :class "button wide-button"
                                 :onclick "page.login()"
                                 "Log In"))
                       (:p
                        (:a :id "forgot-pwd"
                            :href "javascript:void(0)"
                            :onclick "page.forgotPwd()"
                            :style "float:left"
                            "Forgot password")
                        (:a :href "javascript:void(0)"
                            :onclick "page.closeLogin()"
                            :style "float:right"
                            "Close")))
             (:main :id ,page-id
                    ,@body)))))
;;; Template Page ----------------------------------------------------------- END

;;; Error Pages
(defun www-not-found-page (&key player league)
  (setf (return-code*) +http-not-found+)
  (standard-page
      (:title "Not Found"
       :player player
       :league league
       :page-id "not-found-page")
    (:h2 "Not Found")
    (:p "The page or resource you requested could not be found.")
    (:a :href "/" "Go back to the home page")))

(defun www-not-authorised-page (&key player league)
  (setf (return-code*) +http-forbidden+)
  (standard-page
      (:title "Not Authorised"
       :player player
       :league league
       :page-id "not-authorised-page")
    (:h2 "Not Authorised")
    (:p "Sorry but you do not have permission to view the page or "
        "resource you requested.")
    (:a :href "/" "Go back to the home page")
    (if (null player)
        (htm
         (:p "Or")
         (:button :class "button wide-button"
                  :onclick "page.showLogin()"
                  "Log in")))))

(defmethod acceptor-status-message (acceptor (http-status-code (eql 404)) &key)
  (base-league-page #'www-not-found-page :require-league? nil))

(defun www-server-error-page (&key player league)
  (standard-page
   (:title "Server Error"
    :player player
    :league league
    :page-id "server-error-page")
   (:h2 "Server Error")
   (:p "Sorry, it looks like something unexpected happened on the server.")
   (:p "An administrator has been notified of the error.")
   (:a :href "/" "Go back to the home page")))

(defmethod acceptor-status-message (acceptor (http-status-code (eql 500)) &key)
  (bt:make-thread (lambda () (send-email "Server Error"
                                         "A <b>server error</b> occurred.")))
  (www-server-error-page nil))

(defun www-test-server-error (&key player league)
  (log-message* :error "Test error page \(error log level).")
  (log-message* :warning "Test error page \(warning log level).")
  (log-message* :info "Test error page \(info log level).")
  (error "This is an intentional error for testing purposes.")
  ;; The following should never be displayed
  (standard-page
      (:title "Test Server Error"
       :player player
       :league league)
   (:h2 "Test Server Error")))
;;; Error Pages ------------------------------------------------------------- END

;;; Home Page
(defun www-home-page (&key player league)
  (redirect "/leagues"))
;;; Home Page --------------------------------------------------------------- END

;;; About Page
(defun www-about-page (&key player league)
  (standard-page
   (:title "About"
    :player player
    :league league
    :page-id "about-page")
   (:p
    "The Hockey Oracle is a simple app that generates teams by randomly "
    "selecting from a pool of active players.")
   (:p
    (:span "Please note this is an")
    (:b "alpha")
    (:span "version of the website with very limited functionality."))
   (:table :class "brief-table"
           (:tr
            (:td "Version")
            (:td (fmt "~a" version)))
           (:tr
            (:td "Last Updated")
            (:td (fmt "~a" (pretty-time updated))))
           (:tr
            (:td "License")
            (:td
             (:a :href "https://www.gnu.org/licenses/gpl-2.0.html" "GPL v2")))
           (:tr
            (:td "Copyright")
            (:td "2014-2015 Thirushanth Thirunavukarasu")))))
;;; About Page -------------------------------------------------------------- END

;;; Login API
(defun api-login (&key player league)
  (sleep 2)
  (setf (content-type*) "application/json")
  (let* ((name (post-parameter "name"))
         (pwd (post-parameter "pwd"))
         (player nil))
    ;; Verify password provided by user is correct
    (setf player (get-player :name name :pwd pwd))
    (if (null player) ; Password incorrect
        (return-from api-login
          (json:encode-json-plist-to-string
           `(level :error message "Incorrect login..."))))
    (set-auth-cookie player :perm? t)
    (json:encode-json-plist-to-string
     `(level :success message "Login successful!"))))
;;; Login API --------------------------------------------------------------- END

;;; Reset Password Page
(defun www-reset-pwd (&key player league)
  (let* ((token (get-parameter "token"))
         (player-id (safe-parse-int (subseq token 0 (position #\- token))))
         (player (get-player :id player-id))
         (verified-token (if player (reset-pwd-get-token player))))
    (if (not (and player
                  (not (empty? verified-token))
                  (string-equal token verified-token)))
        (return-from www-reset-pwd
          (www-not-found-page :player player :league league)))
    (standard-page
        (:title "Reset Password"
         :player player
         :league league
         :page-id "reset-password-page")
      (:h2 "Please enter your new password")
      (:p
       (:input :id "pwd-new"
               :class "full-width"
               :onkeyup "onEnter(event, page.resetPwd)"
               :placeholder "New password"
               :title "New password"
               :type "password"))
      (:p
       (:input :id "pwd-new-repeat"
               :class "full-width"
               :onkeyup "onEnter(event, page.resetPwd)"
               :placeholder "Repeat new password"
               :title "Repeat new password"
               :type "password"))
      (:p :id "save-result")
      (:p
       (:button :id "save-btn"
                :class "button wide-button"
                :data-player-id player-id
                :data-reset-token (escape-string verified-token)
                :onclick "page.resetPwd()"
                "Save")))))
;;; Reset Password Page ----------------------------------------------------- END

;;; Reset Password API
(defun api-reset-pwd (&key player league)
  (sleep 2)
  (setf (content-type*) "application/json")
  (let* ((player-id (safe-parse-int (post-parameter "id")))
         (reset-token (post-parameter "resetToken"))
         (new-pwd (post-parameter "pwd"))
         (player (get-player :id player-id))
         (verified-token (if player (reset-pwd-get-token player)))
         (save-res nil))
    ;; Player not found:
    (if (null player)
        (return-from api-reset-pwd
          (json:encode-json-plist-to-string
           `(level :error message "Account not found."))))
    ;; Verify reset password token is still valid
    (if (or (empty? verified-token)
            (not (string-equal reset-token verified-token)))
        (return-from api-reset-pwd
          (json:encode-json-plist-to-string
           `(level :error message "Password reset period expired."))))
    (setf save-res (change-player-pwd player new-pwd))
    ;; Password update failed:
    (if (failed? save-res)
        (return-from api-reset-pwd
          (json:encode-json-plist-to-string
           `(level :error message "Failed to reset password."))))
    (setf player (r-data save-res))
    (set-auth-cookie player :perm? t)
    (json:encode-json-plist-to-string
     `(level :success
             message "Password succesfully updated!"))))
;;; Reset Password API ------------------------------------------------------ END

;;; Forgot Password API
(defun api-forgot-pwd (&key player league)
  (sleep 2)
  (setf (content-type*) "application/json")
  (let* ((name (post-parameter "name"))
         (player (get-player :name name))
         (reset-token ""))
    ;; User name not found:
    (if (null player)
        (return-from api-forgot-pwd
          (json:encode-json-plist-to-string
           `(level :error message "Account not found."))))
    (setf reset-token (reset-pwd-set-token player))
    ;; Reset attempt failed:
    (if (empty? reset-token)
        (return-from api-forgot-pwd
          (json:encode-json-plist-to-string
           `(level :error message "Failed to reset password."))))
    ;; Send email to reset password
    (send-email "Reset Password"
                (sf reset-pwd-msg (if *debug* "http" "https") (host) reset-token)
                (player-email player))
    ;; Report success
    (json:encode-json-plist-to-string
     `(level :success
             message "A link to reset your password was sent to your email."))))
;;; Forgot Password API ----------------------------------------------------- END

;;; User Detail Page
(defun www-user-detail-page (&key player league)
  (if (null player)
      (return-from www-user-detail-page
        (www-not-found-page :player player :league league)))
  (let ((leagues (get-all-leagues))
        (commissions '()))
    (dolist (l leagues)
      (if (find (player-id player) (league-commissioners l) :key #'player-id)
          (push l commissions)))
    (standard-page
        (:title "User"
         :player player
         :league league
         :page-id "user-detail-page")
      (:section :id "left-col" :class "col"
                (:p
                 (:img :id "user-img"
                       :class "full-width"
                       :src "/images/user.png")))
      (:section :id "right-col" :class "col"
                (:p
                 (:a :class "button"
                     :href "/logout"
                     :style "float:right" "Log out")
                 (:div :class "clear-fix"))
                (:p
                 (:input :id "player-name-edit"
                         :class "full-width"
                         :data-orig-val (escape-string (player-name player))
                         :placeholder "Name"
                         :title "Name"
                         :type "text"
                         :value (escape-string (player-name player))))
                (:p
                 (:input :id "player-email-edit"
                         :class "full-width"
                         :data-orig-val (escape-string (player-email player))
                         :placeholder "Email address"
                         :title "Email address"
                         :type "email"
                         :value (escape-string (player-email player))))
                (:br)
                (if (player-admin? player)
                    (htm
                     (:p :id "admin"
                         :title "You have site-wide adminstrator privileges"
                         (:i :class "fa fa-star")
                         (:span "Administrator"))))
                (if commissions
                    (htm
                     (:p :id "commissioner"
                         :title "You are a commissioner of these leagues"
                         (:i :class "fa fa-star")
                         (:span "Commissioner: ")
                         (dolist (l commissions)
                           (htm
                            (:a :href (sf "/~(~A~)" (league-name l))
                                (esc (league-name l)))
                            (:span :class "comma" ","))))))
                (:p
                 (:label
                  :title "Notify me immediately when the state of the upcoming game changes. E.g. when a player changes their status."
                  (:input :id "player-immediate-notify-edit"
                          :checked (player-notify-immediately? player)
                          :type "checkbox")
                  (:span "Immediate email notifications")))
                (:br)
                (:p
                 (:label
                  (:span "Default Position: ")
                  (:select :id "player-pos-edit"
                           :data-orig-val (escape-string (player-position player))
                           (dolist (pos players-positions)
                             (htm
                              (:option :selected
                                       (string-equal pos (player-position player))
                                       :value pos (esc pos)))))))
                (:br)
                (:p
                 (:button :id "change-pwd-btn"
                          :class "button wide-button"
                          :onclick "page.changePwd()"
                          "Change Password"))
                (:div :id "pwd-group"
                      :style "display:none"
                      (:p
                       (:input :id "pwd-curr"
                               :class "full-width"
                               :type "password"
                               :placeholder "Current password"
                               :title "Current password"))
                      (:p
                       (:input :id "pwd-new"
                               :class "full-width"
                               :type "password"
                               :placeholder "New password"
                               :title "New password"))
                      (:p
                       (:input :id "pwd-new-repeat"
                               :class "full-width"
                               :type "password"
                               :placeholder "Repeat new password"
                               :title "Repeat new password")))
                (:p
                 (:button :id "save-btn"
                          :class "button wide-button"
                          :onclick "page.saveUser()"
                          :style "display:none"
                          "Save"))
                (:p :id "save-result")))))
;;; User Detail Page -------------------------------------------------------- END

;;; User Save API
(defun api-user-save (&key player league)
  (setf (content-type*) "application/json")
  (let* ((name (post-parameter "name"))
         (email (post-parameter "email"))
         (notify-immediately?
           (string-equal "true" (post-parameter "notifyImmediately")))
         (pos (post-parameter "position"))
         (curr-pwd (post-parameter "currentPwd"))
         (new-pwd (post-parameter "newPwd"))
         (save-res nil))
    (setf (player-name player) name)
    (setf (player-email player) email)
    (setf (player-notify-immediately? player) notify-immediately?)
    (setf (player-position player) pos)
    (setf save-res (update-player player))
    ;; Basic player update failed or no password change attempted
    (if (or (failed? save-res) (empty? new-pwd))
        (return-from api-user-save
          (json:encode-json-plist-to-string
           `(level ,(r-level save-res)
                   message ,(r-message save-res)))))
    ;; Verify current password provided by user is correct
    (setf player (get-player :id (player-id player) :pwd curr-pwd))
    (if (null player) ; Current password incorrect
        (return-from api-user-save
          (json:encode-json-plist-to-string
           `(level :error message "Current password is incorrect."))))
    (setf save-res (change-player-pwd player new-pwd))
    (if (failed? save-res)
        (return-from api-user-save
          (json:encode-json-plist-to-string
           `(level ,(r-level save-res) message ,(r-message save-res)))))
    (setf player (r-data save-res))
    (set-auth-cookie player :perm? t)
    (json:encode-json-plist-to-string
     `(level :success message "Update successful!"))))
;;; User Save API ----------------------------------------------------------- END

;;; User Logout Page
(defun www-user-logout-page (&key player league)
  (remove-auth-cookies)
  (standard-page
      (:title "Log Out"
       :player nil
       :league league
       :page-id "user-logout-page")
    (:h2 "Thank you, come again!")))
;;; User Logout Page -------------------------------------------------------- END

;;; League List Page
(defun www-league-list-page (&key player league)
  (standard-page
   (:title "Leagues"
    :player player
    :league league
    :page-id "league-list-page")
   (:h2 "Choose your league:")
   (:ul :class "simple-list"
        (dolist (league (get-all-leagues))
          (htm
           (:li
            (:a :class "button wide-button"
                :href (string-downcase (league-name league))
                (esc (league-name league)))))))))
;;; League List Page -------------------------------------------------------- END

;;; League Detail Page
(defun www-league-detail-page (&key player league)
  (redirect (sf "/~A/games~A"
                (string-downcase (league-name league))
                (if (query-string*)
                    (sf "?~A" (query-string*)) ""))))
;;; League Detail Page ------------------------------------------------------ END

;;; Game List Page
(defun www-game-list-page (&key player league)
  (let* ((started-games (get-games league :exclude-unstarted t))
         (unstarted-games (get-games league :exclude-started t)))
    (standard-page
        (:title "Games"
         :player player
         :league league
         :page-id "game-list-page")
      (if (and (empty? started-games) (empty? unstarted-games))
          (htm (:div "No games have been created for this league."))
          (htm
           (:h2 :class "blue-heading" "Schedule")
           (:ul :class "data-list"
                (dolist (game unstarted-games)
                  (htm
                   (:li
                    (:a :class "game-date"
                        :href (sf "/~A/games/~A"
                                  (string-downcase (league-name league))
                                  (game-id game))
                        (esc (pretty-time (game-time game))))
                    (:span :class "game-state" "")
                    (:span :class "clear-fix")))))
           (:h2 :class "blue-heading" "Scores")
           (:ul :class "data-list"
                (dolist (game (reverse started-games))
                  (htm
                   (:li
                    (:div :class "game-date"
                          (:a
                           :href (sf "/~A/games/~A"
                                     (string-downcase (league-name league))
                                     (game-id game))
                           (esc (pretty-time (game-time game)))))
                    (:div :class "game-score"
                          (:div
                           (:img :class "team-logo"
                                 :src (sf "/images/team-logos/~A"
                                          (team-logo (game-away-team game))))
                           (:span :class "team-name"
                                  (esc (sf "~A"
                                           (team-name (game-away-team game)))))
                           (:span :class "score"
                                  (esc (sf "~A" (game-away-score game)))))
                          (:div
                           (:img :class "team-logo"
                                 :src (sf "/images/team-logos/~A"
                                          (team-logo (game-home-team game))))
                           (:span :class "team-name"
                                  (esc (sf "~A"
                                           (team-name (game-home-team game)))))
                           (:span :class "score"
                                  (esc (sf "~A" (game-home-score game))))))
                    (:div :class "clear-fix"))))))))))
;;; Game List Page ---------------------------------------------------------- END

;;; Game Detail Page
(defun www-game-detail-page (&key player league)
  (let* ((game-id (last1 (path-segments *request*)))
         (game (get-game league game-id))
         (player-gc (if game (or (game-confirm-for game player)
                                 (make-game-confirm
                                  :player player
                                  :confirm-type :no-response))))
         (confirm-qp (get-parameter "confirm"))
         (confirm-save-res (new-r :info))
         (show-confirm-inputs
           (and game
                (not (string-equal "final" (game-progress game))))))
    (if (null game)
        (www-not-found-page :player player :league league)
        (progn
          ;; Update player's confirmation status and reload game object, unless
          ;; game is in final state
          (when (and confirm-qp
                     (not (string-equal "final" (game-progress game))))
            (setf confirm-save-res
                  (save-game-confirm game player confirm-qp))
            (when (succeeded? confirm-save-res)
              (setf game (r-data confirm-save-res))
              (setf player-gc (game-confirm-for game player))))
          (standard-page
              (:title (fmt "Game on ~A" (pretty-time (game-time game)))
               :player player
               :league league
               :page-id "game-detail-page")
            (:div :id "game-info"
                  :data-game game-id
                  ;; Game Time (main heading)
                  (:h1 :id "time-status"
                       (:span (esc (pretty-time (game-time game))))
                       (if (not (empty? (game-progress game)))
                           (htm
                            (:span " - ")
                            (:span :class "uppercase"
                                   (esc (game-progress game)))))))
            ;; Player-Specific Game Confirmation
            (when show-confirm-inputs
              (htm
               (:section
                :id "confirm-inputs"
                (:b "Your current status for this game is:&nbsp;")
                (:select :id "game-confirm-opts"
                         :onchange "page.confirmTypeChanged(this)"
                         (doplist (ct-id ct-name confirm-types)
                           (htm
                            (:option :selected
                                     (string-equal ct-id
                                                   (game-confirm-confirm-type
                                                    player-gc))
                                     :value ct-id (esc ct-name)))))
                (:span :id "confirm-type-status"
                       (if (succeeded? confirm-save-res)
                           (htm
                            (:i :class
                                (sf "fa fa-check ~A"
                                    (string-downcase
                                     (r-level confirm-save-res)))
                                :title
                                (esc (r-message confirm-save-res))))
                           (htm
                            (:i :class
                                (sf "fa fa-exclamation-circle ~A"
                                    (string-downcase
                                     (r-level confirm-save-res)))
                                :title
                                (esc (r-message confirm-save-res))))))
                (:div :id "reason-input-group"
                      :class (if (string-equal :playing
                                               (game-confirm-confirm-type
                                                player-gc))
                                 "hidden")
                 (:textarea :id "reason-input"
                            :maxlength game-confirm-reason-max-length
                            :onchange "page.reasonTextChanged(this)"
                            :onkeyup "page.reasonTextChanged(this)"
                            :placeholder
                            (glu:str "Please enter why you&apos;re unable to "
                                     "play or are unsure")
                            (esc (game-confirm-reason player-gc)))
                 (:div :id "save-confirm-group"
                       (:div :id "reason-input-info"
                             (fmt "~A chars left"
                                  (- game-confirm-reason-max-length
                                      (length (game-confirm-reason
                                               player-gc)))))
                       (:button :class "button"
                                :onclick "page.saveConfirmInfo()"
                                "Update")
                       (:div :class "clear-fix"))))))
            ;; Edit Player Dialog
            (:div :id "edit-dialog" :class "dialog"
                  (:header "Editing Player")
                  (:section :class "content"
                            (:table
                             (:tr :class "input-row"
                                  (:td :class "label-col"
                                       (:label :for "player-name-edit" "Name: "))
                                  (:td :class "input-col"
                                       (:input :id "player-name-edit"
                                               :type "text")))
                             (:tr
                              (:td
                               (:label :for "player-pos-edit" "Position: "))
                              (:td
                               (:select :id "player-pos-edit"
                                        (dolist (pos players-positions)
                                          (htm
                                           (:option :value pos (esc pos)))))))
                             (:tr
                              (:td
                               (:label :for "player-active-edit" "Is Active: "))
                              (:td
                               (:input :id "player-active-edit"
                                       :type "checkbox"))))
                            (:div :class "actions"
                                  (:button
                                   :class "button save-btn"
                                   :data-player-id "0"
                                   :onclick "page.savePlayer()"
                                   "Save")
                                  (:button
                                   :class "button cancel-btn"
                                   :onclick
                                   "page.closeDialog(\"#edit-dialog\")"
                                   "Cancel"))))
            ;; Players Confirmed To Play
            (:section
             :id "confirmed-players-section"
             (:h2 :id "confirmed-heading-many"
                  :class "blue-heading"
                  :style (if (empty? (confirmed-players game)) "display:none")
                  (:span "Confirmed to play")
                  (:span :id "confirmed-count"
                          (fmt "(~A)" (length (confirmed-players game)))))
             (:h2 :id "confirmed-heading-zero"
                  :class "grey-heading"
                  :style (if (confirmed-players game) "display:none")
                         "No players confirmed to play")
             (:ul :class "template-player-item"
                  (:li :class "player-item"
                       (:span :class "player-name" "")
                       (:span :class "confirm-type" "&nbsp;")
                       (:span :class "confirm-btn-toggle"
                              (:button :class "button"
                                       :onclick "page.unconfirmPlayer(this)"
                                       :title "Move to \"Not playing\" section"
                                       (:i :class "fa fa-chevron-circle-down")))
                       (:select :class "player-position"
                                :onchange "page.positionChanged(this)"
                                (dolist (pos players-positions)
                                  (htm
                                   (:option :value pos
                                            :selected nil
                                            (esc pos)))))
                       (:span :class "confirm-info"
                              (:span :class "confirm-reason" "")
                              (:span :class "confirm-time"
                                     :title "Date confirmed"
                                     ""))
                       (:span :class "clear-fix")))
             (:ul :id "confirmed-players"
                  :class (if (confirmed-players game)
                             "data-list"
                             "data-list hidden")
                  (dolist (pc (confirmed-players game))
                    (htm
                     (:li :class "player-item"
                          :data-id (player-id (-> pc player))
                          :data-name (player-name (-> pc player))
                          :data-position (player-position (-> pc player))
                          :data-confirm-type (esc (sf "(~A)"
                                                      (getf
                                                       confirm-types
                                                       (game-confirm-confirm-type
                                                        pc))))
                          :data-reason (esc (game-confirm-reason pc))
                          :data-response-time (pretty-time
                                               (game-confirm-time pc)
                                               'short)
                          (:span :class "player-name"
                                 (esc (player-name (-> pc player))))
                          (:span :class "confirm-type" "&nbsp;")
                          (:span :class "confirm-btn-toggle"
                                 (:button :class "button"
                                          :onclick "page.unconfirmPlayer(this)"
                                          :title
                                          "Move to \"Not playing\" section"
                                          (:i :class
                                              "fa fa-chevron-circle-down")))
                          (:select :class "player-position"
                                   :onchange "page.positionChanged(this)"
                                   (dolist (pos players-positions)
                                     (htm
                                      (:option
                                       :value pos
                                       :selected (if (string-equal
                                                      pos
                                                      (player-position
                                                       (-> pc player)))
                                                     ""
                                                     nil)
                                       (esc pos)))))
                          (:span :class "confirm-info"
                                 (:span :class "confirm-reason" "")
                                 (:span :class "confirm-time"
                                        :title "Date confirmed"
                                        (esc (pretty-time
                                              (game-confirm-time pc)
                                              'short))))
                          (:span :class "clear-fix"))))))
            ;; Players Not Playing Or Unsure
            (:section
             :id "unconfirmed-players-section"
             (:h2 :id "unconfirmed-heading" :class "blue-heading"
                  "Not playing or undecided"
                  (:span :id "unconfirmed-count"
                         (fmt "(~A)" (length (unconfirmed-players game)))))
             (:ul :class "template-player-item"
                  (:li :class "player-item"
                       (:span :class "player-name" "")
                       (:span :class "confirm-type" "&nbsp;")
                       (:span :class "confirm-btn-toggle"
                              (:button :class "button"
                                       :onclick "page.confirmPlayer(this)"
                                       :title "Move to \"Confirmed\" section"
                                       (:i :class "fa fa-chevron-circle-up")))
                       (:span :class "player-position" "&nbsp;")
                       (:span :class "confirm-info"
                              (:span :class "confirm-reason" "")
                              (:span :class "confirm-time"
                                     :title "Date confirmed"
                                     ""))
                       (:span :class "clear-fix")))
             (:ul :id "unconfirmed-players"
                  :class (if (unconfirmed-players game)
                             "data-list"
                             "data-list hidden")
                  (dolist (pc (unconfirmed-players game))
                    (htm
                     (:li :class "player-item"
                          :data-id (player-id (-> pc player))
                          :data-name (player-name (-> pc player))
                          :data-position (player-position (-> pc player))
                          :data-confirm-type (esc (sf "(~A)"
                                                      (getf
                                                       confirm-types
                                                       (game-confirm-confirm-type
                                                        pc))))
                          :data-reason (esc (game-confirm-reason pc))
                          :data-response-time (pretty-time
                                               (game-confirm-time pc) 'short)
                          (:span :class "player-name"
                                 (esc (player-name (-> pc player))))
                          (:span :class "confirm-type"
                                 (esc (sf "(~A)"
                                          (getf confirm-types
                                                (game-confirm-confirm-type pc)))))
                          (:span :class "confirm-btn-toggle"
                                 (:button :class "button"
                                          :onclick "page.confirmPlayer(this)"
                                          :title "Move to \"Confirmed\" section"
                                          (:i :class "fa fa-chevron-circle-up")))
                          (:span :class "player-position"
                                 (esc (player-position (-> pc player))))
                          (:span :class "confirm-reason"
                                 (esc (game-confirm-reason pc)))
                          (:span :class "confirm-time"
                                 :title "Date confirmed"
                                 (esc (pretty-time
                                       (game-confirm-time pc)
                                       'short)))
                          (:span :class "clear-fix"))))))
            ;; Random Teams
            (:section :id "random-teams"
                      (:ul :class "template-player-item"
                           (:li :class "player-item"
                                (:span :class "player-name")
                                (:span :class "player-position")
                                (:span :class "clear-fix")))
                      ; TODO: Remove hard-coded team logos
                      (:div :id "team1" :class "team"
                            (:img :class "team-logo"
                                  :src "/images/team-logos/cripplers.png")
                            (:h2 :class "team-heading" "Cripplers")
                            (:ul :class "team-players data-list"))
                      (:div :id "team2" :class "team"
                            (:img :class "team-logo"
                                  :src "/images/team-logos/panthers.png")
                            (:h2 :class "team-heading" "Panthers")
                            (:ul :class "team-players data-list")))
            (:br)
            (:button :id "make-teams"
                     :class (if (confirmed-players game)
                                "button wide-button"
                                "button wide-button hidden")
                     :onclick "page.makeTeams()"
                     :title "Generate random teams"
                     (:i :class "fa fa-random")
                     (:span :class "button-text" "Make Teams"))
            (:button :id "add-player"
                     :class "button wide-button"
                     :onclick "page.addPlayer()"
                     (:i :class "fa fa-user-plus")
                     (:span :class "button-text" "Add Player"))
            (:button :id "pick-players"
                     :class "button wide-button"
                     :onclick "page.pickPlayers()"
                     :title "Choose players"
                     (:i :class "fa fa-check-circle-o")
                     (:span :class "button-text" "Pick Players")))))))
;;; Game Detail Page -------------------------------------------------------- END

;;; Game Confirm API
(defun api-game-confirm (&key player league)
  (setf (content-type*) "application/json")
  (let* ((game-id (last1 (path-segments *request*)))
         (game (get-game league game-id))
         (confirm-type (post-parameter "confirmType"))
         (reason (post-parameter "reason"))
         (save-res))
    (when confirm-type
      (setf save-res
            (save-game-confirm game player confirm-type reason))
      (json:encode-json-plist-to-string
       (if (succeeded? save-res)
           `(level :success
                   message "Confirmation updated!"
                   data ,(game-confirm-reason
                          (game-confirm-for (r-data save-res) player)))
           `(level ,(r-level save-res)
                   message ,(r-message save-res)
                   data nil))))))
;;; Game Confirm API -------------------------------------------------------- END

;;; Player List Page
(defun www-player-list-page (&key player league)
  (standard-page
      (:title "Players"
       :player player
       :league league
       :page-id "player-list-page")
    (:h2 :class "blue-heading"
         "Players")
    (:ul :id "all-players" :class "data-list"
         (dolist (p (get-players league))
           (htm
            (:li :class "player-item"
                 :data-id (player-id p)
                 :data-name (player-name p)
                 :data-position (player-position p)
                 (:span :class "player-name"
                        (esc (player-name p)))
                 (:span :class "action-buttons"
                        (:button :class "button"
                                 :onclick "page.editPlayer(this, \"#all-players\")"
                                 (:i :class "fa fa-pencil-square-o")))
                 (:span :class "player-position" (esc (player-position p)))
                 (:span :class "clear-fix")))))
    (:br)
    (:button :id "add-player"
             :class "button wide-button"
             :onclick "page.addPlayer()"
             (:i :class "fa fa-user-plus")
             (:span :class "button-text" "Add Player"))
    (:div :class "template-items"
          (:ul :class "template-player-item"
               (:li :class "player-item"
                    (:span :class "player-name" "")
                    (:span :class "action-buttons"
                           (:button :class "button"
                                    :onclick "page.editPlayer(this, \"#all-players\")"
                                    (:i :class "fa fa-pencil-square-o")))
                    (:span :class "player-position" "&nbsp;")
                    (:span :class "clear-fix"))))
    (:div :id "edit-dialog" :class "dialog"
          (:header "Editing Player")
          (:section :class "content"
                    (:table
                     (:tr :class "input-row"
                          (:td :class "label-col"
                               (:label :for "player-name-edit" "Name: "))
                          (:td :class "input-col"
                               (:input :id "player-name-edit"
                                       :type "text")))
                     (:tr
                      (:td
                       (:label :for "player-pos-edit" "Position: "))
                      (:td
                       (:select :id "player-pos-edit"
                                (dolist (pos players-positions)
                                  (htm
                                   (:option :selected t
                                            :value pos (esc pos)))))))
                     (:tr
                      (:td
                       (:label :for "player-active-edit" "Is Active: "))
                      (:td
                       (:input :id "player-active-edit"
                               :checked t
                               :type "checkbox"))))
                    (:div :class "actions"
                          (:button
                           :class "button save-btn"
                           :data-player-id "0"
                           :onclick "page.savePlayer(\"#all-players\", \".template-player-item .player-item\")"
                           "Save")
                          (:button
                           :class "button cancel-btn"
                           :onclick
                           "page.closeDialog(\"#edit-dialog\")"
                           "Cancel"))))))
;;; Player List Page -------------------------------------------------------- END
