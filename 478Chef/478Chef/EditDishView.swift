import SwiftUI

struct EditDishView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let dish: Dish

    @State private var name: String
    @State private var priceText: String
    @State private var category: String
    @State private var newImage: UIImage?   // non-nil only if user picked a new photo
    @State private var showPicker = false
    @State private var isSaving   = false
    @State private var errorMsg   = ""

    init(dish: Dish) {
        self.dish  = dish
        _name      = State(initialValue: dish.name)
        _priceText = State(initialValue: String(format: "%.2f", dish.price))
        _category  = State(initialValue: dish.category)
    }

    private var price: Double? { Double(priceText) }
    private var isValid: Bool  {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? 0) > 0
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Dish Info") {
                    TextField("Name", text: $name)
                    HStack {
                        Text("$").foregroundColor(.secondary)
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
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

                Section("📷 Photo") {
                    Button { showPicker = true } label: {
                        HStack(spacing: 16) {
                            // Show cropped new image, or existing dish image
                            Group {
                                if let newImage {
                                    Image(uiImage: newImage)
                                        .resizable().scaledToFill()
                                } else {
                                    DishThumbnail(imageURL: dish.imageURL, size: 90)
                                        // remove inner clipping so outer clip applies
                                        .frame(width: 90, height: 90)
                                }
                            }
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(newImage != nil ? "Change Photo" : "Change Photo")
                                    .font(.headline).foregroundColor(.orange)
                                Text(newImage != nil
                                     ? "New photo selected — tap to redo"
                                     : "Tap to pick & crop a new photo")
                                    .font(.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    if newImage != nil {
                        Button(role: .destructive) { newImage = nil } label: {
                            Label("Revert to Original", systemImage: "arrow.uturn.backward")
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
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().tint(.white)
                                Text("Saving…").fontWeight(.semibold).foregroundColor(.white)
                            } else {
                                Label("Save Changes", systemImage: "checkmark.circle.fill")
                                    .fontWeight(.semibold)
                                    .foregroundColor(isValid ? .white : .secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(isValid ? Color.orange : Color.secondary.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .disabled(!isValid || isSaving)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Edit Dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                CroppableImagePicker(image: $newImage)
            }
        }
    }

    private func save() {
        guard let p = price, p > 0 else { errorMsg = "Enter a valid price."; return }
        errorMsg = ""
        isSaving = true
        store.updateDish(dish,
                         name: name.trimmingCharacters(in: .whitespaces),
                         price: p,
                         newImage: newImage,
                         category: category) { ok, msg in
            isSaving = false
            if ok { dismiss() }
            else  { errorMsg = msg }
        }
    }
}
