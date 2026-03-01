import SwiftUI
import CryptoKit
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct AppUser: Identifiable, Equatable {
    var id: String
    var username: String
    var email: String
    var balance: Double
    var profilePhotoURL: String?
}

let dishCategories = ["Main Dish", "Small Plates", "Noodle & Rice", "Dessert", "Drink"]

struct Dish: Identifiable {
    var id: String
    var name: String
    var price: Double
    var imageURL: String?
    var ownerID: String
    var ownerName: String
    var category: String

    init?(from doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name      = d["name"]      as? String,
              let ownerID   = d["ownerID"]   as? String,
              let ownerName = d["ownerName"] as? String
        else { return nil }
        // Firestore may return numbers as NSNumber backed by Int64 or Double depending
        // on how the value was stored. Using NSNumber bridging handles both safely.
        let price = (d["price"] as? NSNumber)?.doubleValue ?? 0
        guard price > 0 else { return nil }
        self.id = doc.documentID; self.name = name; self.price = price
        self.imageURL = d["imageURL"] as? String
        self.ownerID = ownerID; self.ownerName = ownerName
        self.category = d["category"] as? String ?? "Main Dish"
    }

    init(id: String, name: String, price: Double, imageURL: String?,
         ownerID: String, ownerName: String, category: String = "Main Dish") {
        self.id = id; self.name = name; self.price = price
        self.imageURL = imageURL; self.ownerID = ownerID; self.ownerName = ownerName
        self.category = category
    }
}

struct CartItem: Identifiable {
    var id: String = UUID().uuidString
    var dish: Dish
    var quantity: Int
    var subtotal: Double { dish.price * Double(quantity) }
}

// MARK: - Order History Models

struct OrderRecord: Identifiable {
    var id: String
    var total: Double
    var date: Date
    var items: [OrderLineItem]
}

struct OrderLineItem {
    var dishName: String
    var chefName: String
    var quantity: Int
    var price: Double
    var subtotal: Double { price * Double(quantity) }
}

// MARK: - Chef Order Models
//
// Schema: one `orders` document per (chef × checkout).
// Chef listener: whereField("chefID", isEqualTo: uid)  — simple equality, no composite index.
// Buyer listener: whereField("buyerID", isEqualTo: uid) — unchanged, still works.

struct PendingOrder: Identifiable {
    let id: String
    let chefID: String      // the chef who must fulfil this order
    let buyerID: String
    let buyerName: String
    let items: [PendingOrderItem]
    let total: Double       // amount to be credited to chefID on completion
    var status: String      // "pending" | "completed"
    let createdAt: Date
}

struct PendingOrderItem: Identifiable {
    let id = UUID()
    let dishName: String
    let quantity: Int
    let price: Double
    var subtotal: Double { price * Double(quantity) }
}

// MARK: - Top-Up Model

struct TopUpRecord: Identifiable {
    var id: String
    var amount: Double
    var date: Date
}

// MARK: - AppStore

class AppStore: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var dishes: [Dish]              = []
    @Published var cartItems: [CartItem]       = []
    @Published var orderHistory: [OrderRecord]   = []
    @Published var topUpHistory: [TopUpRecord]   = []
    @Published var pendingOrders: [PendingOrder] = []   // orders awaiting this chef's confirmation
    @Published var isLoadingAuth                 = true
    @Published var needsUsername                 = false

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            DispatchQueue.main.async {
                if let uid = firebaseUser?.uid {
                    self?.startListeners(uid: uid)
                } else {
                    self?.stopListeners()
                    self?.currentUser    = nil
                    self?.dishes         = []
                    self?.cartItems      = []
                    self?.orderHistory   = []
                    self?.topUpHistory   = []
                    self?.pendingOrders  = []
                    self?.needsUsername  = false
                    self?.isLoadingAuth  = false
                }
            }
        }
    }

    // MARK: Computed

    var isLoggedIn: Bool  { currentUser != nil }
    var cartTotal: Double { cartItems.reduce(0) { $0 + $1.subtotal } }
    var cartCount: Int    { cartItems.reduce(0) { $0 + $1.quantity } }

    // MARK: - Listeners

    private func startListeners(uid: String) {
        stopListeners()

        // Current user — updates in real-time when chefs earn money
        let userListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                DispatchQueue.main.async {
                    if let d = snap?.data() {
                        self?.currentUser = AppUser(
                            id: uid,
                            username:        d["username"]        as? String ?? "",
                            email:           d["email"]           as? String ?? "",
                            balance:         d["balance"]         as? Double ?? 0,
                            profilePhotoURL: d["profilePhotoURL"] as? String
                        )
                        self?.needsUsername = false
                    }
                    self?.isLoadingAuth = false
                }
            }

        // All dishes — menu syncs across all devices
        let dishesListener = db.collection("dishes")
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    self?.dishes = snap.documents.compactMap { Dish(from: $0) }
                }
            }

        // Order history for this user (sorted client-side, no composite index needed)
        let ordersListener = db.collection("orders")
            .whereField("buyerID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, error in
                if let error = error {
                    print("[OrderHistory] Listener error: \(error.localizedDescription)")
                    return
                }
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    let records: [OrderRecord] = snap.documents.compactMap { doc in
                        // .estimate resolves pending FieldValue.serverTimestamp() to a local
                        // clock estimate so newly placed orders appear immediately.
                        let d = doc.data(with: .estimate)
                        let total = (d["total"] as? NSNumber)?.doubleValue ?? 0
                        guard total > 0,
                              let timestamp = d["createdAt"] as? Timestamp else { return nil }
                        let items = (d["items"] as? [[String: Any]] ?? []).map {
                            OrderLineItem(
                                dishName: $0["dishName"] as? String ?? "",
                                chefName: $0["chefName"] as? String ?? "",
                                quantity: ($0["quantity"] as? NSNumber)?.intValue ?? 1,
                                price:    ($0["price"]    as? NSNumber)?.doubleValue ?? 0
                            )
                        }
                        return OrderRecord(id: doc.documentID, total: total,
                                          date: timestamp.dateValue(), items: items)
                    }
                    self?.orderHistory = records.sorted { $0.date > $1.date }
                }
            }

        // Top-up history for this user
        let topupsListener = db.collection("topups")
            .whereField("userID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, error in
                if let error = error {
                    print("[TopUps] Listener error — check Firestore rules: \(error.localizedDescription)")
                    return
                }
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    let records: [TopUpRecord] = snap.documents.compactMap { doc in
                        // Use .estimate so FieldValue.serverTimestamp() pending writes still
                        // produce a valid Timestamp (local clock estimate) instead of nil.
                        let d = doc.data(with: .estimate)
                        let amount = (d["amount"] as? NSNumber)?.doubleValue
                                  ?? d["amount"] as? Double ?? 0
                        guard amount > 0,
                              let timestamp = d["createdAt"] as? Timestamp else { return nil }
                        return TopUpRecord(id: doc.documentID, amount: amount,
                                          date: timestamp.dateValue())
                    }
                    self?.topUpHistory = records.sorted { $0.date > $1.date }
                }
            }

        // Chef's incoming orders — one document per chef per checkout.
        // Simple equality query: no composite index, no arrayContains complexity.
        let chefOrdersListener = db.collection("orders")
            .whereField("chefID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, error in
                if let error = error {
                    print("[ChefOrders] ❌ Listener error — check Firestore rules: \(error.localizedDescription)")
                    return
                }
                guard let snap = snap else {
                    print("[ChefOrders] Snapshot was nil")
                    return
                }
                print("[ChefOrders] ✅ Received \(snap.documents.count) document(s) for chefID=\(uid)")
                DispatchQueue.main.async {
                    self?.pendingOrders = snap.documents.compactMap { doc -> PendingOrder? in
                        // .estimate: resolves pending FieldValue.serverTimestamp() locally
                        // so orders appear immediately after checkout rather than waiting
                        // for the Firestore server round-trip.
                        let d = doc.data(with: .estimate)

                        guard let chefID    = d["chefID"]    as? String,
                              let buyerID   = d["buyerID"]   as? String,
                              let buyerName = d["buyerName"] as? String
                        else {
                            print("[ChefOrders] ⚠️ Dropped \(doc.documentID): missing string fields. data=\(d)")
                            return nil
                        }
                        // NSNumber bridging handles both Int64 and Double Firestore types.
                        let total     = (d["total"]  as? NSNumber)?.doubleValue ?? 0
                        let status    =  d["status"] as? String ?? "pending"
                        let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()

                        let items = (d["items"] as? [[String: Any]] ?? []).compactMap { item -> PendingOrderItem? in
                            guard let dn  = item["dishName"] as? String else { return nil }
                            let qty   = (item["quantity"] as? NSNumber)?.intValue    ?? 1
                            let price = (item["price"]    as? NSNumber)?.doubleValue ?? 0
                            return PendingOrderItem(dishName: dn, quantity: qty, price: price)
                        }

                        print("[ChefOrders]   doc=\(doc.documentID) status=\(status) total=\(total) buyer=\(buyerName)")
                        return PendingOrder(id: doc.documentID, chefID: chefID,
                                            buyerID: buyerID, buyerName: buyerName,
                                            items: items, total: total,
                                            status: status, createdAt: createdAt)
                    }.sorted { $0.createdAt > $1.createdAt }
                }
            }

        listeners = [userListener, dishesListener, ordersListener, topupsListener, chefOrdersListener]
    }

    /// Orders where this chef still needs to tap Done — drives the tab badge.
    var pendingOrderCount: Int {
        pendingOrders.filter { $0.status == "pending" }.count
    }

    private func stopListeners() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(_ authorization: ASAuthorization,
                           nonce: String,
                           completion: @escaping (Bool, String) -> Void) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleCredential.identityToken,
              let idToken   = String(data: tokenData, encoding: .utf8) else {
            completion(false, "Could not read Apple credential.")
            return
        }
        let credential = OAuthProvider.credential(
            withProviderID: "apple.com", idToken: idToken, rawNonce: nonce)

        Auth.auth().signIn(with: credential) { [weak self] result, error in
            if let error = error {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }
            guard let uid = result?.user.uid else { return }
            self?.db.collection("users").document(uid).getDocument { snapshot, _ in
                DispatchQueue.main.async {
                    if snapshot?.exists == false { self?.needsUsername = true }
                    completion(true, "")
                }
            }
        }
    }

    func createUserProfile(username: String, completion: @escaping (Bool, String) -> Void) {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        db.collection("users").whereField("username", isEqualTo: username)
            .getDocuments { [weak self] snapshot, _ in
                if (snapshot?.documents.count ?? 0) > 0 {
                    DispatchQueue.main.async { completion(false, "Username already taken.") }
                    return
                }
                let data: [String: Any] = [
                    "username": username, "email": firebaseUser.email ?? "",
                    "balance": 1000.0, "createdAt": FieldValue.serverTimestamp()
                ]
                self?.db.collection("users").document(firebaseUser.uid).setData(data) { error in
                    DispatchQueue.main.async {
                        if error == nil { self?.needsUsername = false }
                        completion(error == nil, error?.localizedDescription ?? "")
                    }
                }
            }
    }

    func logout() {
        try? Auth.auth().signOut()
        cartItems.removeAll()
    }

    func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Profile

    func updateProfile(username: String, photo: UIImage?,
                       completion: @escaping (Bool, String) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = ["username": username]
        if let photo {
            data["profilePhotoURL"] = prepareImageBase64(photo)
        }
        db.collection("users").document(uid).setData(data, merge: true) { error in
            DispatchQueue.main.async {
                completion(error == nil, error?.localizedDescription ?? "")
            }
        }
    }

    // MARK: - Top Up

    func topUp(amount: Double, completion: @escaping (Bool, String) -> Void) {
        guard let user = currentUser, amount > 0 else { return }
        let userRef = db.collection("users").document(user.id)

        db.runTransaction({ transaction, errorPointer in
            let snap: DocumentSnapshot
            do { snap = try transaction.getDocument(userRef) }
            catch let e as NSError { errorPointer?.pointee = e; return nil }
            let current = snap.data()?["balance"] as? Double ?? 0
            transaction.updateData(["balance": current + amount], forDocument: userRef)
            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                self?.db.collection("topups").addDocument(data: [
                    "userID":    user.id,
                    "amount":    amount,
                    "createdAt": FieldValue.serverTimestamp()
                ]) { writeError in
                    if let writeError = writeError {
                        print("[TopUps] Failed to write top-up record — check Firestore rules: \(writeError.localizedDescription)")
                    }
                }
                completion(true, "")
            }
        }
    }

    // MARK: - Dish Management

    // Resize image to max dimension before encoding to keep Firestore doc size small
    private func prepareImageBase64(_ image: UIImage) -> String? {
        let maxDimension: CGFloat = 800
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let targetSize = ratio < 1.0
            ? CGSize(width: size.width * ratio, height: size.height * ratio)
            : size
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        guard let data = resized.jpegData(compressionQuality: 0.5) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    func addDish(name: String, price: Double, image: UIImage?, category: String,
                 completion: @escaping (Bool, String) -> Void) {
        guard let user = currentUser else { return }
        let dishID = UUID().uuidString

        func write(imageURL: String?) {
            let data: [String: Any] = [
                "name": name, "price": price, "imageURL": imageURL as Any,
                "ownerID": user.id, "ownerName": user.username,
                "category": category,
                "createdAt": FieldValue.serverTimestamp()
            ]
            db.collection("dishes").document(dishID).setData(data) { error in
                DispatchQueue.main.async { completion(error == nil, error?.localizedDescription ?? "") }
            }
        }

        if let image {
            write(imageURL: prepareImageBase64(image))
        } else {
            write(imageURL: nil)
        }
    }

    /// Update an existing dish. Pass `newImage` only if the photo changed; nil keeps the existing one.
    func updateDish(_ dish: Dish, name: String, price: Double, newImage: UIImage?, category: String,
                    completion: @escaping (Bool, String) -> Void) {
        func write(imageURL: String?) {
            var data: [String: Any] = ["name": name, "price": price, "category": category]
            if let url = imageURL { data["imageURL"] = url }
            db.collection("dishes").document(dish.id).setData(data, merge: true) { error in
                DispatchQueue.main.async { completion(error == nil, error?.localizedDescription ?? "") }
            }
        }

        if let newImage {
            write(imageURL: prepareImageBase64(newImage))
        } else {
            write(imageURL: nil)
        }
    }

    func deleteDish(_ dish: Dish) {
        db.collection("dishes").document(dish.id).delete()
        cartItems.removeAll { $0.dish.id == dish.id }
    }

    // MARK: - Cart

    func quantityInCart(for dish: Dish) -> Int {
        cartItems.first(where: { $0.dish.id == dish.id })?.quantity ?? 0
    }

    func increment(_ dish: Dish) {
        if let idx = cartItems.firstIndex(where: { $0.dish.id == dish.id }) {
            cartItems[idx].quantity += 1
        } else {
            cartItems.append(CartItem(dish: dish, quantity: 1))
        }
    }

    func decrement(_ dish: Dish) {
        guard let idx = cartItems.firstIndex(where: { $0.dish.id == dish.id }) else { return }
        if cartItems[idx].quantity > 1 { cartItems[idx].quantity -= 1 }
        else { cartItems.remove(at: idx) }
    }

    // MARK: - Checkout

    func checkout(completion: @escaping (Bool, String, Double) -> Void) {
        guard let buyer = currentUser else {
            print("[Checkout] ❌ currentUser is nil — not logged in")
            return
        }
        let total = cartTotal
        guard total > 0 else {
            print("[Checkout] ❌ cartTotal is 0 — nothing to purchase")
            return
        }

        // Buyer does not pay for their own dishes.
        let selfEarned = cartItems
            .filter { $0.dish.ownerID == buyer.id }
            .reduce(0.0) { $0 + $1.subtotal }
        let effectiveDeduction = total - selfEarned

        // Group external items by chef. Own dishes are skipped — no order needed.
        var itemsByChef: [String: [CartItem]] = [:]
        for item in cartItems where item.dish.ownerID != buyer.id {
            itemsByChef[item.dish.ownerID, default: []].append(item)
        }

        print("[Checkout] buyerID=\(buyer.id) total=\(total) effectiveDeduction=\(effectiveDeduction)")
        print("[Checkout] itemsByChef keys=\(itemsByChef.keys.sorted())")

        let buyerRef  = db.collection("users").document(buyer.id)
        // Pre-generate one DocumentReference per chef so we can write inside the transaction.
        let orderRefs: [String: DocumentReference] = itemsByChef.mapValues { _ in
            db.collection("orders").document()
        }

        // ── Single atomic transaction ──────────────────────────────────────────
        // Reads buyer balance, checks funds, deducts, creates one order doc per
        // chef — all in one commit. Any failure rolls back everything.
        db.runTransaction({ transaction, errorPointer in

            let buyerSnap: DocumentSnapshot
            do { buyerSnap = try transaction.getDocument(buyerRef) }
            catch let e as NSError {
                print("[Checkout] ❌ Failed to read buyer doc: \(e.localizedDescription)")
                errorPointer?.pointee = e; return nil
            }

            // NSNumber bridging: Firestore may return the balance as Int64 or Double.
            let buyerBalance = (buyerSnap.data()?["balance"] as? NSNumber)?.doubleValue ?? -1
            print("[Checkout] buyerBalance=\(buyerBalance) effectiveDeduction=\(effectiveDeduction)")

            guard buyerBalance >= 0, buyerBalance >= effectiveDeduction else {
                let msg = buyerBalance < 0 ? "Could not read balance" : "Insufficient funds"
                print("[Checkout] ❌ Guard failed: \(msg)")
                errorPointer?.pointee = NSError(
                    domain: "com.478chef", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: msg])
                return nil
            }

            if effectiveDeduction > 0 {
                transaction.updateData(["balance": buyerBalance - effectiveDeduction],
                                       forDocument: buyerRef)
            }

            for (chefID, chefItems) in itemsByChef {
                guard let ref = orderRefs[chefID] else { continue }
                let chefTotal = chefItems.reduce(0.0) { $0 + $1.subtotal }
                let itemData: [[String: Any]] = chefItems.map { item in [
                    "dishName": item.dish.name,
                    "quantity": item.quantity,
                    "price":    item.dish.price
                ]}
                print("[Checkout] Writing order for chefID=\(chefID) total=\(chefTotal) ref=\(ref.documentID)")
                transaction.setData([
                    "chefID":    chefID,
                    "buyerID":   buyer.id,
                    "buyerName": buyer.username,
                    "items":     itemData,
                    "total":     chefTotal,
                    "status":    "pending",
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: ref)
            }

            return nil

        }) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[Checkout] ❌ Transaction failed: \(error.localizedDescription)")
                    completion(false, error.localizedDescription, 0)
                    return
                }
                print("[Checkout] ✅ Transaction committed. Orders created: \(orderRefs.count)")
                self?.cartItems.removeAll()
                completion(true, "", effectiveDeduction)
            }
        }
    }

    // MARK: - Chef Confirmation

    /// Mark a chef order as done, credit the chef's balance, and write a ledger entry.
    ///
    /// Guarantees:
    /// - **Idempotent**: tapping Done twice never double-credits.
    ///   `payoutLedger/{orderID}` is the idempotency key — one credit per order.
    /// - **Atomic**: status update + balance credit + ledger write in one transaction.
    /// - **Auth-scoped**: verifies the signed-in user is the order's chef.
    func markDone(order: PendingOrder, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id else {
            print("[MarkDone] ❌ currentUser is nil")
            completion(false, "Not logged in"); return
        }
        guard uid == order.chefID else {
            print("[MarkDone] ❌ Auth mismatch: currentUser=\(uid) order.chefID=\(order.chefID)")
            completion(false, "Unauthorized"); return
        }
        print("[MarkDone] Starting for orderID=\(order.id) total=\(order.total)")

        let orderRef  = db.collection("orders").document(order.id)
        let chefRef   = db.collection("users").document(uid)
        let ledgerRef = db.collection("payoutLedger").document(order.id)

        db.runTransaction({ transaction, errorPointer in

            // 1. Read live order
            let orderSnap: DocumentSnapshot
            do { orderSnap = try transaction.getDocument(orderRef) }
            catch let e as NSError {
                print("[MarkDone] ❌ Failed to read order: \(e.localizedDescription)")
                errorPointer?.pointee = e; return nil
            }

            // 2. Read ledger (idempotency guard)
            let ledgerSnap: DocumentSnapshot
            do { ledgerSnap = try transaction.getDocument(ledgerRef) }
            catch let e as NSError {
                print("[MarkDone] ❌ Failed to read ledger: \(e.localizedDescription)")
                errorPointer?.pointee = e; return nil
            }

            // Already completed — idempotent no-op
            if orderSnap.data()?["status"] as? String == "completed" {
                print("[MarkDone] Order already completed, skipping")
                return nil
            }

            // 3. Credit chef + write ledger (skip if already credited)
            if !ledgerSnap.exists && order.total > 0 {
                print("[MarkDone] Crediting chef \(uid) with $\(order.total)")
                transaction.updateData(["balance": FieldValue.increment(order.total)],
                                       forDocument: chefRef)
                transaction.setData([
                    "orderId":   order.id,
                    "chefId":    uid,
                    "amount":    order.total,
                    "type":      "CREDIT",
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: ledgerRef)
            }

            // 4. Mark order completed
            transaction.updateData([
                "status":      "completed",
                "completedAt": FieldValue.serverTimestamp()
            ], forDocument: orderRef)
            return nil

        }) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[MarkDone] ❌ Transaction failed: \(error.localizedDescription)")
                } else {
                    print("[MarkDone] ✅ Order \(order.id) completed, chef credited $\(order.total)")
                }
                completion(error == nil, error?.localizedDescription ?? "")
            }
        }
    }
}
