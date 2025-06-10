;; title: Privopoll
;; version: 1.0.0
;; summary: Anonymous Polling Protocol
;; description: Prove participation without revealing identity

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_POLL_NOT_FOUND (err u101))
(define-constant ERR_POLL_EXPIRED (err u102))
(define-constant ERR_POLL_NOT_ACTIVE (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INVALID_OPTION (err u105))
(define-constant ERR_POLL_ENDED (err u106))
(define-constant ERR_INSUFFICIENT_STAKE (err u107))
(define-constant ERR_INVALID_COMMITMENT (err u108))
(define-constant ERR_REVEAL_PERIOD_ENDED (err u109))
(define-constant ERR_COMMITMENT_NOT_FOUND (err u110))

(define-data-var poll-counter uint u0)
(define-data-var min-stake-amount uint u1000000)

(define-map polls
  { poll-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    options: (list 10 (string-ascii 50)),
    creator: principal,
    start-block: uint,
    end-block: uint,
    reveal-end-block: uint,
    min-stake: uint,
    total-participants: uint,
    status: (string-ascii 20)
  }
)

(define-map poll-votes
  { poll-id: uint, option-index: uint }
  { vote-count: uint }
)

(define-map commitments
  { poll-id: uint, voter: principal }
  {
    commitment-hash: (buff 32),
    stake-amount: uint,
    block-committed: uint,
    revealed: bool
  }
)

(define-map reveals
  { poll-id: uint, voter: principal }
  {
    option-index: uint,
    nonce: (buff 32),
    block-revealed: uint
  }
)

(define-map user-stakes
  { user: principal }
  { total-staked: uint }
)

(define-map poll-participants
  { poll-id: uint }
  { participants: (list 1000 principal) }
)

(define-public (create-poll 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (options (list 10 (string-ascii 50)))
  (duration-blocks uint)
  (reveal-duration-blocks uint)
  (min-stake uint))
  (let
    (
      (poll-id (+ (var-get poll-counter) u1))
      (start-block stacks-block-height)
      (end-block (+ stacks-block-height duration-blocks))
      (reveal-end-block (+ end-block reveal-duration-blocks))
    )
    (asserts! (>= (len options) u2) ERR_INVALID_OPTION)
    (asserts! (>= min-stake (var-get min-stake-amount)) ERR_INSUFFICIENT_STAKE)
    
    (map-set polls
      { poll-id: poll-id }
      {
        title: title,
        description: description,
        options: options,
        creator: tx-sender,
        start-block: start-block,
        end-block: end-block,
        reveal-end-block: reveal-end-block,
        min-stake: min-stake,
        total-participants: u0,
        status: "active"
      }
    )
    
    (var-set poll-counter poll-id)
    (ok poll-id)
  )
)

(define-public (commit-vote (poll-id uint) (commitment-hash (buff 32)))
  (let
    (
      (poll (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (current-block stacks-block-height)
      (stake-amount (get min-stake poll))
    )
    (asserts! (and (>= current-block (get start-block poll)) 
                   (<= current-block (get end-block poll))) ERR_POLL_EXPIRED)
    (asserts! (is-eq (get status poll) "active") ERR_POLL_NOT_ACTIVE)
    (asserts! (is-none (map-get? commitments { poll-id: poll-id, voter: tx-sender })) ERR_ALREADY_VOTED)
    
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set commitments
      { poll-id: poll-id, voter: tx-sender }
      {
        commitment-hash: commitment-hash,
        stake-amount: stake-amount,
        block-committed: current-block,
        revealed: false
      }
    )
    
    (map-set user-stakes
      { user: tx-sender }
      { total-staked: (+ (get-user-stake tx-sender) stake-amount) }
    )
    
    (map-set polls
      { poll-id: poll-id }
      (merge poll { total-participants: (+ (get total-participants poll) u1) })
    )
    
    (ok true)
  )
)

(define-public (reveal-vote (poll-id uint) (option-index uint) (nonce (buff 32)))
  (let
    (
      (poll (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (commitment (unwrap! (map-get? commitments { poll-id: poll-id, voter: tx-sender }) ERR_COMMITMENT_NOT_FOUND))
      (current-block stacks-block-height)
      (computed-hash (sha256 (concat (concat (unwrap-panic (to-consensus-buff? option-index)) nonce) (unwrap-panic (to-consensus-buff? tx-sender)))))
    )
    (asserts! (> current-block (get end-block poll)) ERR_POLL_NOT_ACTIVE)
    (asserts! (<= current-block (get reveal-end-block poll)) ERR_REVEAL_PERIOD_ENDED)
    (asserts! (is-eq computed-hash (get commitment-hash commitment)) ERR_INVALID_COMMITMENT)
    (asserts! (not (get revealed commitment)) ERR_ALREADY_VOTED)
    (asserts! (< option-index (len (get options poll))) ERR_INVALID_OPTION)
    
    (map-set reveals
      { poll-id: poll-id, voter: tx-sender }
      {
        option-index: option-index,
        nonce: nonce,
        block-revealed: current-block
      }
    )
    
    (map-set commitments
      { poll-id: poll-id, voter: tx-sender }
      (merge commitment { revealed: true })
    )
    
    (let
      (
        (current-votes (default-to u0 (get vote-count (map-get? poll-votes { poll-id: poll-id, option-index: option-index }))))
      )
      (map-set poll-votes
        { poll-id: poll-id, option-index: option-index }
        { vote-count: (+ current-votes u1) }
      )
    )
    
    (try! (as-contract (stx-transfer? (get stake-amount commitment) tx-sender tx-sender)))
    
    (map-set user-stakes
      { user: tx-sender }
      { total-staked: (- (get-user-stake tx-sender) (get stake-amount commitment)) }
    )
    
    (ok true)
  )
)

(define-public (finalize-poll (poll-id uint))
  (let
    (
      (poll (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (or (is-eq tx-sender (get creator poll)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_AUTHORIZED)
    (asserts! (> current-block (get reveal-end-block poll)) ERR_POLL_NOT_ACTIVE)
    (asserts! (is-eq (get status poll) "active") ERR_POLL_ENDED)
    
    (map-set polls
      { poll-id: poll-id }
      (merge poll { status: "finalized" })
    )
    
    (ok true)
  )
)

(define-public (claim-unrevealed-stakes (poll-id uint) (voters (list 100 principal)))
  (let
    (
      (poll (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> current-block (get reveal-end-block poll)) ERR_REVEAL_PERIOD_ENDED)
    (asserts! (is-eq (get status poll) "finalized") ERR_POLL_NOT_ACTIVE)
    
    (ok (map claim-single-stake (map create-claim-data voters (list poll-id))))
  )
)

(define-private (create-claim-data (voter principal) (poll-id uint))
  { voter: voter, poll-id: poll-id }
)

(define-private (claim-single-stake (data { voter: principal, poll-id: uint }))
  (let
    (
      (voter (get voter data))
      (poll-id (get poll-id data))
      (commitment (map-get? commitments { poll-id: poll-id, voter: voter }))
    )
    (match commitment
      commitment-data
      (if (not (get revealed commitment-data))
        (begin
          (map-delete commitments { poll-id: poll-id, voter: voter })
          (map-set user-stakes
            { user: voter }
            { total-staked: (- (get-user-stake voter) (get stake-amount commitment-data)) }
          )
          true
        )
        false
      )
      false
    )
  )
)

(define-read-only (get-poll (poll-id uint))
  (map-get? polls { poll-id: poll-id })
)

(define-read-only (get-poll-results (poll-id uint))
  (let
    (
      (poll (map-get? polls { poll-id: poll-id }))
    )
    (match poll
      poll-data
      (some {
        poll: poll-data,
        results: (map get-option-votes (generate-indices (len (get options poll-data)) poll-id))
      })
      none
    )
  )
)

(define-read-only (get-option-votes (data { index: uint, poll-id: uint }))
  {
    option-index: (get index data),
    vote-count: (default-to u0 (get vote-count (map-get? poll-votes { poll-id: (get poll-id data), option-index: (get index data) })))
  }
)

(define-read-only (generate-indices (length uint) (poll-id uint))
  (map create-index-data (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9) (list poll-id poll-id poll-id poll-id poll-id poll-id poll-id poll-id poll-id poll-id))
)

(define-read-only (create-index-data (index uint) (poll-id uint))
  { index: index, poll-id: poll-id }
)

(define-read-only (get-commitment (poll-id uint) (voter principal))
  (map-get? commitments { poll-id: poll-id, voter: voter })
)

(define-read-only (get-reveal (poll-id uint) (voter principal))
  (map-get? reveals { poll-id: poll-id, voter: voter })
)

(define-read-only (get-user-stake (user principal))
  (default-to u0 (get total-staked (map-get? user-stakes { user: user })))
)

(define-read-only (get-poll-count)
  (var-get poll-counter)
)

(define-read-only (verify-participation (poll-id uint) (voter principal))
  (let
    (
      (commitment (map-get? commitments { poll-id: poll-id, voter: voter }))
      (reveal (map-get? reveals { poll-id: poll-id, voter: voter }))
    )
    {
      participated: (is-some commitment),
      revealed: (and (is-some commitment) (is-some reveal)),
      commitment-block: (match commitment c (some (get block-committed c)) none),
      reveal-block: (match reveal r (some (get block-revealed r)) none)
    }
  )
)

(define-read-only (get-poll-status (poll-id uint))
  (let
    (
      (poll (map-get? polls { poll-id: poll-id }))
      (current-block stacks-block-height)
    )
    (match poll
      poll-data
      (some {
        phase: (if (<= current-block (get end-block poll-data))
                  "commit"
                  (if (<= current-block (get reveal-end-block poll-data))
                    "reveal"
                    "ended")),
        blocks-remaining: (if (<= current-block (get end-block poll-data))
                           (- (get end-block poll-data) current-block)
                           (if (<= current-block (get reveal-end-block poll-data))
                             (- (get reveal-end-block poll-data) current-block)
                             u0)),
        total-participants: (get total-participants poll-data),
        status: (get status poll-data)
      })
      none
    )
  )
)