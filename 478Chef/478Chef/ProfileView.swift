import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @State private var navPath            = NavigationPath()
    @State private var showSignOutConfirm = false
    @State private var showEditProfile    = false
    @State private var showTopUp          = false
    @State private var dishToEdit: Dish?
    @State private var myDishesExpanded = false

    private var myDishes: [Dish] {
        store.dishes.filter { $0.ownerID == store.currentUser?.id }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                // Avatar + username
                Section {
                    HStack(spacing: 16) {
                        DishThumbnail(imageURL: store.currentUser?.profilePhotoURL, size: 72)
                        Text(store.currentUser?.username ?? "")
                            .font(.title2).fontWeight(.bold)
                    }
                    .padding(.vertical, 6)
                }

                // Wallet
                Section("Wallet") {
                    HStack {
                        Label("Balance", systemImage: "dollarsign.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text(String(format: "$%.2f", store.currentUser?.balance ?? 0))
                            .fontWeight(.semibold).foregroundColor(.green)
                    }
                    .padding(.vertical, 2)

                    Button {
                        showTopUp = true
                    } label: {
                        Label("Top Up", systemImage: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                }

                // Activity
                Section("Activity") {
                    NavigationLink(value: "orderHistory") {
                        HStack {
                            Label("Order History", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(store.orderHistory.count)")
                                .foregroundColor(.secondary).font(.subheadline)
                        }
                    }
                    NavigationLink(value: "topUpHistory") {
                        HStack {
                            Label("Top-up History", systemImage: "arrow.up.circle.fill")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(store.topUpHistory.count)")
                                .foregroundColor(.secondary).font(.subheadline)
                        }
                    }
                }

                // My dishes as chef — collapsible, with edit/delete swipe actions
                Section {
                    DisclosureGroup(isExpanded: $myDishesExpanded) {
                        if myDishes.isEmpty {
                            Text("You haven't added any dishes yet.")
                                .foregroundColor(.secondary).font(.subheadline)
                        } else {
                            ForEach(myDishes) { dish in
                                HStack(spacing: 12) {
                                    DishThumbnail(imageURL: dish.imageURL, size: 52)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(dish.name)
                                            .font(.subheadline).fontWeight(.medium)
                                        Text(String(format: "$%.2f per order", dish.price))
                                            .font(.caption).foregroundColor(.secondary)
                                        Text(dish.category)
                                            .font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.12))
                                            .foregroundColor(.orange)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button { dishToEdit = dish } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.deleteDish(dish)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("My Dishes (\(myDishes.count))")
                            .fontWeight(.semibold)
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) { showSignOutConfirm = true } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .navigationDestination(for: String.self) { destination in
                if destination == "topUpHistory" {
                    TopUpHistoryView()
                } else {
                    OrderHistoryView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditProfile = true } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .confirmationDialog(
                "Sign out of \(store.currentUser?.username ?? "your account")?",
                isPresented: $showSignOutConfirm, titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) { store.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your cart will be cleared.")
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(currentUsername: store.currentUser?.username ?? "")
            }
            .sheet(isPresented: $showTopUp) {
                TopUpView()
            }
            .sheet(item: $dishToEdit) { dish in
                EditDishView(dish: dish)
            }
        }
    }
}

// MARK: - Top-up History View

struct TopUpHistoryView: View {
    @EnvironmentObject var store: AppStore

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if store.topUpHistory.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 60)).foregroundColor(.secondary)
                    Text("No top-ups yet")
                        .font(.title2).fontWeight(.semibold)
                    Text("Your top-up history will appear here.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                List {
                    Section("💵 Top-up History") {
                        ForEach(store.topUpHistory) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Self.dateFormatter.string(from: record.date))
                                        .font(.subheadline).fontWeight(.medium)
                                    Text("Balance top-up")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "+$%.2f", record.amount))
                                    .font(.headline).foregroundColor(.green)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Top-up History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var username: String
    @State private var newImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var isSaving  = false
    @State private var errorMsg  = ""

    init(currentUsername: String) {
        _username = State(initialValue: currentUsername)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Username") {
                    TextField("Username", text: $username)
                }

                Section("Profile Photo") {
                    Button { showPhotoPicker = true } label: {
                        HStack(spacing: 16) {
                            if let newImage {
                                Image(uiImage: newImage)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                DishThumbnail(imageURL: store.currentUser?.profilePhotoURL, size: 72)
                            }
                            Text(newImage != nil ? "Change Photo" : "Add Photo")
                                .font(.headline).foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $showPhotoPicker) {
                    CroppableImagePicker(image: $newImage)
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.circle")
                            .foregroundColor(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("✏️ Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMsg = "Username cannot be empty."; return }
        isSaving = true
        store.updateProfile(username: trimmed, photo: newImage) { ok, msg in
            isSaving = false
            if ok { dismiss() }
            else  { errorMsg = msg }
        }
    }
}

// MARK: - Top Up View

struct TopUpView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var amountText  = ""
    @State private var isProcessing = false
    @State private var errorMsg     = ""
    @FocusState private var focused: Bool

    private var amount: Double? {
        guard let d = Double(amountText), d > 0, d <= 200 else { return nil }
        return d
    }
    private var isValid: Bool { amount != nil }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Text("$")
                            .font(.title2).foregroundColor(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                            .focused($focused)
                            .onChange(of: amountText) { val in
                                // strip leading zeros
                                if val.hasPrefix("0") && val.count > 1 && !val.hasPrefix("0.") {
                                    amountText = String(val.drop(while: { $0 == "0" }))
                                }
                            }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Max: $200")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "Current balance: $%.2f", store.currentUser?.balance ?? 0))
                            .font(.caption).foregroundColor(.secondary)
                    }

                    // Quick-pick amounts
                    HStack(spacing: 10) {
                        ForEach([10, 20, 50, 100, 200], id: \.self) { preset in
                            Button { amountText = "\(preset)" } label: {
                                Text("$\(preset)")
                                    .font(.caption).fontWeight(.semibold)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(amountText == "\(preset)"
                                                ? Color.green : Color.secondary.opacity(0.12))
                                    .foregroundColor(amountText == "\(preset)" ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("💵 Amount")
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.circle")
                            .foregroundColor(.red).font(.footnote)
                    }
                }

                Section {
                    Button(action: topUp) {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                Text(isValid
                                     ? String(format: "Top Up $%.2f", amount ?? 0)
                                     : "Enter an amount (max $200)")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(isValid ? Color.green : Color.secondary.opacity(0.3))
                        .cornerRadius(10)
                    }
                    .disabled(!isValid || isProcessing)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
            }
            .navigationTitle("💰 Top Up Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .onAppear { focused = true }
    }

    private func topUp() {
        guard let a = amount else { return }
        isProcessing = true
        store.topUp(amount: a) { ok, msg in
            isProcessing = false
            if ok { dismiss() }
            else  { errorMsg = msg }
        }
    }
}
