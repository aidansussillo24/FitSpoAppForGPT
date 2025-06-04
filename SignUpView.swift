import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @State private var email        = ""
    @State private var password     = ""
    @State private var errorMessage: String?
    @State private var isLoading    = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            TextField("Email", text: $email)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            SecureField("Password", text: $password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                signUp()
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Create Account")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }

    private func signUp() {
        isLoading    = true
        errorMessage = nil

        Auth.auth().createUser(withEmail: email, password: password) { result, authError in
            if let authError = authError {
                self.errorMessage = authError.localizedDescription
                self.isLoading    = false
                return
            }
            guard let user = result?.user else {
                self.errorMessage = "Unknown error creating user."
                self.isLoading    = false
                return
            }

            // initialize an empty profile
            let profileData: [String:Any] = [
                "displayName": "",
                "bio":         "",
                "avatarURL":   "",
                "createdAt":   Date()
            ]

            NetworkService.shared.createUserProfile(
                userId: user.uid,
                data:   profileData
            ) { firestoreResult in
                self.isLoading = false
                switch firestoreResult {
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                case .success:
                    // on success, go back to Sign In
                    dismiss()
                }
            }
        }
    }
}
