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
    var defaultMenuID: String?
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
    var menuID: String

    init?(from doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name      = d["name"]      as? String,
              let ownerID   = d["ownerID"]   as? String,
              let ownerName = d["ownerName"] as? String
        else { return nil }
        let price = (d["price"] as? NSNumber)?.doubleValue ?? 0
        guard price > 0 else { return nil }
        self.id = doc.documentID; self.name = name; self.price = price
        self.imageURL = d["imageURL"] as? String
        self.ownerID = ownerID; self.ownerName = ownerName
        self.category = d["category"] as? String ?? "Main Dish"
        self.menuID = d["menuID"] as? String ?? ""
    }

    init(id: String, name: String, price: Double, imageURL: String?,
         ownerID: String, ownerName: String, category: String = "Main Dish",
         menuID: String) {
        self.id = id; self.name = name; self.price = price
        self.imageURL = imageURL; self.ownerID = ownerID; self.ownerName = ownerName
        self.category = category; self.menuID = menuID
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

struct PendingOrder: Identifiable {
    let id: String
    let chefID: String
    let buyerID: String
    let buyerName: String
    let items: [PendingOrderItem]
    let total: Double
    var status: String
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

// MARK: - Menu Model

struct Menu: Identifiable, Equatable {
    var id: String
    var name: String
    var creatorID: String
    var memberIDs: [String]
    var createdAt: Date

    init?(from doc: QueryDocumentSnapshot) {
        let d = doc.data(with: .estimate)
        guard let name      = d["name"]      as? String,
              let creatorID = d["creatorID"] as? String,
              let memberIDs = d["memberIDs"] as? [String]
        else { return nil }
        self.id        = doc.documentID
        self.name      = name
        self.creatorID = creatorID
        self.memberIDs = memberIDs
        self.createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

// MARK: - Invitation Model

struct Invitation: Identifiable {
    var id: String
    var menuID: String
    var menuName: String
    var fromUserID: String
    var fromUsername: String
    var toUserID: String
    var toUsername: String
    var status: String
    var createdAt: Date

    init?(from doc: QueryDocumentSnapshot) {
        let d = doc.data(with: .estimate)
        guard let menuID       = d["menuID"]       as? String,
              let menuName     = d["menuName"]     as? String,
              let fromUserID   = d["fromUserID"]   as? String,
              let fromUsername = d["fromUsername"] as? String,
              let toUserID     = d["toUserID"]     as? String,
              let toUsername   = d["toUsername"]   as? String,
              let status       = d["status"]       as? String
        else { return nil }
        self.id           = doc.documentID
        self.menuID       = menuID
        self.menuName     = menuName
        self.fromUserID   = fromUserID
        self.fromUsername = fromUsername
        self.toUserID     = toUserID
        self.toUsername   = toUsername
        self.status       = status
        self.createdAt    = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

// MARK: - AppStore

class AppStore: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var dishes: [Dish]                = []
    @Published var myAllDishes: [Dish]           = []
    @Published var cartItems: [CartItem]         = []
    @Published var orderHistory: [OrderRecord]   = []
    @Published var topUpHistory: [TopUpRecord]   = []
    @Published var pendingOrders: [PendingOrder] = []
    @Published var myMenus: [Menu]               = []
    @Published var currentMenu: Menu?
    @Published var pendingInvitations: [Invitation] = []
    @Published var isLoadingAuth                 = true
    @Published var needsUsername                 = false

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var dishesListener: ListenerRegistration?

    init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            DispatchQueue.main.async {
                if let uid = firebaseUser?.uid {
                    self?.startListeners(uid: uid)
                } else {
                    self?.stopListeners()
                    self?.currentUser        = nil
                    self?.dishes             = []
                    self?.myAllDishes        = []
                    self?.cartItems          = []
                    self?.orderHistory       = []
                    self?.topUpHistory       = []
                    self?.pendingOrders      = []
                    self?.myMenus            = []
                    self?.currentMenu        = nil
                    self?.pendingInvitations = []
                    self?.needsUsername      = false
                    self?.isLoadingAuth      = false
                }
            }
        }
    }

    // MARK: Computed

    var isLoggedIn: Bool            { currentUser != nil }
    var cartTotal: Double           { cartItems.reduce(0) { $0 + $1.subtotal } }
    var cartCount: Int              { cartItems.reduce(0) { $0 + $1.quantity } }
    var isMemberOfAnyMenu: Bool     { !myMenus.isEmpty }
    var pendingInvitationCount: Int { pendingInvitations.count }
    var ownedMenuCount: Int {
        guard let uid = currentUser?.id else { return 0 }
        return myMenus.filter { $0.creatorID == uid }.count
    }

    // MARK: - Listeners

    private func startListeners(uid: String) {
        stopListeners()

        // User doc — balance, username, defaultMenuID
        let userListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                DispatchQueue.main.async {
                    if let d = snap?.data() {
                        let defaultMenuID = d["defaultMenuID"] as? String
                        self?.currentUser = AppUser(
                            id:              uid,
                            username:        d["username"]        as? String ?? "",
                            email:           d["email"]           as? String ?? "",
                            balance:         (d["balance"] as? NSNumber)?.doubleValue ?? 0,
                            profilePhotoURL: d["profilePhotoURL"] as? String,
                            defaultMenuID:   defaultMenuID
                        )
                        self?.needsUsername = false
                        // Switch to default menu if loaded after the menus listener
                        if let defaultID = defaultMenuID,
                           self?.currentMenu?.id != defaultID,
                           let menu = self?.myMenus.first(where: { $0.id == defaultID }) {
                            self?.switchMenu(menu)
                        }
                    }
                    self?.isLoadingAuth = false
                }
            }

        // Menus where user is a member
        let menusListener = db.collection("menus")
            .whereField("memberIDs", arrayContains: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    let menus = snap.documents.compactMap { Menu(from: $0) }
                        .sorted { $0.createdAt < $1.createdAt }
                    self?.myMenus = menus

                    if let current = self?.currentMenu,
                       let updated = menus.first(where: { $0.id == current.id }) {
                        // Keep currentMenu in sync with live data
                        self?.currentMenu = updated
                    } else if self?.currentMenu == nil, !menus.isEmpty {
                        // First load: pick default or first menu
                        let defaultID = self?.currentUser?.defaultMenuID
                        let target = menus.first(where: { $0.id == defaultID }) ?? menus.first
                        if let menu = target { self?.switchMenu(menu) }
                    }
                }
            }

        // Invitations addressed to this user
        let invitationsListener = db.collection("invitations")
            .whereField("toUserID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    self?.pendingInvitations = snap.documents
                        .compactMap { Invitation(from: $0) }
                        .filter { $0.status == "pending" }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }

        // Order history for this user as buyer
        let ordersListener = db.collection("orders")
            .whereField("buyerID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    let records: [OrderRecord] = snap.documents.compactMap { doc in
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
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    let records: [TopUpRecord] = snap.documents.compactMap { doc in
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

        // Chef's incoming orders
        let chefOrdersListener = db.collection("orders")
            .whereField("chefID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    self?.pendingOrders = snap.documents.compactMap { doc -> PendingOrder? in
                        let d = doc.data(with: .estimate)
                        guard let chefID    = d["chefID"]    as? String,
                              let buyerID   = d["buyerID"]   as? String,
                              let buyerName = d["buyerName"] as? String
                        else { return nil }
                        let total     = (d["total"]  as? NSNumber)?.doubleValue ?? 0
                        let status    =  d["status"] as? String ?? "pending"
                        let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                        let items = (d["items"] as? [[String: Any]] ?? []).compactMap { item -> PendingOrderItem? in
                            guard let dn = item["dishName"] as? String else { return nil }
                            let qty   = (item["quantity"] as? NSNumber)?.intValue    ?? 1
                            let price = (item["price"]    as? NSNumber)?.doubleValue ?? 0
                            return PendingOrderItem(dishName: dn, quantity: qty, price: price)
                        }
                        return PendingOrder(id: doc.documentID, chefID: chefID,
                                            buyerID: buyerID, buyerName: buyerName,
                                            items: items, total: total,
                                            status: status, createdAt: createdAt)
                    }.sorted { $0.createdAt > $1.createdAt }
                }
            }

        // All dishes owned by this user (across all menus) — for Profile "My Dishes"
        let myDishesListener = db.collection("dishes")
            .whereField("ownerID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    self?.myAllDishes = snap.documents.compactMap { Dish(from: $0) }
                }
            }

        listeners = [userListener, menusListener, invitationsListener,
                     ordersListener, topupsListener, chefOrdersListener,
                     myDishesListener]
    }

    // Switch to a different menu — clears cart and restarts the dishes listener.
    func switchMenu(_ menu: Menu) {
        guard currentMenu?.id != menu.id else { return }
        currentMenu = menu
        cartItems.removeAll()
        startDishesListener(menuID: menu.id)
    }

    private func startDishesListener(menuID: String) {
        dishesListener?.remove()
        dishesListener = db.collection("dishes")
            .whereField("menuID", isEqualTo: menuID)
            .addSnapshotListener { [weak self] snap, error in
                if let error = error {
                    print("[Dishes] listener error: \(error.localizedDescription)")
                    return
                }
                guard let snap = snap else { return }
                DispatchQueue.main.async {
                    self?.dishes = snap.documents.compactMap { Dish(from: $0) }
                    print("[Dishes] loaded \(self?.dishes.count ?? 0) for menu \(menuID)")
                }
            }
    }

    var pendingOrderCount: Int {
        pendingOrders.filter { $0.status == "pending" }.count
    }

    private func stopListeners() {
        listeners.forEach { $0.remove() }
        dishesListener?.remove()
        dishesListener = nil
        listeners = []
    }

    // MARK: - Menu Management

    func createMenu(name: String, completion: @escaping (Bool, String) -> Void) {
        guard let user = currentUser else { return }
        guard ownedMenuCount < 3 else {
            completion(false, "You can only create up to 3 menus."); return
        }
        db.collection("menus").addDocument(data: [
            "name":      name,
            "creatorID": user.id,
            "memberIDs": [user.id],
            "createdAt": FieldValue.serverTimestamp()
        ]) { error in
            DispatchQueue.main.async {
                completion(error == nil, error?.localizedDescription ?? "")
            }
        }
    }

    func setDefaultMenu(_ menu: Menu, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id else { return }
        db.collection("users").document(uid)
            .updateData(["defaultMenuID": menu.id]) { error in
                DispatchQueue.main.async {
                    completion(error == nil, error?.localizedDescription ?? "")
                }
            }
    }

    func updateMenuName(_ menu: Menu, name: String, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id, uid == menu.creatorID else {
            completion(false, "Only the creator can rename this menu."); return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { completion(false, "Name cannot be empty."); return }
        db.collection("menus").document(menu.id)
            .updateData(["name": trimmed]) { error in
                DispatchQueue.main.async {
                    completion(error == nil, error?.localizedDescription ?? "")
                }
            }
    }

    func deleteMenu(_ menu: Menu, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id, uid == menu.creatorID else {
            completion(false, "Only the creator can delete this menu."); return
        }

        // 1. Unlink all dishes from this menu (set menuID to "")
        db.collection("dishes").whereField("menuID", isEqualTo: menu.id)
            .getDocuments { [weak self] snap, _ in
                guard let self = self else { return }
                let batch = self.db.batch()

                for doc in snap?.documents ?? [] {
                    batch.updateData(["menuID": ""], forDocument: doc.reference)
                }

                // 2. Delete the menu document
                batch.deleteDocument(self.db.collection("menus").document(menu.id))

                batch.commit { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(false, error.localizedDescription); return
                        }
                        // 3. Clear defaultMenuID if this was the default
                        if self.currentUser?.defaultMenuID == menu.id {
                            self.db.collection("users").document(uid)
                                .updateData(["defaultMenuID": FieldValue.delete()])
                        }
                        // 4. Switch away from deleted menu
                        if self.currentMenu?.id == menu.id {
                            self.currentMenu = nil
                            self.dishes = []
                            self.dishesListener?.remove()
                            self.dishesListener = nil
                            // Pick another menu if available
                            if let next = self.myMenus.first(where: { $0.id != menu.id }) {
                                self.switchMenu(next)
                            }
                        }
                        completion(true, "")
                    }
                }
            }
    }

    func removeMember(uid memberUID: String, from menu: Menu,
                      completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id, uid == menu.creatorID else {
            completion(false, "Only the creator can remove members."); return
        }
        guard memberUID != menu.creatorID else {
            completion(false, "Cannot remove the creator."); return
        }

        // 1. Remove member from the menu's memberIDs
        let menuRef = db.collection("menus").document(menu.id)

        // 2. Delete that member's dishes from this menu
        db.collection("dishes")
            .whereField("menuID", isEqualTo: menu.id)
            .whereField("ownerID", isEqualTo: memberUID)
            .getDocuments { [weak self] snap, _ in
                guard let self = self else { return }
                let batch = self.db.batch()

                batch.updateData(["memberIDs": FieldValue.arrayRemove([memberUID])],
                                 forDocument: menuRef)

                for doc in snap?.documents ?? [] {
                    batch.deleteDocument(doc.reference)
                }

                batch.commit { error in
                    DispatchQueue.main.async {
                        completion(error == nil, error?.localizedDescription ?? "")
                    }
                }
            }
    }

    func loadMemberUsernames(for memberIDs: [String],
                             completion: @escaping ([String: String]) -> Void) {
        guard !memberIDs.isEmpty else { completion([:]); return }
        // Firestore 'in' query supports up to 30 values
        let chunks = stride(from: 0, to: memberIDs.count, by: 30).map {
            Array(memberIDs[$0..<min($0 + 30, memberIDs.count)])
        }
        var result: [String: String] = [:]
        let group = DispatchGroup()
        for chunk in chunks {
            group.enter()
            db.collection("users").whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { snap, _ in
                    for doc in snap?.documents ?? [] {
                        let username = doc.data()["username"] as? String ?? doc.documentID
                        result[doc.documentID] = username
                    }
                    group.leave()
                }
        }
        group.notify(queue: .main) { completion(result) }
    }

    // MARK: - Invitations

    func inviteUser(username: String, to menu: Menu,
                    completion: @escaping (Bool, String) -> Void) {
        guard let user = currentUser else { return }
        guard menu.creatorID == user.id else {
            completion(false, "Only the menu creator can invite."); return
        }
        // 1. Look up invitee by username
        db.collection("users").whereField("username", isEqualTo: username)
            .getDocuments { [weak self] snap, _ in
                guard let doc = snap?.documents.first else {
                    DispatchQueue.main.async { completion(false, "User '\(username)' not found.") }
                    return
                }
                let inviteeID = doc.documentID
                guard inviteeID != user.id else {
                    DispatchQueue.main.async { completion(false, "You can't invite yourself.") }
                    return
                }
                guard !menu.memberIDs.contains(inviteeID) else {
                    DispatchQueue.main.async { completion(false, "\(username) is already a member.") }
                    return
                }
                let inviteeUsername = doc.data()["username"] as? String ?? username
                // 2. Check for existing pending invitation (client-side filter)
                self?.db.collection("invitations")
                    .whereField("menuID",   isEqualTo: menu.id)
                    .whereField("toUserID", isEqualTo: inviteeID)
                    .getDocuments { snap, _ in
                        let hasPending = snap?.documents
                            .compactMap { Invitation(from: $0) }
                            .contains(where: { $0.status == "pending" }) ?? false
                        if hasPending {
                            DispatchQueue.main.async {
                                completion(false, "Invitation already sent to \(username).")
                            }
                            return
                        }
                        // 3. Create invitation
                        self?.db.collection("invitations").addDocument(data: [
                            "menuID":       menu.id,
                            "menuName":     menu.name,
                            "fromUserID":   user.id,
                            "fromUsername": user.username,
                            "toUserID":     inviteeID,
                            "toUsername":   inviteeUsername,
                            "status":       "pending",
                            "createdAt":    FieldValue.serverTimestamp()
                        ]) { error in
                            DispatchQueue.main.async {
                                completion(error == nil, error?.localizedDescription ?? "")
                            }
                        }
                    }
            }
    }

    func acceptInvitation(_ invitation: Invitation, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id else { return }
        let menuRef = db.collection("menus").document(invitation.menuID)
        let invRef  = db.collection("invitations").document(invitation.id)
        db.runTransaction({ transaction, errorPointer in
            transaction.updateData(["memberIDs": FieldValue.arrayUnion([uid])],
                                   forDocument: menuRef)
            transaction.updateData(["status": "accepted"], forDocument: invRef)
            return nil
        }) { _, error in
            DispatchQueue.main.async {
                completion(error == nil, error?.localizedDescription ?? "")
            }
        }
    }

    func declineInvitation(_ invitation: Invitation, completion: @escaping (Bool, String) -> Void) {
        db.collection("invitations").document(invitation.id)
            .updateData(["status": "declined"]) { error in
                DispatchQueue.main.async {
                    completion(error == nil, error?.localizedDescription ?? "")
                }
            }
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
                ])
                completion(true, "")
            }
        }
    }

    // MARK: - Dish Management

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
                 menuID: String? = nil,
                 completion: @escaping (Bool, String) -> Void) {
        guard let user = currentUser else { completion(false, "Not logged in."); return }
        let targetMenuID = menuID ?? currentMenu?.id
        guard let targetMenuID, !targetMenuID.isEmpty else {
            completion(false, "No menu selected. Pick a menu first."); return
        }
        let dishID = UUID().uuidString

        func write(imageURL: String?) {
            let data: [String: Any] = [
                "name": name, "price": price, "imageURL": imageURL as Any,
                "ownerID": user.id, "ownerName": user.username,
                "category": category,
                "menuID": targetMenuID,
                "createdAt": FieldValue.serverTimestamp()
            ]
            db.collection("dishes").document(dishID).setData(data) { error in
                DispatchQueue.main.async { completion(error == nil, error?.localizedDescription ?? "") }
            }
        }

        if let image { write(imageURL: prepareImageBase64(image)) }
        else { write(imageURL: nil) }
    }

    func moveDish(_ dish: Dish, toMenuID: String, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id, uid == dish.ownerID else {
            completion(false, "You can only move your own dishes."); return
        }
        db.collection("dishes").document(dish.id)
            .updateData(["menuID": toMenuID]) { error in
                DispatchQueue.main.async {
                    completion(error == nil, error?.localizedDescription ?? "")
                }
            }
    }

    /// Any menu member can remove a dish from the menu (unlinks it; dish stays under the chef).
    func removeDishFromMenu(_ dish: Dish) {
        db.collection("dishes").document(dish.id)
            .updateData(["menuID": ""])
        cartItems.removeAll { $0.dish.id == dish.id }
    }

    func updateDish(_ dish: Dish, name: String, price: Double, newImage: UIImage?, category: String,
                    completion: @escaping (Bool, String) -> Void) {
        func write(imageURL: String?) {
            var data: [String: Any] = ["name": name, "price": price, "category": category]
            if let url = imageURL { data["imageURL"] = url }
            db.collection("dishes").document(dish.id).setData(data, merge: true) { error in
                DispatchQueue.main.async { completion(error == nil, error?.localizedDescription ?? "") }
            }
        }

        if let newImage { write(imageURL: prepareImageBase64(newImage)) }
        else { write(imageURL: nil) }
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
        guard let buyer = currentUser else { return }
        let total = cartTotal
        guard total > 0 else { return }

        let selfEarned = cartItems
            .filter { $0.dish.ownerID == buyer.id }
            .reduce(0.0) { $0 + $1.subtotal }
        let effectiveDeduction = total - selfEarned

        // Group all items by chef (including buyer's own dishes for order visibility)
        var itemsByChef: [String: [CartItem]] = [:]
        for item in cartItems {
            itemsByChef[item.dish.ownerID, default: []].append(item)
        }

        let buyerRef  = db.collection("users").document(buyer.id)
        let orderRefs: [String: DocumentReference] = itemsByChef.mapValues { _ in
            db.collection("orders").document()
        }

        db.runTransaction({ transaction, errorPointer in

            let buyerSnap: DocumentSnapshot
            do { buyerSnap = try transaction.getDocument(buyerRef) }
            catch let e as NSError { errorPointer?.pointee = e; return nil }

            let buyerBalance = (buyerSnap.data()?["balance"] as? NSNumber)?.doubleValue ?? -1
            guard buyerBalance >= 0, buyerBalance >= effectiveDeduction else {
                let msg = buyerBalance < 0 ? "Could not read balance" : "Insufficient funds"
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
                // Self-orders carry total=0 — buyer was never charged, chef not credited
                let chefTotal = chefID == buyer.id ? 0.0 : chefItems.reduce(0.0) { $0 + $1.subtotal }
                let itemData: [[String: Any]] = chefItems.map { item in [
                    "dishName": item.dish.name,
                    "chefName": item.dish.ownerName,
                    "quantity": item.quantity,
                    "price":    item.dish.price
                ]}
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
                    completion(false, error.localizedDescription, 0)
                    return
                }
                self?.cartItems.removeAll()
                completion(true, "", effectiveDeduction)
            }
        }
    }

    // MARK: - Chef Confirmation

    func markDone(order: PendingOrder, completion: @escaping (Bool, String) -> Void) {
        guard let uid = currentUser?.id else {
            completion(false, "Not logged in"); return
        }
        guard uid == order.chefID else {
            completion(false, "Unauthorized"); return
        }

        let orderRef  = db.collection("orders").document(order.id)
        let chefRef   = db.collection("users").document(uid)
        let ledgerRef = db.collection("payoutLedger").document(order.id)

        db.runTransaction({ transaction, errorPointer in

            let orderSnap: DocumentSnapshot
            do { orderSnap = try transaction.getDocument(orderRef) }
            catch let e as NSError { errorPointer?.pointee = e; return nil }

            let ledgerSnap: DocumentSnapshot
            do { ledgerSnap = try transaction.getDocument(ledgerRef) }
            catch let e as NSError { errorPointer?.pointee = e; return nil }

            if orderSnap.data()?["status"] as? String == "completed" { return nil }

            if !ledgerSnap.exists && order.total > 0 {
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

            transaction.updateData([
                "status":      "completed",
                "completedAt": FieldValue.serverTimestamp()
            ], forDocument: orderRef)
            return nil

        }) { _, error in
            DispatchQueue.main.async {
                completion(error == nil, error?.localizedDescription ?? "")
            }
        }
    }
}
