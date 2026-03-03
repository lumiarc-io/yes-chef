import SwiftUI

struct InviteUserView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let menu: Menu

    @State private var username   = ""
    @State private var isSending  = false
    @State private var errorMsg   = ""
    @State private var successMsg = ""
    @State private var memberNames: [String: String] = [:]
    @State private var memberToRemove: String?
    @FocusState private var focused: Bool

    private var trimmed: String { username.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool   { !trimmed.isEmpty }
    private var isCreator: Bool { store.currentUser?.id == menu.creatorID }

    /// Live memberIDs from the store (stays in sync after removals)
    private var liveMemberIDs: [String] {
        store.myMenus.first(where: { $0.id == menu.id })?.memberIDs ?? menu.memberIDs
    }

    var body: some View {
        NavigationView {
            Form {
                if isCreator {
                    Section {
                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($focused)
                    } header: {
                        Text("Invite to \"\(menu.name)\"")
                    } footer: {
                        Text("Enter the exact username of the person you want to invite.")
                    }

                    if !errorMsg.isEmpty {
                        Section {
                            Label(errorMsg, systemImage: "exclamationmark.circle")
                                .foregroundColor(.red).font(.footnote)
                        }
                    }

                    if !successMsg.isEmpty {
                        Section {
                            Label(successMsg, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.footnote)
                        }
                    }

                    Section {
                        Button(action: send) {
                            HStack {
                                Spacer()
                                if isSending {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Send Invitation", systemImage: "paperplane.fill")
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .foregroundColor(.white)
                            .background(isValid ? Color.orange : Color.secondary.opacity(0.3))
                            .cornerRadius(10)
                        }
                        .disabled(!isValid || isSending)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal)
                    }
                }

                // Current members
                if !liveMemberIDs.isEmpty {
                    Section("Members (\(liveMemberIDs.count))") {
                        ForEach(liveMemberIDs, id: \.self) { uid in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.secondary)
                                Text(memberNames[uid] ?? uid)
                                    .font(.subheadline)
                                Spacer()
                                if uid == menu.creatorID {
                                    Text("Creator")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .clipShape(Capsule())
                                } else if isCreator {
                                    Button {
                                        memberToRemove = uid
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isCreator ? "Manage Members" : "Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
            .confirmationDialog(
                "Remove \(memberNames[memberToRemove ?? ""] ?? "this member")?",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove & Delete Their Dishes", role: .destructive) {
                    if let uid = memberToRemove {
                        store.removeMember(uid: uid, from: menu) { _, _ in }
                    }
                    memberToRemove = nil
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                Text("This member will lose access and their dishes in this menu will be deleted.")
            }
        }
        .onAppear {
            if isCreator { focused = true }
            loadNames()
        }
    }

    private func send() {
        guard isValid else { return }
        isSending = true
        errorMsg  = ""
        successMsg = ""
        store.inviteUser(username: trimmed, to: menu) { ok, msg in
            isSending = false
            if ok {
                successMsg = "Invitation sent to \(trimmed)!"
                username   = ""
            } else {
                errorMsg = msg
            }
        }
    }

    private func loadNames() {
        store.loadMemberUsernames(for: liveMemberIDs) { names in
            memberNames = names
        }
    }
}
