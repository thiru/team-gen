(in-package :hockey-oracle.web)

(defvar web-app nil "Contains the web-server instance")

(defun create-server (port)
  "Creates the web server on the specified port."
  (let* ((root-dir (asdf:system-relative-pathname :hockey-oracle "public/"))
         (web-app (make-instance
                    'easy-acceptor
                    :port port
                    :document-root root-dir
                    :access-log-destination "~/tbnl-access.log"
                    :message-log-destination "~/tbnl-message.log")))
    web-app))

(defun start-server! (&key (port 9090) debug)
  "Starts the web server.
   @param port:
     Specifies the port for the web server.
   @param debug:
     If T, the server is started with access and message logs sent to standard
     out, and the following hunchentoot special variable settings:
     * *CATCH-ERRORS-P* => NIL
     * *SHOW-LISP-ERRORS-P* => T
   Side-effects: sets the special variable web-app to the created acceptor."
  (setf web-app (create-server port))
  (when debug
    (setf *catch-errors-p* nil)
    (setf *show-lisp-errors-p* t)
    (setf (acceptor-access-log-destination web-app) *standard-output*)
    (setf (acceptor-message-log-destination web-app) *standard-output*))
  (start web-app))


(defun stop-server ()
  "Stops the web server referenced by the special variable web-app."
  (if web-app
    (stop web-app :soft t)))

(defmacro standard-page ((&key title page-id) &body body)
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
      (:head
        (:meta :charset "utf-8")
        (:meta :http-equiv "X-UA-Compatible"
               :content "IE=edge")
        (:meta :name "viewport"
               :content "width=device-width, initial-scale=1")
        (:title ,(format nil "~a - Hockey Oracle" title))
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
          (:a :href "/"
            (:img
              :alt "logo"
              :class "logo"
              :src "/images/banner.jpg")
            (:span :class "title" "Hockey Oracle")))
        (:nav
          (:ul :class "nav-items"
            (:li
              (:a :href "/players" "Players"))
            (:li
              (:a :href "/about" "About"))
            ))
        (:main :id ,page-id
          ,@body)))))

(defmethod acceptor-status-message (acceptor (http-status-code (eql 404)) &key)
  (standard-page
    (:title "Not Found" :page-id "not-found-page")
    (:h2 "Not Found")
    (:p "The page or resource you requested could not be found.")
    (:a :href "/" "Go back to the home page")))

(defmethod acceptor-status-message (acceptor (http-status-code (eql 500)) &key)
  (bt:make-thread (lambda () (send-error-email "A <b>server</b> error occurred.")))
  (standard-page
    (:title "Server Error" :page-id "server-error-page")
    (:h2 "Server Error")
    (:p "Sorry, it looks like something unexpected happened on the server.")
    (:p "An administrator has been notified of the error.")
    (:a :href "/" "Go back to the home page")))

(defun send-error-email (message)
  "Sends an email indicating a server error occurred."
  (let ((auth '()))
    (push (get-secure-key "ho/email/pwd") auth)
    (push (get-secure-key "ho/email/username") auth)
    (cl-smtp:send-email (get-secure-key "ho/email/server")
                        (get-secure-key "ho/email/reply-to")
                        (get-secure-key "ho/email/admins")
                        "Server Error" ""
                        :display-name "Hockey Oracle"
                        :html-message message :ssl :tls
                        :port (parse-integer
                               (get-secure-key "ho/email/ssl-port"))
                        :authentication auth)))

(define-easy-handler (www-test-server-error :uri "/test-server-error") ()
  (log-message* :error "Test error page \(error log level).")
  (log-message* :warning "Test error page \(warning log level).")
  (log-message* :info "Test error page \(info log level).")
  (error "This is an intentional error for testing purposes.")
  ; The following should never be displayed
  (standard-page
    (:title "Test Server Error")
    (:h2 "Test Server Error")))

(define-easy-handler (www-home :uri "/") ()
  (redirect "/players"))

(define-easy-handler (www-players :uri "/players") ()
  (standard-page
    (:title "Players"
     :page-id "player-list-page")
    (:div :id "edit-dialog" :class "dialog"
      (:header "Editing Player")
      (:section :class "content"
        (:table
          (:tr :class "input-row"
            (:td :class "label-col"
              (:label :for "player-name-edit" "Name: "))
            (:td :class "input-col"
              (:input :id "player-name-edit" :type "text")))
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
              (:input :id "player-active-edit" :type "checkbox"))))
        (:div :class "actions"
          (:button
            :class "save-btn"
            :data-player-id "0"
            :onclick "savePlayer()"
            "Save")
          (:button
            :class "cancel-btn"
            :onclick "closeDialog()"
            "Cancel"))))
    (:table :id "player-list" :class "data-table"
      (:thead
        (:tr
          (:th :class "name-col" "Player")
          (:th :class "position-col" :title "Position" "Pos")
          (:th :class "actions-col" "")))
      (:tbody
        (dolist (p (players-get-all))
          (htm
            (:tr :class "player-item" :data-player-id (player-id p)
              ; This indicates the player's initial active status. I.e. it may
              ; change on the client.
              :data-player-active (player-active? p)
              (:td
                :class "player-name-col"
                :onclick "togglePlayerActive(this)"
                (:i :class "player-check fa fa-circle-o"
                    :title "When checked the player is considered active/able to play")
                (:span :class "player-name"
                  (esc (fmt "~a ~a" (player-first-name p) (player-last-name p)))))
              (:td
               (:select :class "player-position"
                        (dolist (pos players-positions)
                          (htm
                           (:option
                            :value pos
                            :selected (if (string-equal pos (player-position p)) "" nil)
                            (esc pos))))))
              (:td :class "action-buttons"
                (:button
                  :href "javascript:void(0)"
                  :onclick "editPlayer(this)"
                  (:i :class "fa fa-pencil-square-o"))))))))
    (:section :id "random-teams"
      (:table :id "team1" :class "team data-table"
        (:thead
          (:tr :class "team-heading"
           (:th :class "team-name"
              "Cripplers")
           (:th
             (:img :class "team-logo" :src "/images/team-logos/cripplers.png"))))
        (:tbody :class "team-players"))
      (:table :id "team2" :class "team data-table"
        (:thead
          (:tr :class "team-heading"
           (:th :class "team-name"
              "Panthers")
           (:th
             (:img :class "team-logo" :src "/images/team-logos/panthers.png"))))
        (:tbody :class "team-players")))
    (:button :id "make-teams"
      :class "wide-button"
      :href "javascript:void(0)"
      :onclick "makeTeams()"
      :title "Select to generate random teams"
      (:i :class "fa fa-random")
      (:span :class "button-text" "Make Teams"))
    (:button :id "add-player"
      :class "wide-button"
      :href "javascript:void(0)"
      :onclick "addPlayer()"
      (:i :class "fa fa-user-plus")
      (:span :class "button-text" "Add Player"))
    (:button :id "pick-players"
      :class "wide-button"
      :href "javascript:void(0)"
      :onclick "pickPlayers()"
      :title "Select to choose active players"
      (:i :class "fa fa-check-circle-o")
      (:span :class "button-text" "Pick Players"))))

(define-easy-handler (www-about :uri "/about") ()
  (standard-page
    (:title "About"
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
        (:td (fmt "~a" app-version)))
      (:tr
        (:td "Last Updated")
        (:td (fmt "~a" app-updated)))
      (:tr
        (:td "License")
        (:td
          (:a :href "https://www.gnu.org/licenses/gpl-2.0.html" "GPL v2")))
      (:tr
        (:td "Copyright")
        (:td "2014-2015 Thirushanth Thirunavukarasu")))))
