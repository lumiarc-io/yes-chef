# 478Chef

A native iOS food ordering app where users can both **order dishes** from others and **earn money** by listing and selling their own dishes.

## Features

### For Buyers
- Browse a real-time menu organized by category (Main Dish, Small Plates, Noodle & Rice, Dessert, Drink)
- Add items to cart, adjust quantities, and checkout
- Atomic payment processing — balance is only deducted once per order
- Own dishes are excluded from payment (no self-charge)
- View full order history with expandable details

### For Chefs
- List dishes with name, price, category, and optional photo
- Edit or delete existing dishes
- View incoming orders grouped by buyer
- Mark orders as "Done" to receive payment credit
- Idempotent payouts — each order is credited exactly once via a ledger system

### Wallet
- Every new user starts with $1,000
- Top up balance (max $200 per transaction)
- Real-time balance updates as orders are placed and fulfilled
- View full top-up history

### Profile
- Sign in with Apple (OAuth with nonce verification)
- Set and update username and profile photo
- Crop UI for profile and dish photos

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| State Management | Combine (`@Published` + `ObservableObject`) |
| Backend | Firebase Firestore (real-time NoSQL) |
| Auth | Firebase Authentication + Sign in with Apple |
| Images | Base64 encoding, resized to max 800px before storage |
| Security | CryptoKit (SHA256 nonce), AuthenticationServices |

## Data Models

**Users** — `id`, `username`, `email`, `balance`, `profilePhotoURL`, `createdAt`

**Dishes** — `id`, `name`, `price`, `imageURL`, `ownerID`, `ownerName`, `category`, `createdAt`

**Orders** — `id`, `chefID`, `buyerID`, `buyerName`, `items[]`, `total`, `status`, `createdAt`, `completedAt`

**Top-ups** — `id`, `userID`, `amount`, `createdAt`

**Payout Ledger** — `orderId`, `chefId`, `amount`, `type`, `createdAt` *(idempotency key)*

## Project Structure

```
478Chef/
├── 478ChefApp.swift          # App entry point
├── AppStore.swift            # Global state & Firestore listeners
├── ContentView.swift         # Tab navigation & routing
├── AuthView.swift            # Sign in with Apple flow
├── MenuView.swift            # Menu browsing & dish management
├── CartView.swift            # Cart & checkout
├── ProfileView.swift         # Profile, balance, top-up
├── OrderHistoryView.swift    # Buyer order history
├── AddDishView.swift         # Add new dish form
└── EditDishView.swift        # Edit existing dish
```

## Requirements

- Xcode (latest)
- iOS 15+
- A Firebase project with:
  - Firestore enabled
  - Authentication with Sign in with Apple enabled
  - `GoogleService-Info.plist` added to the Xcode target
- Sign in with Apple capability enabled in the Xcode project

## Getting Started

1. Clone the repo and open `478Chef/478Chef.xcodeproj` in Xcode.
2. Add your `GoogleService-Info.plist` to the `478Chef` target.
3. Enable the **Sign in with Apple** capability under *Signing & Capabilities*.
4. Build and run on a simulator or device (iOS 15+).

## Architecture Notes

- All Firestore reads use real-time snapshot listeners, keeping the UI in sync automatically.
- Checkout and payout are both handled as Firestore transactions — atomic and safe against race conditions.
- Listeners are cleaned up on sign-out to prevent stale data or unauthorized reads.
