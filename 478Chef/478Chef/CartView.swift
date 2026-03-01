import SwiftUI

struct CartView: View {
    @EnvironmentObject var store: AppStore

    @State private var showConfirm      = false
    @State private var showSuccess      = false
    @State private var checkoutError    = ""
    @State private var isCheckingOut    = false
    @State private var paidTotal: Double = 0
    @State private var newBalance: Double = 0

    private var canAfford: Bool { store.cartTotal <= (store.currentUser?.balance ?? 0) }

    var body: some View {
        NavigationView {
            Group {
                if store.cartItems.isEmpty { EmptyCartView() }
                else { cartList }
            }
            .navigationTitle("Cart")
        }
        .alert("Confirm Payment", isPresented: $showConfirm) {
            Button(String(format: "Pay $%.2f", store.cartTotal), role: .destructive) {
                pay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(format: "Pay $%.2f? Chefs will confirm your items before receiving payment.", store.cartTotal))
        }
        .alert("Payment Successful!", isPresented: $showSuccess) {
            Button("OK") {}
        } message: {
            Text(String(format: "Charged $%.2f.\nNew balance: $%.2f", paidTotal, newBalance))
        }
        .alert("Payment Failed", isPresented: .constant(!checkoutError.isEmpty)) {
            Button("OK") { checkoutError = "" }
        } message: {
            Text(checkoutError)
        }
    }

    // MARK: - Cart List

    private var cartList: some View {
        List {
            Section("Items") {
                ForEach(store.cartItems) { item in CartItemRow(item: item) }
            }
            Section {
                // Total
                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(String(format: "$%.2f", store.cartTotal))
                        .font(.headline)
                        .foregroundColor(canAfford ? .primary : .red)
                }
                // Balance
                HStack {
                    Text("Your Balance").foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", store.currentUser?.balance ?? 0))
                        .foregroundColor(.green).fontWeight(.medium)
                }
                // Warning
                if !canAfford {
                    Label(String(format: "Need $%.2f more",
                                 store.cartTotal - (store.currentUser?.balance ?? 0)),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.footnote)
                }
                // Pay button
                Button { showConfirm = true } label: {
                    HStack {
                        Spacer()
                        if isCheckingOut {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "creditcard.fill")
                            Text(canAfford ? "Pay Now" : "Insufficient Balance")
                                .fontWeight(.bold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(canAfford ? Color.orange : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canAfford || isCheckingOut)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func pay() {
        let balanceBefore = store.currentUser?.balance ?? 0
        isCheckingOut = true
        paidTotal = store.cartTotal
        store.checkout { ok, msg, deducted in
            isCheckingOut = false
            if ok {
                newBalance = balanceBefore - deducted
                showSuccess = true
            } else {
                checkoutError = msg
            }
        }
    }
}

// MARK: - Empty Cart

private struct EmptyCartView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cart")
                .font(.system(size: 64)).foregroundColor(.secondary)
            Text("Your cart is empty")
                .font(.title2).fontWeight(.semibold)
            Text("Browse the menu and add items!")
                .font(.subheadline).foregroundColor(.secondary)
        }
    }
}

// MARK: - Cart Item Row

struct CartItemRow: View {
    @EnvironmentObject var store: AppStore
    let item: CartItem

    var body: some View {
        HStack(spacing: 12) {
            DishThumbnail(imageURL: item.dish.imageURL, size: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.dish.name)
                    .font(.subheadline).fontWeight(.medium)
                Text(String(format: "$%.2f × %d  •  Chef: %@",
                            item.dish.price, item.quantity, item.dish.ownerName))
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button { store.decrement(item.dish) } label: {
                    Image(systemName: "minus.circle.fill").foregroundColor(.orange)
                }.buttonStyle(.plain)

                Text("\(item.quantity)")
                    .font(.subheadline).fontWeight(.medium)
                    .frame(minWidth: 20, alignment: .center)

                Button { store.increment(item.dish) } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                }.buttonStyle(.plain)
            }

            Text(String(format: "$%.2f", item.subtotal))
                .font(.subheadline).fontWeight(.semibold)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
