import SwiftUI

struct OrderHistoryView: View {
    @EnvironmentObject var store: AppStore

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if store.orderHistory.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60)).foregroundColor(.secondary)
                    Text("No orders yet")
                        .font(.title2).fontWeight(.semibold)
                    Text("Your past orders will appear here.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                List {
                    Section("🧾 Orders") {
                        ForEach(store.orderHistory) { order in
                            OrderRow(order: order)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Order History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Order Row

private struct OrderRow: View {
    let order: OrderRecord
    @State private var isExpanded = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dateFormatter.string(from: order.date))
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text("\(order.items.count) item\(order.items.count == 1 ? "" : "s")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(format: "$%.2f", order.total))
                        .font(.headline).foregroundColor(.orange)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Expanded item list
            if isExpanded {
                Divider().padding(.vertical, 6)
                ForEach(Array(order.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.dishName)
                                .font(.subheadline)
                            Text("Chef: \(item.chefName)  ×\(item.quantity)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(String(format: "$%.2f", item.subtotal))
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}
