import SwiftUI

struct CreateMenuView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var menuName   = ""
    @State private var isCreating = false
    @State private var errorMsg   = ""
    @FocusState private var focused: Bool

    private var trimmed: String { menuName.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool   { !trimmed.isEmpty }

    var body: some View {
        NavigationView {
            Form {
                Section("Menu Name") {
                    TextField("e.g. Friday Lunch, Study Group", text: $menuName)
                        .focused($focused)
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.circle")
                            .foregroundColor(.red).font(.footnote)
                    }
                }

                Section {
                    Button(action: create) {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView().tint(.white)
                            } else {
                                Label("Create Menu", systemImage: "plus.circle.fill")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(isValid ? Color.orange : Color.secondary.opacity(0.3))
                        .cornerRadius(10)
                    }
                    .disabled(!isValid || isCreating)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
            }
            .navigationTitle("New Menu")
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

    private func create() {
        guard isValid else { return }
        isCreating = true
        store.createMenu(name: trimmed) { ok, msg in
            isCreating = false
            if ok { dismiss() }
            else  { errorMsg = msg }
        }
    }
}
