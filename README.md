# YesChef

A native iOS food ordering app where users can both **order dishes** from others and **earn money** by listing and selling their own dishes. Menus are private — the creator invites members by username.

## Features

### Menus
- Each user can create up to 3 menus
- Invite members by exact username — invitees accept or decline from the Invitations tab
- Switch between menus from the Menu tab title or Profile tab
- Rename a menu (swipe right on the menu row in Profile)
- Delete a menu (swipe left) — dishes are unlinked but stay under each chef
- Remove a member — also deletes their dishes from that menu

### For Buyers
- Browse a real-time menu organized by category (Main Dish, Small Plates, Noodle & Rice, Dessert, Drink)
- Scrollspy category bar for quick navigation
- Add items to cart, adjust quantities, and checkout
- Atomic payment processing — balance is only deducted once per order
- Self-orders (your own dishes) are tracked but not charged
- View full order history with expandable details

### For Chefs
- List dishes with name, price, category, and optional cropped photo
- Add a new dish from the Menu tab (+) or from Profile "My Dishes"
- Add an existing dish to any menu via "Add from My Dishes" on the Menu tab
- Move dishes between menus (long-press in Profile "My Dishes")
- Remove your own dish from a menu (long-press on the Menu tab)
- Edit or permanently delete dishes
- View all your dishes across all menus in Profile "My Dishes" with menu labels
- View incoming orders grouped by buyer (Pending / Completed tabs)
- Mark orders as "Done" to receive payment credit
- Idempotent payouts — each order is credited exactly once via a ledger system

### Wallet
- Every new user starts with $1,000
- Top up balance (max $200 per transaction) with quick-pick amounts
- Real-time balance updates as orders are placed and fulfilled
- View full top-up history

### Profile
- Sign in with Apple (OAuth with nonce verification)
- Set and update username and profile photo with crop UI
- Manage menus: create, rename, delete, invite members, remove members
- View all your dishes, order history, and top-up history

### New Users
- Users with no menu membership see a limited tab view: Orders, Invitations, Profile
- They can create a menu or wait for an invitation
- Full menu and cart tabs appear after joining or creating a menu

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (iOS 16+ ToolbarTitleMenu for menu switching) |
| State Management | Combine (`@Published` + `ObservableObject`) |
| Backend | Firebase Firestore (real-time NoSQL) |
| Auth | Firebase Authentication + Sign in with Apple |
| Images | Base64 encoding, resized to max 800px before storage |
| Security | CryptoKit (SHA256 nonce), Firestore security rules |

## Data Models

**Users** — `id`, `username`, `email`, `balance`, `profilePhotoURL`, `defaultMenuID`, `createdAt`

**Menus** — `id`, `name`, `creatorID`, `memberIDs[]`, `createdAt`

**Invitations** — `id`, `menuID`, `menuName`, `fromUserID`, `fromUsername`, `toUserID`, `toUsername`, `status`, `createdAt`

**Dishes** — `id`, `name`, `price`, `imageURL`, `ownerID`, `ownerName`, `category`, `menuID`, `createdAt`

**Orders** — `id`, `chefID`, `buyerID`, `buyerName`, `items[]`, `total`, `status`, `createdAt`, `completedAt`

**Top-ups** — `id`, `userID`, `amount`, `createdAt`

**Payout Ledger** — `orderId`, `chefId`, `amount`, `type`, `createdAt` *(idempotency key)*

## Firestore Security Rules

- **Users**: any authenticated user can read; only the owner can write
- **Menus**: only members can read; creator can update/delete; non-creators can add themselves (invitation acceptance)
- **Invitations**: sender and recipient can read; only the creator sends; only the recipient updates status
- **Dishes**: menu members and dish owner can read; owner creates (must be a menu member); only owner can update/delete
- **Orders**: buyer and chef can read; buyer creates; chef updates (mark done)
- **Top-ups**: owner only
- **Payout Ledger**: handles null resource for idempotency check; owner only

## Project Structure

```
YesChef/YesChef/
├── YesChefApp.swift          # App entry point
├── AppStore.swift            # Global state, models, Firestore listeners & business logic
├── ContentView.swift         # Tab navigation (full vs limited), ChefOrdersView, OrderCard
├── AuthView.swift            # Sign in with Apple flow
├── MenuView.swift            # Menu browsing, dish rows, category bar, pick existing dish
├── CartView.swift            # Cart & checkout
├── ProfileView.swift         # Profile, menus, wallet, my dishes, top-up/order history
├── OrderHistoryView.swift    # Buyer order history
├── AddDishView.swift         # Add new dish form with optional menu picker
├── EditDishView.swift        # Edit existing dish
├── InviteUserView.swift      # Invite members, view/remove members
├── InvitationsView.swift     # Accept/decline incoming invitations
└── CreateMenuView.swift      # Create a new menu
```

## Requirements

- Xcode (latest)
- iOS 16+
- A Firebase project with:
  - Firestore enabled
  - Authentication with Sign in with Apple enabled
  - `GoogleService-Info.plist` added to the Xcode target
  - Security rules published from `firestore.rules`
- Sign in with Apple capability enabled in the Xcode project

## Getting Started

1. Clone the repo and open `YesChef/YesChef.xcodeproj` in Xcode.
2. Add your `GoogleService-Info.plist` to the `YesChef` target.
3. Enable the **Sign in with Apple** capability under *Signing & Capabilities*.
4. Publish the Firestore security rules: copy `firestore.rules` into Firebase Console > Firestore > Rules.
5. Build and run on a simulator or device (iOS 16+).

## Architecture Notes

- All Firestore reads use real-time snapshot listeners, keeping the UI in sync automatically.
- Checkout and payout are both handled as Firestore transactions — atomic and safe against race conditions.
- Listeners are cleaned up on sign-out to prevent stale data or unauthorized reads.
- Menu switching clears the cart and restarts the dishes listener for the selected menu.
- A separate `myAllDishes` listener tracks all dishes owned by the user across all menus (used in Profile).
- Invitation acceptance uses a transaction to atomically update both the menu's `memberIDs` and the invitation status.
- Self-orders carry `total: 0` — buyer is not charged, chef is not credited on completion.
