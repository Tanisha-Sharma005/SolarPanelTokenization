;; SolarPanel Tokenization Contract
;; Fractional ownership of solar installations with energy production revenue sharing

;; Define the solar panel ownership token
(define-fungible-token solar-panel-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-panel-not-found (err u104))
(define-constant err-insufficient-revenue (err u105))

;; Token metadata
(define-data-var token-name (string-ascii 32) "SolarPanel Token")
(define-data-var token-symbol (string-ascii 10) "SOLAR")
(define-data-var token-decimals uint u6)

;; Solar panel data structure
(define-map solar-panels uint {
  location: (string-ascii 50),
  capacity-kw: uint,
  installation-date: uint,
  total-tokens: uint,
  revenue-pool: uint,
  active: bool
})

;; Panel ownership tracking
(define-map panel-ownership {panel-id: uint, owner: principal} uint)

;; Revenue distribution tracking
(define-map revenue-claims {panel-id: uint, owner: principal} uint)

;; Global variables
(define-data-var next-panel-id uint u1)
(define-data-var total-revenue-distributed uint u0)

;; Function 1: Purchase Panel Shares
;; Allows users to buy fractional ownership in a solar panel installation
(define-public (purchase-panel-shares (panel-id uint) (share-amount uint) (stx-payment uint))
  (let (
    (panel-info (unwrap! (map-get? solar-panels panel-id) err-panel-not-found))
    (current-ownership (default-to u0 (map-get? panel-ownership {panel-id: panel-id, owner: tx-sender})))
  )
    (begin
      ;; Validate inputs
      (asserts! (> share-amount u0) err-invalid-amount)
      (asserts! (> stx-payment u0) err-invalid-amount)
      (asserts! (get active panel-info) err-panel-not-found)
      
      ;; Transfer STX payment to contract for panel investment
      (try! (stx-transfer? stx-payment tx-sender (as-contract tx-sender)))
      
      ;; Mint solar panel tokens to represent fractional ownership
      (try! (ft-mint? solar-panel-token share-amount tx-sender))
      
      ;; Update ownership mapping
      (map-set panel-ownership 
               {panel-id: panel-id, owner: tx-sender}
               (+ current-ownership share-amount))
      
      ;; Update panel revenue pool with the investment
      (map-set solar-panels panel-id
               (merge panel-info {revenue-pool: (+ (get revenue-pool panel-info) stx-payment)}))
      
      (print {
        action: "panel-shares-purchased",
        panel-id: panel-id,
        buyer: tx-sender,
        shares: share-amount,
        payment: stx-payment
      })
      
      (ok {panel-id: panel-id, shares-owned: (+ current-ownership share-amount)})
    )))

;; Function 2: Distribute Energy Revenue
;; Distributes revenue from energy production to token holders based on their ownership percentage
(define-public (distribute-energy-revenue (panel-id uint) (total-revenue uint))
  (let (
    (panel-info (unwrap! (map-get? solar-panels panel-id) err-panel-not-found))
    (caller-ownership (default-to u0 (map-get? panel-ownership {panel-id: panel-id, owner: tx-sender})))
    (total-panel-tokens (get total-tokens panel-info))
  )
    (begin
      ;; Only token holders can trigger revenue distribution (representing energy production)
      (asserts! (> caller-ownership u0) err-not-authorized)
      (asserts! (> total-revenue u0) err-invalid-amount)
      (asserts! (get active panel-info) err-panel-not-found)
      (asserts! (>= (get revenue-pool panel-info) total-revenue) err-insufficient-revenue)
      
      ;; Calculate caller's share of revenue based on token ownership
      (let (
        (caller-share (/ (* total-revenue caller-ownership) total-panel-tokens))
        (current-claims (default-to u0 (map-get? revenue-claims {panel-id: panel-id, owner: tx-sender})))
      )
        ;; Distribute STX revenue to the caller based on their ownership percentage
        (try! (as-contract (stx-transfer? caller-share tx-sender tx-sender)))
        
        ;; Update revenue claims tracking
        (map-set revenue-claims 
                 {panel-id: panel-id, owner: tx-sender}
                 (+ current-claims caller-share))
        
        ;; Update panel revenue pool
        (map-set solar-panels panel-id
                 (merge panel-info {revenue-pool: (- (get revenue-pool panel-info) caller-share)}))
        
        ;; Update global revenue tracking
        (var-set total-revenue-distributed (+ (var-get total-revenue-distributed) caller-share))
        
        (print {
          action: "energy-revenue-distributed",
          panel-id: panel-id,
          recipient: tx-sender,
          revenue-share: caller-share,
          ownership-percentage: (/ (* caller-ownership u100) total-panel-tokens)
        })
        
        (ok {
          panel-id: panel-id,
          revenue-received: caller-share,
          total-ownership: caller-ownership,
          ownership-percentage: (/ (* caller-ownership u100) total-panel-tokens)
        })
      )
    )))

;; Read-only functions for contract information
(define-read-only (get-panel-info (panel-id uint))
  (map-get? solar-panels panel-id))

(define-read-only (get-ownership (panel-id uint) (owner principal))
  (map-get? panel-ownership {panel-id: panel-id, owner: owner}))

(define-read-only (get-revenue-claims (panel-id uint) (owner principal))
  (map-get? revenue-claims {panel-id: panel-id, owner: owner}))

(define-read-only (get-token-balance (owner principal))
  (ft-get-balance solar-panel-token owner))

;; Admin function to register new solar panel installations
(define-public (register-solar-panel (location (string-ascii 50)) (capacity-kw uint) (total-tokens uint))
  (let ((panel-id (var-get next-panel-id)))
    (begin
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      (asserts! (> capacity-kw u0) err-invalid-amount)
      (asserts! (> total-tokens u0) err-invalid-amount)
      
      (map-set solar-panels panel-id {
        location: location,
        capacity-kw: capacity-kw,
        installation-date: stacks-block-height,
        total-tokens: total-tokens,
        revenue-pool: u0,
        active: true
      })
      
      (var-set next-panel-id (+ panel-id u1))
      (ok panel-id)
    )))