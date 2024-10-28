;; DreamVault: Decentralized Dream Journal
;; A privacy-focused platform for storing and sharing dreams

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-invalid-dream (err u101))
(define-constant err-invalid-time (err u102))
(define-constant err-entry-not-found (err u103))
(define-constant err-index-full (err u104))
(define-constant err-invalid-tag (err u105))
(define-constant err-invalid-user (err u106))
(define-constant err-not-in-pool (err u107))
(define-constant err-already-unlocked (err u108))

;; Data Types
(define-map dreams
    { dream-id: uint, owner: principal }
    {
        content: (string-utf8 2048),
        timestamp: uint,
        unlock-time: uint,
        is-private: bool,
        is-anonymous: bool,
        tags: (list 10 (string-utf8 32))
    }
)

;; New map for anonymous dream pool
(define-map anonymous-pool
    uint  ;; dream-id
    {
        owner: principal,
        is-unlocked: bool,
        unlock-block: uint
    }
)

(define-map dream-counts principal uint)
(define-map tag-index { tag: (string-utf8 32) } (list 50 { dream-id: uint, owner: principal }))
(define-data-var anonymous-pool-counter uint u0)

;; Private Functions
(define-private (is-owner (dream-id uint))
    (match (map-get? dreams {dream-id: dream-id, owner: tx-sender})
        entry true
        false)
)

(define-private (get-dream-count-internal (user principal))
    (default-to u0 (map-get? dream-counts user))
)

(define-private (validate-tag (tag (string-utf8 32)))
    (and (> (len tag) u0) (<= (len tag) u32))
)

(define-private (validate-tag-list (tag (string-utf8 32)) (valid bool))
    (and valid (validate-tag tag))
)

(define-private (validate-tags (tags (list 10 (string-utf8 32))))
    (and 
        (<= (len tags) u10)
        (fold validate-tag-list tags true)
    )
)

(define-private (validate-user (user principal))
    (is-some (map-get? dream-counts user))
)

(define-private (validate-bool (value bool))
    true
)

;; New function to generate pseudo-random unlock time
(define-private (generate-unlock-time)
    (let (
        (current-block block-height)
        (random-blocks (mod (var-get anonymous-pool-counter) u144))  ;; ~24 hours in blocks
    )
        (+ current-block (+ u72 random-blocks))  ;; Minimum 12 hours + random time
    )
)

;; Public Functions
(define-public (add-dream (content (string-utf8 2048)) 
                         (unlock-time uint) 
                         (is-private bool)
                         (is-anonymous bool)
                         (tags (list 10 (string-utf8 32))))
    (let (
        (dream-id (get-dream-count-internal tx-sender))
        (validated-private (validate-bool is-private))
        (validated-anonymous (validate-bool is-anonymous))
    )
        (begin
            (asserts! (> (len content) u0) err-invalid-dream)
            (asserts! (>= unlock-time block-height) err-invalid-time)
            (asserts! (validate-tags tags) err-invalid-tag)
            (asserts! validated-private err-not-authorized)
            (asserts! validated-anonymous err-not-authorized)
            
            (map-set dreams
                { dream-id: dream-id, owner: tx-sender }
                {
                    content: content,
                    timestamp: block-height,
                    unlock-time: unlock-time,
                    is-private: is-private,
                    is-anonymous: is-anonymous,
                    tags: tags
                }
            )
            
            (map-set dream-counts 
                tx-sender 
                (+ dream-id u1))
            
            ;; If anonymous, add to anonymous pool
            (if is-anonymous
                (begin
                    (map-set anonymous-pool
                        dream-id
                        {
                            owner: tx-sender,
                            is-unlocked: false,
                            unlock-block: (generate-unlock-time)
                        }
                    )
                    (var-set anonymous-pool-counter (+ (var-get anonymous-pool-counter) u1))
                    (ok dream-id)
                )
                (ok dream-id)
            )
        )
    )
)

(define-public (read-dream (dream-id uint) (owner principal))
    (let (
        (entry (unwrap! (map-get? dreams {dream-id: dream-id, owner: owner}) 
                         err-entry-not-found))
        (anonymous-entry (map-get? anonymous-pool dream-id))
    )
        (begin
            (asserts! (or
                (is-eq tx-sender owner)
                (and
                    (not (get is-private entry))
                    (or
                        (>= block-height (get unlock-time entry))
                        (and
                            (is-some anonymous-entry)
                            (get is-unlocked (unwrap! anonymous-entry err-not-in-pool))
                        )
                    )
                )
            ) err-not-authorized)
            
            (ok {
                content: (get content entry),
                timestamp: (get timestamp entry),
                tags: (get tags entry),
                anonymous: (get is-anonymous entry)
            })
        )
    )
)

(define-public (update-privacy (dream-id uint) 
                             (is-private bool)
                             (is-anonymous bool))
    (let ((entry (unwrap! (map-get? dreams 
                                   {dream-id: dream-id, owner: tx-sender})
                         err-entry-not-found)))
        (begin
            (asserts! (is-owner dream-id) err-not-authorized)
            (asserts! (validate-bool is-private) err-not-authorized)
            (asserts! (validate-bool is-anonymous) err-not-authorized)
            
            (map-set dreams
                { dream-id: dream-id, owner: tx-sender }
                (merge entry {
                    is-private: is-private,
                    is-anonymous: is-anonymous
                })
            )
            (ok true)
        )
    )
)

;; New function to check if anonymous dream is unlocked
(define-public (check-anonymous-dream-status (dream-id uint))
    (let ((entry (unwrap! (map-get? anonymous-pool dream-id) err-not-in-pool)))
        (begin
            (if (and
                    (not (get is-unlocked entry))
                    (>= block-height (get unlock-block entry))
                )
                (begin
                    (map-set anonymous-pool
                        dream-id
                        (merge entry { is-unlocked: true })
                    )
                    (ok true)
                )
                (ok false)
            )
        )
    )
)

(define-public (get-dream-count (user principal))
    (begin
        (asserts! (validate-user user) err-invalid-user)
        (ok (get-dream-count-internal user))
    )
)

(define-public (get-public-dreams-by-tag (tag (string-utf8 32)))
    (begin
        (asserts! (validate-tag tag) err-invalid-tag)
        (ok (default-to (list) (map-get? tag-index {tag: tag})))
    )
)

(define-public (add-tag-to-index (dream-id uint) (tag (string-utf8 32)))
    (begin
        (asserts! (validate-tag tag) err-invalid-tag)
        (let (
            (current-entries (default-to (list) (map-get? tag-index {tag: tag})))
            (new-entry {dream-id: dream-id, owner: tx-sender})
        )
            (if (< (len current-entries) u50)
                (begin
                    (map-set tag-index 
                        {tag: tag}
                        (unwrap! (as-max-len? (concat current-entries (list new-entry)) u50)
                                err-index-full))
                    (ok true))
                err-index-full)
        )
    )
)