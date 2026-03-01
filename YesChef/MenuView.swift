import SwiftUI
import FirebaseFirestore

// MARK: - Helpers

private let categoryMeta: [(name: String, emoji: String)] = [
    ("Main Dish",     "🍽"),
    ("Small Plates",  "🥗"),
    ("Noodle & Rice", "🍜"),
    ("Dessert",       "🍰"),
    ("Drink",         "🧋"),
]

private func categoryEmoji(for category: String) -> String {
    categoryMeta.first { $0.name == category }?.emoji ?? "🍴"
}

// MARK: - Chef Reference (for sheet presentation)

struct ChefRef: Identifiable {
    var id: String   // ownerID
    var name: String
}

// MARK: - Menu View

// Tracks each category header's global Y — used for both scrollspy and sticky-bar visibility.
private struct CategoryPositionKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct MenuView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAddDish          = false
    @State private var activeCategory: String? = nil
    @State private var showCategoryBar      = false
    @State private var isProgrammaticScroll = false

    private var groupedDishes: [(String, [Dish])] {
        let grouped = Dictionary(grouping: store.dishes, by: { $0.category })
        var result: [(String, [Dish])] = []
        for cat in dishCategories {
            if let dishes = grouped[cat], !dishes.isEmpty { result.append((cat, dishes)) }
        }
        for (cat, dishes) in grouped where !dishCategories.contains(cat) {
            result.append((cat, dishes))
        }
        return result
    }

    var body: some View {
        NavigationView {
            Group {
                if store.dishes.isEmpty {
                    EmptyMenuView()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(groupedDishes, id: \.0) { category, dishes in
                                    // Category title — reports Y position for scrollspy
                                    Text(category)
                                        .font(.title2).fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 16)
                                        .padding(.bottom, 8)
                                        .id(category)
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear.preference(
                                                    key: CategoryPositionKey.self,
                                                    value: [category: geo.frame(in: .global).minY]
                                                )
                                            }
                                        )

                                    // Dishes in white rounded card
                                    VStack(spacing: 0) {
                                        ForEach(dishes) { dish in
                                            VStack(spacing: 0) {
                                                DishRow(dish: dish)
                                                    .padding(.horizontal, 16)
                                                if dish.id != dishes.last?.id {
                                                    Divider().padding(.horizontal, 16)
                                                }
                                            }
                                        }
                                    }
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.bottom, 24)
                        }
                        .background(Color(.systemGroupedBackground))
                        .onPreferenceChange(CategoryPositionKey.self) { positions in
                            guard !positions.isEmpty else { return }
                            DispatchQueue.main.async {
                                // ── Sticky bar show/hide with hysteresis ─────────────────────
                                // When the tab bar appears via safeAreaInset it shifts all
                                // category headers DOWN ~48 pt. Without hysteresis that shift
                                // pushes the first header back above the show threshold,
                                // hiding the bar again — causing infinite oscillation.
                                // Fix: the hide threshold (140 pt) is 60 pt above the show
                                // threshold (80 pt), which is wider than the bar height (~48 pt),
                                // so the post-appear shift can never cross the hide line.
                                if let firstCat = groupedDishes.first?.0,
                                   let y = positions[firstCat] {
                                    let shouldShow = showCategoryBar ? (y < 140) : (y < 80)
                                    if shouldShow != showCategoryBar {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showCategoryBar = shouldShow
                                        }
                                    }
                                }
                                // ── Scrollspy ────────────────────────────────────────────────
                                if !isProgrammaticScroll {
                                    updateActiveCategory(positions)
                                }
                            }
                        }
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if showCategoryBar {
                                categoryTabBar(listProxy: proxy)
                            }
                        }
                    }
                }
            }
            .navigationTitle("🍽 Our Menu")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Balance")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "$%.2f", store.currentUser?.balance ?? 0))
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                    }
                    .fixedSize()
                    .padding(.leading, 4)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddDish = true } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showAddDish) { AddDishView() }
        }
    }

    // MARK: - Category Tab Bar

    /// Tab bar needs `listProxy` to scroll the dish list when a tab is tapped.
    /// It owns a separate `ScrollViewReader` to auto-scroll itself horizontally.
    private func categoryTabBar(listProxy: ScrollViewProxy) -> some View {
        ScrollViewReader { tabProxy in
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(groupedDishes.map { $0.0 }, id: \.self) { cat in
                            Button { tapCategory(cat, listProxy: listProxy) } label: {
                                VStack(spacing: 0) {
                                    Text(cat)
                                        .font(.subheadline)
                                        .fontWeight(activeCategory == cat ? .semibold : .regular)
                                        .foregroundColor(activeCategory == cat ? .primary : .secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    Rectangle()
                                        .fill(activeCategory == cat ? Color.primary : Color.clear)
                                        .frame(height: 2)
                                }
                                .id("tab_\(cat)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Divider()
            }
            .background(.bar)
            // When the bar first appears, immediately center whatever tab is active
            .onAppear {
                guard let cat = activeCategory else { return }
                tabProxy.scrollTo("tab_\(cat)", anchor: .center)
            }
            // Auto-scroll the tab bar so the active tab stays centered
            .onChange(of: activeCategory) { cat in
                guard let cat else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    tabProxy.scrollTo("tab_\(cat)", anchor: .center)
                }
            }
        }
    }

    // MARK: - Scroll Helpers

    /// Tap a category tab: disable scrollspy, jump to section, re-enable after animation.
    private func tapCategory(_ cat: String, listProxy: ScrollViewProxy) {
        isProgrammaticScroll = true
        activeCategory = cat
        withAnimation(.easeInOut(duration: 0.35)) {
            listProxy.scrollTo(cat, anchor: .top)
        }
        // Re-enable scrollspy after the jump animation finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isProgrammaticScroll = false
        }
    }

    /// Scrollspy: determine which category is currently at the top of the visible area.
    private func updateActiveCategory(_ positions: [String: CGFloat]) {
        guard !positions.isEmpty else { return }
        // Top of visible content: nav bar ~100 pt; add bar height ~48 pt when visible
        let threshold: CGFloat = showCategoryBar ? 148 : 100
        // Active = the last section header that has scrolled above the threshold
        let active = positions
            .filter  { $0.value < threshold }
            .max(by: { $0.value < $1.value })?.key
            ?? positions.min(by: { $0.value < $1.value })?.key
        guard let active, active != activeCategory else { return }
        activeCategory = active
    }
}

// MARK: - Empty State

private struct EmptyMenuView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🍽").font(.system(size: 72))
            Text("No dishes yet")
                .font(.title2).fontWeight(.semibold)
            Text("Tap + to add the first dish to the menu.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Dish Row

struct DishRow: View {
    @EnvironmentObject var store: AppStore
    let dish: Dish

    @State private var selectedChef: ChefRef?
    @State private var showDetail = false

    private var quantity: Int  { store.quantityInCart(for: dish) }
    private var isMyDish: Bool { dish.ownerID == store.currentUser?.id }

    var body: some View {
        HStack(spacing: 14) {
            // Dish thumbnail — opens dish detail
            Button { showDetail = true } label: {
                DishThumbnail(imageURL: dish.imageURL, size: 90)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                // Dish name — opens dish detail
                Button { showDetail = true } label: {
                    Text(dish.name)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Text(String(format: "$%.2f", dish.price))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.orange)

                if isMyDish {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.caption2).foregroundColor(.orange)
                        Text("Your dish")
                            .font(.caption).foregroundColor(.orange)
                    }
                } else {
                    // Chef name — tappable, opens ChefProfileView
                    Button {
                        selectedChef = ChefRef(id: dish.ownerID, name: dish.ownerName)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "person.circle.fill")
                                .font(.caption2)
                            Text(dish.ownerName)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Add / remove controls
            HStack(spacing: 8) {
                if quantity > 0 {
                    Button { store.decrement(dish) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2).foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)

                    Text("\(quantity)")
                        .font(.headline).fontWeight(.bold)
                        .frame(minWidth: 22, alignment: .center)
                }
                Button { store.increment(dish) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showDetail) {
            DishDetailView(dish: dish)
        }
        .sheet(item: $selectedChef) { chef in
            ChefProfileView(ownerID: chef.id, ownerName: chef.name)
        }
    }
}

// MARK: - Chef Profile View

struct ChefProfileView: View {
    @EnvironmentObject var store: AppStore
    let ownerID: String
    let ownerName: String

    @State private var profilePhotoURL: String?

    private var chefDishes: [Dish] {
        store.dishes.filter { $0.ownerID == ownerID }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 16) {
                        DishThumbnail(imageURL: profilePhotoURL, size: 72)
                        Text(ownerName)
                            .font(.title2).fontWeight(.bold)
                    }
                    .padding(.vertical, 6)
                }

                Section("🍳 Dishes") {
                    if chefDishes.isEmpty {
                        Text("No dishes yet.")
                            .foregroundColor(.secondary).font(.subheadline)
                    } else {
                        ForEach(chefDishes) { dish in
                            DishRow(dish: dish)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("👨‍🍳 Chef Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { fetchProfilePhoto() }
    }

    private func fetchProfilePhoto() {
        Firestore.firestore().collection("users").document(ownerID).getDocument { snap, _ in
            if let d = snap?.data() {
                DispatchQueue.main.async {
                    profilePhotoURL = d["profilePhotoURL"] as? String
                }
            }
        }
    }
}

// MARK: - Dish Detail View

struct DishDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let dish: Dish

    @State private var showChef = false
    private var quantity: Int { store.quantityInCart(for: dish) }
    private var isMyDish: Bool { dish.ownerID == store.currentUser?.id }

    /// Status-bar height — needed to position the close button below the notch/island.
    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full-bleed hero image: edge-to-edge, extends under status bar, aspect fill.
            dishImage
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                    // Push the button below the status bar / dynamic island
                    .padding(.top, safeAreaTop + 8)
                    .padding(.leading, 16)
                }

            // Dish info
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(dish.name)
                        .font(.title2).fontWeight(.bold)
                    Text(String(format: "$%.2f", dish.price))
                        .font(.title3).fontWeight(.semibold).foregroundColor(.orange)
                    if isMyDish {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.subheadline).foregroundColor(.orange)
                            Text("Your dish")
                                .font(.subheadline).foregroundColor(.orange)
                        }
                    } else {
                        Button { showChef = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.circle.fill")
                                    .font(.subheadline).foregroundColor(.secondary)
                                Text(dish.ownerName)
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(isPresented: $showChef) {
                ChefProfileView(ownerID: dish.ownerID, ownerName: dish.ownerName)
            }

            Spacer(minLength: 0)

            // Bottom cart controls
            VStack(spacing: 0) {
                Divider()
                if quantity > 0 {
                    HStack(spacing: 24) {
                        Button { store.decrement(dish) } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title).foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        Text("\(quantity)")
                            .font(.title3).fontWeight(.bold)
                            .frame(minWidth: 32, alignment: .center)
                        Button { store.increment(dish) } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title).foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    Button { store.increment(dish); dismiss() } label: {
                        HStack {
                            Spacer()
                            Text(String(format: "Add to Cart  ·  $%.2f", dish.price))
                                .font(.headline).fontWeight(.semibold).foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 18)
                        .background(Color.black)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var dishImage: some View {
        if let urlString = dish.imageURL {
            if urlString.hasPrefix("data:image"),
               let commaIdx = urlString.firstIndex(of: ","),
               let data = Data(base64Encoded: String(urlString[urlString.index(after: commaIdx)...])),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: detailPlaceholder
                    }
                }
            } else { detailPlaceholder }
        } else { detailPlaceholder }
    }

    private var detailPlaceholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.4))
            }
    }
}

// MARK: - Croppable Image Picker
// Wraps UIImagePickerController with allowsEditing = true for native move-and-scale crop UI

struct CroppableImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType       = .photoLibrary
        picker.allowsEditing    = true          // enables the move-and-scale crop UI
        picker.delegate         = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CroppableImagePicker
        init(_ parent: CroppableImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Prefer the cropped edit; fall back to the original
            parent.image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Shared Thumbnail

struct DishThumbnail: View {
    let imageURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = imageURL {
                if urlString.hasPrefix("data:image"),
                   let commaIdx = urlString.firstIndex(of: ","),
                   let data = Data(base64Encoded: String(urlString[urlString.index(after: commaIdx)...])),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary.opacity(0.5))
            }
    }
}
