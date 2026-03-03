import SwiftUI

struct InvitationsView: View {
    @EnvironmentObject var store: AppStore
    @State private var processingID: String?

    var body: some View {
        NavigationView {
            Group {
                if store.pendingInvitations.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "envelope")
                            .font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No pending invitations")
                            .font(.title2).fontWeight(.semibold)
                        Text("When someone invites you to a menu, it'll appear here.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                        if !store.isMemberOfAnyMenu {
                            Divider().padding(.vertical, 8)
                            Text("You can also create your own menu from the Profile tab.")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(store.pendingInvitations) { inv in
                            InvitationRow(invitation: inv, processingID: $processingID)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Invitations")
        }
    }
}

// MARK: - Invitation Row

private struct InvitationRow: View {
    @EnvironmentObject var store: AppStore
    let invitation: Invitation
    @Binding var processingID: String?
    @State private var errorMsg = ""

    private var isProcessing: Bool { processingID == invitation.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.menuName)
                    .font(.headline)
                Text("Invited by \(invitation.fromUsername)")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            if !errorMsg.isEmpty {
                Text(errorMsg).font(.caption).foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("Decline") {
                    processingID = invitation.id
                    store.declineInvitation(invitation) { ok, msg in
                        processingID = nil
                        if !ok { errorMsg = msg }
                    }
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(isProcessing)

                Button("Accept") {
                    processingID = invitation.id
                    store.acceptInvitation(invitation) { ok, msg in
                        processingID = nil
                        if !ok { errorMsg = msg }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isProcessing)

                if isProcessing { ProgressView() }
            }
        }
        .padding(.vertical, 4)
    }
}
