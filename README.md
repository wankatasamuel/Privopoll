# 🗳️ Privopoll - Anonymous Polling Protocol

> Prove participation without revealing identity 🔐

## 📋 Overview

Privopoll is a privacy-preserving polling protocol built on Stacks that enables anonymous voting through a commit-reveal scheme. Users can participate in polls while maintaining complete anonymity, with cryptographic proof of participation.

## ✨ Features

- 🎭 **Anonymous Voting**: Complete voter privacy through commit-reveal mechanism
- 🔒 **Stake-based Security**: Prevents spam and ensures commitment
- ⏰ **Time-bounded Polls**: Configurable voting and reveal periods  
- 🏆 **Verifiable Results**: Transparent vote counting without identity exposure
- 💰 **Automatic Refunds**: Stakes returned upon proper vote revelation
- 🛡️ **Sybil Resistance**: Economic barriers prevent multiple fake identities

## 🚀 Quick Start

### Creating a Poll

```clarity
(contract-call? .Privopoll create-poll 
  "Favorite Programming Language"
  "Vote for your preferred programming language for blockchain development"
  (list "Clarity" "Solidity" "Rust" "JavaScript")
  u1000    ;; 1000 blocks voting period
  u500     ;; 500 blocks reveal period  
  u1000000 ;; 1 STX minimum stake
)
```

### Participating in a Poll

#### Step 1: Commit Your Vote 🤝
```clarity
;; Generate commitment hash off-chain: sha256(option_index + nonce + voter_address)
(contract-call? .Privopoll commit-vote 
  u1 ;; poll-id
  0x1234567890abcdef... ;; commitment hash
)
```

#### Step 2: Reveal Your Vote 🎯
```clarity
(contract-call? .Privopoll reveal-vote
  u1 ;; poll-id
  u2 ;; option index (0-based)
  0xabcdef1234567890... ;; nonce used in commitment
)
```

## 🔍 Reading Poll Data

### Get Poll Information
```clarity
(contract-call? .Privopoll get-poll u1)
```

### Check Poll Results
```clarity
(contract-call? .Privopoll get-poll-results u1)
```

### Verify Participation
```clarity
(contract-call? .Privopoll verify-participation u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Check Poll Status
```clarity
(contract-call? .Privopoll get-poll-status u1)
```

## 🔄 Poll Lifecycle

1. **📝 Creation Phase**: Poll creator sets parameters and options
2. **🤝 Commit Phase**: Voters submit encrypted vote commitments with stake
3. **🎯 Reveal Phase**: Voters reveal their actual votes to claim stakes back
4. **🏁 Finalization**: Poll creator or contract owner finalizes results

## 🛠️ Advanced Features

### Poll Management
- **Finalize Poll**: Mark poll as complete after reveal period
- **Claim Unrevealed Stakes**: Contract owner can claim stakes from non-revealed votes

### Stake Management
- **Minimum Stake**: 1 STX default (configurable per poll)
- **Automatic Refund**: Stakes returned upon successful vote reveal
- **Penalty System**: Unrevealed votes forfeit their stakes

## 🔐 Privacy Guarantees

- **Vote Secrecy**: Individual votes cannot be traced to voters
- **Participation Proof**: Can prove you voted without revealing your choice
- **Result Integrity**: Vote counts are verifiable and tamper-proof
- **Temporal Privacy**: Commitment timing doesn't reveal vote content

## 📊 Use Cases

- 🏛️ **DAO Governance**: Anonymous proposal voting
- 🎓 **Academic Research**: Private opinion polling
- 🏢 **Corporate Decisions**: Confidential employee feedback
- 🌍 **Community Polls**: Public opinion without personal exposure
- 🗳️ **Elections**: Private ballot systems

## ⚠️ Important Notes

- 📝 Keep your nonce secure - losing it means losing your stake
- ⏰ Reveal votes within the reveal period or forfeit your stake  
- 🔢 Option indices are 0-based (first option = 0)
- 💎 Stakes are held in STX and automatically managed

## 🧪 Testing

```bash
clarinet test
```

## 📈 Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 100 | ERR_NOT_AUTHORIZED | Caller not authorized for this action |
| 101 | ERR_POLL_NOT_FOUND | Poll ID does not exist |
| 102 | ERR_POLL_EXPIRED | Poll voting period has ended |
| 103 | ERR_POLL_NOT_ACTIVE | Poll is not in active state |
| 104 | ERR_ALREADY_VOTED | User has already committed/revealed |
| 105 | ERR_INVALID_OPTION | Invalid option index provided |
| 106 | ERR_POLL_ENDED | Poll has already been finalized |
| 107 | ERR_INSUFFICIENT_STAKE | Stake amount below minimum |
| 108 | ERR_INVALID_COMMITMENT | Commitment hash doesn't match reveal |
| 109 | ERR_REVEAL_PERIOD_ENDED | Reveal period has expired |
| 110 | ERR_COMMITMENT_NOT_FOUND | No commitment found for user |

## 🤝 Contributing

Contributions welcome! Please read our contributing guidelines and submit pull requests for any improvements.


