;;;; Core domain.

(in-package :hockey-oracle.core)

;;; Global Variables
(defvar *the-random-state* (make-random-state t))
;;; Global Variables -------------------------------------------------------- END

;;; Utils
(defun first1 (obj)
  "Gets the first item in OBJ if it's a list, otherwise OBJ is simply returned."
  (if (listp obj) (first obj) obj))

(defun second1 (obj &optional fallback)
  "Gets the second item in OBJ if it's a list of at least two items, otherwise
   FALLBACK."
  (cond ((atom obj)
         fallback)
        ((and (listp obj) (> (length obj) 1))
         (second obj))
        (t fallback)))

(defun third1 (obj &optional fallback)
  "Gets the third item in OBJ if it's a list of at least three items, otherwise
   FALLBACK."
  (cond ((atom obj)
         fallback)
        ((and (listp obj) (> (length obj) 2))
         (third obj))
        (t fallback)))

(defun get-secure-key (key)
  "Gets a secure key by calling the 'pass' program."
  (uiop:run-program (sf "pass ~A" key) :output '(:string :stripped t)))

(defun parse-id (key &key idx)
  "Parses an integer id from a redis key. If IDX is non-null it specifies the
   index to retrieve the id from, after the key has been split by colons. If
   IDX is null the last segment of the key is returned."
  (let* ((key-segs (split-sequence #\: key)))
    (if (null idx)
        (parse-integer (last1 key-segs))
        (parse-integer (nth idx key-segs)))))

(defun read-code (string)
  "Read in STRING as source code, without complaining about empty/nil strings."
  (if (empty? string)
      nil
      (read-from-string string)))

(defun to-bool (redis-val)
  "Converts the given redis value to a bool."
  (plusp (parse-integer redis-val)))

;; Based on hunchentoot/hunchentools
(defun random-string (&optional (n 32) (base 36))
  "Return a random number \(as a string) with N digits and base BASE."
  (with-output-to-string (s)
    (dotimes (i n)
      (format s "~VR" base
              (random base *the-random-state*)))))

(defun gen-hash (str)
  "Generate a hash of STR."
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha512
                             (ironclad:ascii-string-to-byte-array str))))
;;; Utils ------------------------------------------------------------------- END

;;; Leagues
(defstruct league
  "Defines a hockey league.
   * ID: unique identifier
   * NAME: unique name
   * CREATED: date/time created
   * ACTIVE?: whether it is active/visible"
  (id 0)
  (name "")
  (created "")
  (active? t))

(defun get-all-leagues ()
  "Gets a list of all LEAGUE's sorted by name (A -> Z)."
  ;; TODO: Use (red-scan) instead of (red-keys) to get player keys
  ;; TODO: Use pipelines to send multiple commands at once
  (redis:with-persistent-connection ()
    (let* ((league-keys (red-keys "league:*"))
           (leagues nil))
      (dolist (league-key league-keys)
        (push (new-league-from-db league-key) leagues))
      (sort leagues #'string< :key #'league-name))))

(defun get-league (&key id name)
  "Get a LEAGUE by id or name."
  (if (and (null id) (empty? name))
      nil
      (let* ((leagues (get-all-leagues)))
        (if (not (empty? name))
            (find name leagues :test #'string-equal :key #'league-name)
            (find id leagues :test #'= :key #'league-id)))))

(defun new-league-from-db (league-key)
  "Create a LEAGUE struct from the given redis key."
  (let ((id (parse-id league-key)))
    (make-league :id id
                 :name (red-hget league-key "name")
                 :created (red-hget league-key "created")
                 :active? (to-bool (red-hget league-key "active?")))))
;;; Leagues ----------------------------------------------------------------- END

;;; Teams
(defstruct team
  "Defines a hockey team."
  (id 0)
  (name "")
  (logo ""))

(defun get-teams (league)
  "Gets teams belonging to the given LEAGUE."
  (check-type league LEAGUE)
  (if league
      (redis:with-persistent-connection ()
        (let* ((team-ids (red-smembers (sf "leagues:~A:teams" (-> league id))))
               (teams '()))
          (dolist (team-id team-ids)
            (push (new-team-from-db (sf "team:~A" team-id)) teams))
          (sort teams #'string< :key #'team-name)))))

(defun get-team (id)
  "Get TEAM with the given id."
  (if id
      (let ((key (sf "team:~A" id)))
        (redis:with-persistent-connection ()
          (if (red-exists key)
              (new-team-from-db (sf "team:~A" id)))))))

(defun new-team-from-db (team-key)
  "Create a TEAM struct from the given redis key."
  (let ((id (parse-id team-key)))
    (make-team :id id
               :name (red-hget team-key "name")
               :logo (red-hget team-key "logo"))))
;;; Teams ------------------------------------------------------------------- END

;;; Games
(defstruct game
  "Describes a hockey game.
   * TIME: date/time of the game
     * This also acts as a unique identifier within the scope of a league
   * PROGRESS: is the state of the game, and one of:
     * NIL (not yet started)
     * IN-PROGRESS
     * FINAL
   * CONFIRMS: list of GAME-CONFIRM structs"
  (id 0)
  (league nil)
  (time nil)
  (progress nil)
  (home-team nil)
  (away-team nil)
  (home-score 0)
  (away-score 0)
  (confirms '()))

(defun confirmed-players (game)
  "Gets PLAYER's confirmed to play for the given GAME as a list of GAME-CONFIRM
   structs."
  (sort (remove-if (complement (lambda (x)
                                 (string-equal 'Playing (-> x confirm-type))))
                   (-> game confirms))
        #'string<
        :key (lambda (x) (player-name (game-confirm-player x)))))

(defun unconfirmed-players (game)
  "Gets PLAYER's that have not confirmed, are not able to play, or are unsure of
   being able to player for the given game, as a list of GAME-CONFIRM structs."
  (let* ((unconfirmed (remove-if (lambda (x) (string-equal "Playing"
                                                           (-> x confirm-type)))
                                 (-> game confirms))))
    (dolist (p (get-players (game-league game)))
      (unless (find (player-id p) (-> game confirms)
                    :key (lambda (x) (player-id (game-confirm-player x))))
        (push (make-game-confirm :player p
                                 :confirm-type "No response")
              unconfirmed)))
    (sort unconfirmed
          #'string<
          :key (lambda (x) (player-name (game-confirm-player x))))))

(defstruct game-confirm
  "Describes the confirmation state of a player for a game.
   * PLAYER: the respective PLAYER
   * TIME: when the PLAYER made a response
   * CONFIRM-TYPE:
     * Playing
     * Can't play
     * Maybe
     * No response
   * REASON: typically a description of why a player is unable/unsure of
     playing"
  (player nil)
  (time "")
  (confirm-type nil)
  (reason ""))

(defun get-games (league &key exclude-started exclude-unstarted)
  "Get all GAME's belonging to the given LEAGUE."
  (if league
      (redis:with-persistent-connection ()
        (let* ((game-keys (red-keys (sf "leagues:~A:games:*" (-> league id))))
               (games '()))
          (dolist (game-key game-keys)
            (let ((game (new-game-from-db game-key league)))
              (cond (exclude-started
                     (if (empty? (game-progress game))
                         (push game games)))
                    (exclude-unstarted
                     (if (not (empty? (game-progress game)))
                         (push game games)))
                    (t (push game games)))))
          (sort games #'string< :key #'game-time)))))

(defun get-game (league game-id)
  "Get the GAME with the given LEAGUE and GAME-ID."
  (if (or (empty? league) (null game-id))
      nil
      (redis:with-persistent-connection ()
        (let* ((game-key (sf "leagues:~A:games:~A"
                             (-> league id)
                             game-id)))
          (if (redis:red-exists game-key)
              (new-game-from-db game-key league))))))

(defun new-game-from-db (game-key league)
  "Create a GAME struct based on the given redis key."
  (let ((id (parse-id game-key)))
    (make-game :id id
               :league league
               :time (red-hget game-key "time")
               :progress (red-hget game-key "progress")
               :home-team (new-team-from-db (sf "team:~A"
                                                (red-hget game-key
                                                          "home-team")))
               :away-team (new-team-from-db (sf "team:~A"
                                                (red-hget game-key
                                                          "away-team")))
               :home-score (parse-integer (red-hget game-key "home-score"))
               :away-score (parse-integer (red-hget game-key "away-score"))
               :confirms (new-game-confirm
                          (read-code (red-hget game-key "confirms"))))))

(defun new-game-confirm (plist)
  "The key of PLIST is expected to be a player id and the value a list of the
   form: (CONFIRM-TYPE TIME REASON). REASON is optional."
  (let ((game-confirms '()))
    (doplist (player-id confirm-info plist)
             (push (make-game-confirm :player (get-player player-id)
                                      :confirm-type (first1 confirm-info)
                                      :time (second1 confirm-info "")
                                      :reason (third1 confirm-info ""))
                   game-confirms))
    game-confirms))
;;; Games ------------------------------------------------------------------- END

;;; Players
(defstruct player
  "Describes a player/user.
   * ID: unique identifier (across all leagues)
   * NAME: his/her name
   * AUTH: current authentication token
   * POSITION: default position
   * ACTIVE?: whether active/able to play"
  (id 0)
  (name "")
  (auth "")
  (position "")
  (active? t))

(defparameter players-positions '("C" "D" "G" "LW" "RW"))

(defun get-all-players ()
  "Gets a list of all PLAYER's sorted by first name."
  ;; TODO: Use (red-scan) instead of (red-keys) to get player keys
  ;; TODO: Use pipelines to send multiple commands at once
  (redis:with-persistent-connection ()
    (let* ((player-keys (red-keys "player:*"))
           (players nil))
      (dolist (player-key player-keys)
        (push (new-player-from-db player-key) players))
      (sort players #'string< :key #'player-name))))

(defun get-players (league)
  "Gets a list of all PLAYER's belonging the given LEAGUE, sorted by first name."
  ;; TODO: Use (red-scan) instead of (red-keys) to get player keys
  ;; TODO: Use pipelines to send multiple commands at once
  (if league
      (redis:with-persistent-connection ()
        (let* ((player-ids (red-smembers (sf "leagues:players:~A"
                                             (league-id league))))
               (players '()))
          (dolist (player-id player-ids)
            (push (new-player-from-db (sf "player:~A" player-id)) players))
          (sort players #'string< :key #'player-name)))))

(defun get-player (id)
  "Gets the PLAYER with the given id."
  (if id
      (redis:with-persistent-connection ()
        (new-player-from-db (sf "player:~A" id)))))

(defun get-auth-player (auth-token)
  "Gets the PLAYER with the given authentication token (if any)."
  (redis:with-persistent-connection ()
    (get-player (red-hget "auths" auth-token))))

; TODO: Wrap DB updates in transaction
(defun reset-player-auth (player)
  "Reset the authentication token of PLAYER.
   RETURNS:
   * The new auth token
   * The random string that was hashed to generate the auth token"
  (check-type player PLAYER)
  (if player
      (let* ((rnd-str (random-string))
             (new-auth (gen-hash rnd-str))
             (player-key (sf "player:~A" (player-id player))))
        (redis:with-persistent-connection ()
          (when (red-exists player-key)
            (red-hset player-key "auth" new-auth)
            (red-hdel "auths" (player-auth player))
            (red-hset "auths" new-auth (player-id player))
            (values new-auth rnd-str))))))

(defun new-player-from-db (player-key)
  "Create a PLAYER struct from the given redis key."
  (let ((id (parse-id player-key)))
    (make-player :id id
                 :name (red-hget player-key "name")
                 :auth (red-hget player-key "auth")
                 :position (red-hget player-key "position")
                 :active? (red-sismember "players:active" id))))
;;; Players ----------------------------------------------------------------- END
