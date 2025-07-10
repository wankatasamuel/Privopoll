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
(define-constant ERR_DELEGATION_EXISTS (err u111))
(define-constant ERR_DELEGATION_NOT_FOUND (err u112))
(define-constant ERR_SELF_DELEGATION (err u113))
(define-constant ERR_CIRCULAR_DELEGATION (err u114))
(define-constant ERR_DELEGATION_LIMIT (err u115))
(define-constant ERR_INVALID_DELEGATE (err u116))
(define-constant ERR_REPUTATION_TOO_LOW (err u117))
(define-constant ERR_INVALID_RATING (err u118))

(define-data-var poll-counter uint u0)
(define-data-var min-stake-amount uint u1000000)
(define-data-var delegation-counter uint u0)
(define-data-var min-reputation-score uint u50)
(define-data-var max-delegations-per-user uint u5)

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

(define-map delegations
  { delegator: principal, delegate: principal }
  {
    delegation-id: uint,
    start-block: uint,
    active: bool,
    delegation-weight: uint,
    polls-delegated: (list 100 uint)
  }
)

(define-map user-delegations
  { user: principal }
  {
    delegating-to: (list 5 principal),
    delegated-from: (list 20 principal),
    total-delegation-weight: uint,
    active-delegations: uint
  }
)

(define-map delegate-reputation
  { delegate: principal }
  {
    reputation-score: uint,
    total-votes-cast: uint,
    total-delegations-received: uint,
    successful-votes: uint,
    rating-sum: uint,
    rating-count: uint,
    last-activity-block: uint
  }
)

(define-map delegation-votes
  { poll-id: uint, delegate: principal }
  {
    delegated-votes: uint,
    option-voted: uint,
    delegators: (list 20 principal)
  }
)

(define-map delegation-ratings
  { delegator: principal, delegate: principal, poll-id: uint }
  {
    rating: uint,
    feedback: (string-ascii 200),
    block-rated: uint
  }
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

(define-public (create-delegation (delegate principal) (weight uint))
  (let
    (
      (delegation-id (+ (var-get delegation-counter) u1))
      (current-block stacks-block-height)
      (delegator-data (get-user-delegation-data tx-sender))
      (delegate-rep (get-delegate-reputation delegate))
    )
    (asserts! (not (is-eq tx-sender delegate)) ERR_SELF_DELEGATION)
    (asserts! (is-none (map-get? delegations { delegator: tx-sender, delegate: delegate })) ERR_DELEGATION_EXISTS)
    (asserts! (< (get active-delegations delegator-data) (var-get max-delegations-per-user)) ERR_DELEGATION_LIMIT)
    (asserts! (>= (get reputation-score delegate-rep) (var-get min-reputation-score)) ERR_REPUTATION_TOO_LOW)
    (asserts! (> weight u0) ERR_INSUFFICIENT_STAKE)
    (asserts! (not (check-circular-delegation tx-sender delegate)) ERR_CIRCULAR_DELEGATION)
    
    (map-set delegations
      { delegator: tx-sender, delegate: delegate }
      {
        delegation-id: delegation-id,
        start-block: current-block,
        active: true,
        delegation-weight: weight,
        polls-delegated: (list)
      }
    )
    
    (map-set user-delegations
      { user: tx-sender }
      {
        delegating-to: (unwrap-panic (as-max-len? (append (get delegating-to delegator-data) delegate) u5)),
        delegated-from: (get delegated-from delegator-data),
        total-delegation-weight: (+ (get total-delegation-weight delegator-data) weight),
        active-delegations: (+ (get active-delegations delegator-data) u1)
      }
    )
    
    (let ((delegate-data (get-user-delegation-data delegate)))
      (map-set user-delegations
        { user: delegate }
        {
          delegating-to: (get delegating-to delegate-data),
          delegated-from: (unwrap-panic (as-max-len? (append (get delegated-from delegate-data) tx-sender) u20)),
          total-delegation-weight: (get total-delegation-weight delegate-data),
          active-delegations: (get active-delegations delegate-data)
        }
      )
    )
    
    (map-set delegate-reputation
      { delegate: delegate }
      {
        reputation-score: (get reputation-score delegate-rep),
        total-votes-cast: (get total-votes-cast delegate-rep),
        total-delegations-received: (+ (get total-delegations-received delegate-rep) u1),
        successful-votes: (get successful-votes delegate-rep),
        rating-sum: (get rating-sum delegate-rep),
        rating-count: (get rating-count delegate-rep),
        last-activity-block: current-block
      }
    )
    
    (var-set delegation-counter delegation-id)
    (ok delegation-id)
  )
)

(define-public (revoke-delegation (delegate principal))
  (let
    (
      (delegation (unwrap! (map-get? delegations { delegator: tx-sender, delegate: delegate }) ERR_DELEGATION_NOT_FOUND))
      (delegator-data (get-user-delegation-data tx-sender))
      (delegate-data (get-user-delegation-data delegate))
    )
    (asserts! (get active delegation) ERR_DELEGATION_NOT_FOUND)
    
    (map-set delegations
      { delegator: tx-sender, delegate: delegate }
      (merge delegation { active: false })
    )
    
    (map-set user-delegations
      { user: tx-sender }
      {
        delegating-to: (filter remove-delegate (get delegating-to delegator-data)),
        delegated-from: (get delegated-from delegator-data),
        total-delegation-weight: (- (get total-delegation-weight delegator-data) (get delegation-weight delegation)),
        active-delegations: (- (get active-delegations delegator-data) u1)
      }
    )
    
    (map-set user-delegations
      { user: delegate }
      {
        delegating-to: (get delegating-to delegate-data),
        delegated-from: (filter remove-delegator (get delegated-from delegate-data)),
        total-delegation-weight: (get total-delegation-weight delegate-data),
        active-delegations: (get active-delegations delegate-data)
      }
    )
    
    (ok true)
  )
)

(define-public (vote-as-delegate (poll-id uint) (option-index uint) (delegator-commitments (list 20 {delegator: principal, commitment: (buff 32)})))
  (let
    (
      (poll (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (current-block stacks-block-height)
      (delegate-rep (get-delegate-reputation tx-sender))
    )
    (asserts! (and (>= current-block (get start-block poll)) 
                   (<= current-block (get end-block poll))) ERR_POLL_EXPIRED)
    (asserts! (is-eq (get status poll) "active") ERR_POLL_NOT_ACTIVE)
    (asserts! (< option-index (len (get options poll))) ERR_INVALID_OPTION)
    (asserts! (>= (get reputation-score delegate-rep) (var-get min-reputation-score)) ERR_REPUTATION_TOO_LOW)
    
    (let ((processed-votes (process-delegated-commitments poll-id delegator-commitments)))
      ;; (map-set delegation-votes
      ;;   { poll-id: poll-id, delegate: tx-sender }
      ;;   {
      ;;     delegated-votes: (len processed-votes),
      ;;     option-voted: option-index,
      ;;     delegators: processed-votes
      ;;   }
      ;; )
      
      (map-set delegate-reputation
        { delegate: tx-sender }
        {
          reputation-score: (get reputation-score delegate-rep),
          total-votes-cast: (+ (get total-votes-cast delegate-rep) u1),
          total-delegations-received: (get total-delegations-received delegate-rep),
          successful-votes: (get successful-votes delegate-rep),
          rating-sum: (get rating-sum delegate-rep),
          rating-count: (get rating-count delegate-rep),
          last-activity-block: current-block
        }
      )
      
      (ok (len processed-votes))
    )
  )
)

(define-public (rate-delegate (delegate principal) (poll-id uint) (rating uint) (feedback (string-ascii 200)))
  (let
    (
      (delegation (unwrap! (map-get? delegations { delegator: tx-sender, delegate: delegate }) ERR_DELEGATION_NOT_FOUND))
      (poll (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (delegate-vote (map-get? delegation-votes { poll-id: poll-id, delegate: delegate }))
      (delegate-rep (get-delegate-reputation delegate))
    )
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
    (asserts! (is-eq (get status poll) "finalized") ERR_POLL_NOT_ACTIVE)
    (asserts! (is-some delegate-vote) ERR_INVALID_DELEGATE)
    (asserts! (is-none (map-get? delegation-ratings { delegator: tx-sender, delegate: delegate, poll-id: poll-id })) ERR_ALREADY_VOTED)
    
    (map-set delegation-ratings
      { delegator: tx-sender, delegate: delegate, poll-id: poll-id }
      {
        rating: rating,
        feedback: feedback,
        block-rated: stacks-block-height
      }
    )
    
    (let ((new-rating-sum (+ (get rating-sum delegate-rep) rating))
          (new-rating-count (+ (get rating-count delegate-rep) u1)))
      (map-set delegate-reputation
        { delegate: delegate }
        {
          reputation-score: (/ (* new-rating-sum u20) new-rating-count),
          total-votes-cast: (get total-votes-cast delegate-rep),
          total-delegations-received: (get total-delegations-received delegate-rep),
          successful-votes: (get successful-votes delegate-rep),
          rating-sum: new-rating-sum,
          rating-count: new-rating-count,
          last-activity-block: (get last-activity-block delegate-rep)
        }
      )
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

(define-private (check-circular-delegation (delegator principal) (delegate principal))
  (let ((delegate-data (get-user-delegation-data delegate)))
    (is-some (index-of (get delegating-to delegate-data) delegator))
  )
)

(define-private (remove-delegate (delegate principal))
  (not (is-eq delegate delegate))
)

(define-private (remove-delegator (delegator principal))
  (not (is-eq delegator delegator))
)

(define-private (process-delegated-commitments (poll-id uint) (delegator-commitments (list 20 {delegator: principal, commitment: (buff 32)})))
  (filter is-valid-delegator-commitment (map validate-delegator-commitment delegator-commitments))
)

(define-private (validate-delegator-commitment (commitment-data {delegator: principal, commitment: (buff 32)}))
  (let
    (
      (delegator (get delegator commitment-data))
      (commitment (get commitment commitment-data))
      (delegation (map-get? delegations { delegator: delegator, delegate: tx-sender }))
    )
    (and
      (is-some delegation)
      (get active (unwrap-panic delegation))
      (is-some (map-get? commitments { poll-id: u1, voter: delegator }))
    )
  )
)

(define-private (is-valid-delegator-commitment (is-valid bool))
  is-valid
)

(define-read-only (get-user-delegation-data (user principal))
  (default-to
    {
      delegating-to: (list),
      delegated-from: (list),
      total-delegation-weight: u0,
      active-delegations: u0
    }
    (map-get? user-delegations { user: user })
  )
)

(define-read-only (get-delegate-reputation (delegate principal))
  (default-to
    {
      reputation-score: u50,
      total-votes-cast: u0,
      total-delegations-received: u0,
      successful-votes: u0,
      rating-sum: u0,
      rating-count: u0,
      last-activity-block: u0
    }
    (map-get? delegate-reputation { delegate: delegate })
  )
)

(define-read-only (get-delegation (delegator principal) (delegate principal))
  (map-get? delegations { delegator: delegator, delegate: delegate })
)

(define-read-only (get-delegation-votes (poll-id uint) (delegate principal))
  (map-get? delegation-votes { poll-id: poll-id, delegate: delegate })
)

(define-read-only (get-delegation-rating (delegator principal) (delegate principal) (poll-id uint))
  (map-get? delegation-ratings { delegator: delegator, delegate: delegate, poll-id: poll-id })
)

(define-read-only (get-delegate-performance (delegate principal))
  (let ((rep (get-delegate-reputation delegate)))
    {
      reputation-score: (get reputation-score rep),
      success-rate: (if (> (get total-votes-cast rep) u0)
                      (/ (* (get successful-votes rep) u100) (get total-votes-cast rep))
                      u0),
      total-delegations: (get total-delegations-received rep),
      average-rating: (if (> (get rating-count rep) u0)
                       (/ (get rating-sum rep) (get rating-count rep))
                       u0),
      last-activity: (get last-activity-block rep)
    }
  )
)

;; (define-read-only (get-top-delegates (limit uint))
;;   (let
;;     (
;;       ;; (delegates (list 'SP1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM 'SP2PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM))
;;       ;; (sorted-delegates (sort-delegates delegates))
;;     )
;;     (if (<= limit u10)
;;       (default-to (list) (as-max-len? sorted-delegates u10))
;;       (list)
;;     )
;;   )
;; )

(define-private (sort-delegates (delegates (list 2 principal)))
  delegates
)

(define-read-only (get-delegation-history (user principal))
  (let ((user-data (get-user-delegation-data user)))
    {
      delegating-to: (get delegating-to user-data),
      delegated-from: (get delegated-from user-data),
      total-weight: (get total-delegation-weight user-data),
      active-count: (get active-delegations user-data)
    }
  )
)

(define-read-only (verify-delegation-eligibility (delegate principal))
  (let ((rep (get-delegate-reputation delegate)))
    {
      eligible: (>= (get reputation-score rep) (var-get min-reputation-score)),
      reputation-score: (get reputation-score rep),
      min-required: (var-get min-reputation-score),
      total-delegations: (get total-delegations-received rep),
      last-activity: (get last-activity-block rep)
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