import SwiftUI

struct AddDishView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    /// When true, shows a menu picker (used from Profile "My Dishes").
    /// When false, uses the current active menu (used from MenuView).
    var showMenuPicker: Bool = false

    @State private var selectedMenuID: String = ""
    @State private var dishName       = ""
    @State private var priceText      = ""
    @State private var category       = "Main Dish"
    @State private var selectedImage: UIImage?
    @State private var showPicker     = false
    @State private var isUploading    = false
    @State private var showSuccess    = false
    @State private var errorMsg       = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, price }

    private var price: Double? { Double(priceText) }
    private var isValid: Bool {
        !dishName.trimmingCharacters(in: .whitespaces).isEmpty
        && (price ?? 0) > 0
        && targetMenuID != nil
    }

    /// The menu ID to use for adding the dish.
    private var targetMenuID: String? {
        if showMenuPicker {
            return selectedMenuID.isEmpty ? nil : selectedMenuID
        }
        return store.currentMenu?.id
    }

    private var targetMenuName: String? {
        if showMenuPicker {
            return store.myMenus.first(where: { $0.id == selectedMenuID })?.name
        }
        return store.currentMenu?.name
    }

    var body: some View {
        NavigationView {
            Form {
                if showMenuPicker {
                    Section("Menu") {
                        Picker("Add to", selection: $selectedMenuID) {
                            Text("Select a menu").tag("")
                            ForEach(store.myMenus) { menu in
                                Text(menu.name).tag(menu.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else if let menuName = store.currentMenu?.name {
                    Section {
                        Label("Adding to: \(menuName)", systemImage: "fork.knife.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }

                Section("Dish Info") {
                    TextField("Name (e.g. Margherita Pizza)", text: $dishName)
                        .focused($focusedField, equals: .name)
                    HStack {
                        Text("$").foregroundColor(.secondary)
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                            .onChange(of: priceText) { val in
                                if val.hasPrefix("0") && val.count > 1 && !val.hasPrefix("0.") {
                                    priceText = String(val.drop(while: { $0 == "0" }))
                                }
                            }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(dishCategories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                Section("Photo") {
                    Button { focusedField = nil; showPicker = true } label: {
                        HStack(spacing: 16) {
                            Group {
                                if let img = selectedImage {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                } else {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.12))
                                        .overlay {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 28))
                                                .foregroundColor(.secondary.opacity(0.5))
                                        }
                                }
                            }
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedImage == nil ? "Add Photo" : "Change Photo")
                                    .font(.headline).foregroundColor(.orange)
                                Text(selectedImage == nil
                                     ? "Tap to open Photos — you can crop after picking"
                                     : "Tap to pick a different photo")
                                    .font(.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    if selectedImage != nil {
                        Button(role: .destructive) { selectedImage = nil } label: {
                            Label("Remove Photo", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.circle")
                            .foregroundColor(.red).font(.footnote)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isUploading {
                                ProgressView().tint(.white)
                                Text("Uploading…")
                                    .fontWeight(.semibold).foregroundColor(.white)
                            } else {
                                Label("Add to Menu", systemImage: "plus.circle.fill")
                                    .fontWeight(.semibold)
                                    .foregroundColor(isValid ? .white : .secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(isValid ? Color.orange : Color.secondary.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .disabled(!isValid || isUploading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Add Dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .alert("Dish Added!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(dishName) is now live on the menu.")
            }
            .sheet(isPresented: $showPicker) {
                CroppableImagePicker(image: $selectedImage)
            }
            .onAppear {
                // Pre-select the current menu if using picker
                if showMenuPicker, let id = store.currentMenu?.id {
                    selectedMenuID = id
                }
            }
        }
    }

    private func submit() {
        focusedField = nil
        let trimmed = dishName.trimmingCharacters(in: .whitespaces)
        guard let p = price, p > 0 else { errorMsg = "Enter a valid price."; return }

        errorMsg    = ""
        isUploading = true

        store.addDish(name: trimmed, price: p, image: selectedImage, category: category,
                      menuID: targetMenuID) { ok, msg in
            isUploading = false
            if ok {
                dishName      = ""
                priceText     = ""
                category      = "Main Dish"
                selectedImage = nil
                showSuccess   = true
            } else {
                errorMsg = msg
            }
        }
    }
}
