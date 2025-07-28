import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// A simple model for each "followed" user
private struct UserRow: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String
}

struct ShareToUserView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var rows: [UserRow] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header
                VStack(spacing: 16) {
                    Text("Share to...")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if !rows.isEmpty {
                        Text("Choose someone to share with")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
                
                // Content area
                Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading contacts...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    } else if let errorMsg = errorMsg {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            
                            Text("Something went wrong")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(errorMsg)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button(action: { fetchFollowing() }) {
                                Text("Try Again")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    } else if rows.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "person.2.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.gray.opacity(0.6))
                            
                            Text("No Contacts Found")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("Follow some people to share posts with them")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { user in
                                    Button {
                                        onSelect(user.id)
                                        dismiss()
                                    } label: {
                                        UserRowView(user: user)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if user.id != rows.last?.id {
                                        Divider()
                                            .padding(.leading, 72)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .onAppear(perform: fetchFollowing)
        }
    }
    
    // MARK: - User Row View
    private struct UserRowView: View {
        let user: UserRow
        
        var body: some View {
            HStack(spacing: 16) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let url = URL(string: user.avatarURL),
                       !user.avatarURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .scaleEffect(0.8)
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundColor(.gray)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.gray)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    // Share indicator
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "paperplane")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                
                // User info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Tap to share")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white)
        }
    }

    private func fetchFollowing() {
        guard !isLoading,
              let me = Auth.auth().currentUser?.uid
        else { return }
        isLoading = true
        let db = Firestore.firestore()
        // ← adjust this path if your “following” is stored elsewhere
        db.collection("users")
          .document(me)
          .collection("following")
          .getDocuments { snap, err in
            isLoading = false
            if let err = err {
                errorMsg = err.localizedDescription
            } else {
                let ids = snap?.documents.map{ $0.documentID } ?? []
                fetchProfiles(for: ids)
            }
        }
    }

    private func fetchProfiles(for ids: [String]) {
        let db = Firestore.firestore()
        var temp: [UserRow] = []
        let group = DispatchGroup()
        for id in ids {
            group.enter()
            db.collection("users").document(id).getDocument { snap, err in
                defer { group.leave() }
                guard err == nil, let d = snap?.data() else { return }
                let name = d["displayName"] as? String ?? "Unknown"
                let avatar = d["avatarURL"] as? String ?? ""
                temp.append(UserRow(id: id, displayName: name, avatarURL: avatar))
            }
        }
        group.notify(queue: .main) {
            rows = temp.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }
    }
}
