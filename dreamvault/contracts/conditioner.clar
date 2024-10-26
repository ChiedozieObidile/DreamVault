;; DreamVault: Decentralized Dream Journal
;; A privacy-focused platform for storing and sharing dreams

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-invalid-dream (err u101))
(define-constant err-invalid-time (err u102))
(define-constant err-entry-not-found (err u103))
(define-constant err-index-full (err u104))

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

(define-map dream-counts principal uint)
(define-map tag-index { tag: (string-utf8 32) } (list 50 { dream-id: uint, owner: principal }))

;; Private function to check ownership
(define-private (is-owner (dream-id uint))
    (match (map-get? dreams {dream-id: dream-id, owner: tx-sender})
        entry true
        false)
)

;; Private function to get dream count
(define-private (get-dream-count-internal (user principal))
    (default-to u0 (map-get? dream-counts user))
)

;; Add new dream entry
(define-public (add-dream (content (string-utf8 2048)) 
                         (unlock-time uint) 
                         (is-private bool)
                         (is-anonymous bool)
                         (tags (list 10 (string-utf8 32))))
    (let ((dream-id (get-dream-count-internal tx-sender)))
        (begin
            (asserts! (> (len content) u0) err-invalid-dream)
            (asserts! (>= unlock-time block-height) err-invalid-time)
            
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
            
            (ok dream-id)
        )
    )
)

;; Read dream entry (with privacy checks)
(define-public (read-dream (dream-id uint) (owner principal))
    (let ((entry (unwrap! (map-get? dreams {dream-id: dream-id, owner: owner}) 
                         err-entry-not-found)))
        (begin
            (asserts! (or
                (is-eq tx-sender owner)
                (and
                    (not (get is-private entry))
                    (>= block-height (get unlock-time entry))
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

;; Update dream privacy settings
(define-public (update-privacy (dream-id uint) 
                             (is-private bool)
                             (is-anonymous bool))
    (let ((entry (unwrap! (map-get? dreams 
                                   {dream-id: dream-id, owner: tx-sender})
                         err-entry-not-found)))
        (begin
            (asserts! (is-owner dream-id) err-not-authorized)
            
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

;; Get dream count for user
(define-public (get-dream-count (user principal))
    (ok (get-dream-count-internal user))
)

;; Get all public dreams for a tag
(define-public (get-public-dreams-by-tag (tag (string-utf8 32)))
    (ok (default-to (list) (map-get? tag-index {tag: tag})))
)

;; Add a tag to dream index
(define-public (add-tag-to-index (dream-id uint) (tag (string-utf8 32)))
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