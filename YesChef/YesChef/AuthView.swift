import SwiftUI
import AuthenticationServices

// MARK: - Auth Gate

struct AuthView: View {
    @EnvironmentObject var store: AppStore
    @State private var currentNonce: String?
    @State private var errorMsg = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                Text("478Chef")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Order food. Earn as a chef.")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            Spacer()

            // Sign in with Apple button
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    let nonce     = store.randomNonceString()
                    currentNonce  = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = store.sha256(nonce)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let nonce = currentNonce else { return }
                        store.handleAppleSignIn(authorization, nonce: nonce) { ok, msg in
                            if !ok { errorMsg = msg }
                        }
                    case .failure(let error):
                        if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                            errorMsg = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .cornerRadius(12)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.footnote).foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Uses Face ID · No password needed")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
        // Shown once, for brand-new users who need to pick a username
        .fullScreenCover(isPresented: $store.needsUsername) {
            UsernameSetupView()
        }
    }
}

// MARK: - Username Setup (new users only)

struct UsernameSetupView: View {
    @EnvironmentObject var store: AppStore

    @State private var username  = ""
    @State private var errorMsg  = ""
    @State private var isLoading = false

    private var isValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 52)).foregroundColor(.orange)
                        Text("One last step")
                            .font(.title2).fontWeight(.bold)
                        Text("Pick a username — this is what other users will see when they order your dishes.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section("Choose a username") {
                    TextField("e.g. chef_mario", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.title2).foregroundColor(.green)
                        Text("Your account starts with $1,000 balance.")
                            .font(.footnote).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.circle")
                            .foregroundColor(.red).font(.footnote)
                    }
                }

                Section {
                    Button(action: confirm) {
                        HStack {
                            Spacer()
                            if isLoading { ProgressView().tint(.white) }
                            else {
                                Label("Let's Go!", systemImage: "checkmark.circle.fill")
                                    .fontWeight(.bold)
                                    .foregroundColor(isValid ? .white : .secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(isValid ? Color.orange : Color.secondary.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .disabled(!isValid || isLoading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
            }
            .navigationBarBackButtonHidden(true)   // can't dismiss without a username
        }
    }

    private func confirm() {
        errorMsg  = ""
        isLoading = true
        store.createUserProfile(username: username.trimmingCharacters(in: .whitespaces)) { ok, msg in
            isLoading = false
            if !ok { errorMsg = msg }
            // On success, needsUsername flips to false → sheet closes automatically
        }
    }
}
