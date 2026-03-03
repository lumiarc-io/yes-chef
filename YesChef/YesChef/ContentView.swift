import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.isLoadingAuth {
                VStack(spacing: 16) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)
                    ProgressView()
                }
            } else if store.isLoggedIn {
                MainTabView()
            } else {
                AuthView()
            }
        }
    }
}

// MARK: - Main Tabs

struct MainTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.isMemberOfAnyMenu {
            TabView {
                MenuView()
                    .tabItem { Label("Menu", systemImage: "fork.knife") }

                CartView()
                    .tabItem { Label("Cart", systemImage: "cart.fill") }
                    .badge(store.cartCount)

                ChefOrdersView()
                    .tabItem { Label("Orders", systemImage: "bell.fill") }
                    .badge(store.pendingOrderCount)

                InvitationsView()
                    .tabItem { Label("Invitations", systemImage: "envelope.fill") }
                    .badge(store.pendingInvitationCount)

                ProfileView()
                    .tabItem { Label("Profile", systemImage: "person.fill") }
            }
            .tint(.orange)
        } else {
            // No menu membership yet — show Orders + Invitations + Profile.
            // Chef orders are not menu-specific; a user may have incoming orders
            // even before creating or joining a menu.
            TabView {
                ChefOrdersView()
                    .tabItem { Label("Orders", systemImage: "bell.fill") }
                    .badge(store.pendingOrderCount)

                InvitationsView()
                    .tabItem { Label("Invitations", systemImage: "envelope.fill") }
                    .badge(store.pendingInvitationCount)

                ProfileView()
                    .tabItem { Label("Profile", systemImage: "person.fill") }
            }
            .tint(.orange)
        }
    }
}

// MARK: - Chef Orders View

struct ChefOrdersView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 0

    private var pendingOrders: [PendingOrder] {
        store.pendingOrders.filter { $0.status == "pending" }
    }
    private var completedOrders: [PendingOrder] {
        store.pendingOrders.filter { $0.status == "completed" }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text(pendingOrders.isEmpty ? "Pending" : "Pending (\(pendingOrders.count))")
                        .tag(0)
                    Text("Completed").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 10)

                Divider()

                if selectedTab == 0 { pendingTab } else { completedTab }
            }
            .navigationTitle("Incoming Orders")
        }
    }

    @ViewBuilder private var pendingTab: some View {
        if pendingOrders.isEmpty {
            emptyState(icon: "tray", title: "No pending orders",
                       detail: "Orders for your dishes will appear here.")
        } else {
            List { ForEach(pendingOrders) { OrderCard(order: $0) } }
                .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder private var completedTab: some View {
        if completedOrders.isEmpty {
            emptyState(icon: "checkmark.seal", title: "No completed orders",
                       detail: "Fulfilled orders will appear here.")
        } else {
            List { ForEach(completedOrders) { OrderCard(order: $0) } }
                .listStyle(.insetGrouped)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon).font(.system(size: 60)).foregroundColor(.secondary)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(detail).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - Order Card

private struct OrderCard: View {
    @EnvironmentObject var store: AppStore
    let order: PendingOrder

    @State private var isProcessing = false
    @State private var errorMsg     = ""

    private var isPending: Bool { order.status == "pending" }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From \(order.buyerName)")
                        .font(.subheadline).fontWeight(.semibold)
                    Text(Self.fmt.string(from: order.createdAt))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(order.total > 0 ? String(format: "+$%.2f", order.total) : "Self order")
                    .font(.headline)
                    .foregroundColor(isPending ? .green : .secondary)
            }

            Divider()

            ForEach(order.items) { item in
                HStack {
                    Text(item.dishName).font(.subheadline)
                    Spacer()
                    Text("×\(item.quantity)")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                    Text(String(format: "$%.2f", item.subtotal))
                        .font(.caption).fontWeight(.medium)
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }

            if !errorMsg.isEmpty {
                Label(errorMsg, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundColor(.red)
            }

            if isPending {
                Button(action: markDone) {
                    HStack {
                        Spacer()
                        if isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Mark as Done").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text("Completed — payment credited")
                        .font(.subheadline).foregroundColor(.green)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func markDone() {
        isProcessing = true
        errorMsg = ""
        store.markDone(order: order) { ok, msg in
            isProcessing = false
            if !ok { errorMsg = msg }
        }
    }
}
