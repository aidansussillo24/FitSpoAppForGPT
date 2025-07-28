// MessagesView.swift

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MessagesView: View {
    @State private var chats: [Chat] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNewChatSheet = false
    @State private var selectedUserId: String = ""
    @State private var navigateToNewChat = false
    @State private var selectedChat: Chat?
    @State private var navigateToChat = false
    @State private var isRefreshing = false

    // cache displayName+avatar per userId
    @State private var profiles: [String: (displayName: String, avatarURL: String)] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instagram-style header
                HStack {
                    Text("Messages")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Create new message button
                    Button(action: {
                        showNewChatSheet = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                
                // Content area
                Group {
                    // 1) loading spinner
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading conversations...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // 2) error + retry
                    } else if let error = errorMessage {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            
                            Text("Something went wrong")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(error)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button(action: { loadChats(force: true) }) {
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

                    // 3) empty state
                    } else if chats.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "message.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.gray.opacity(0.6))
                            
                            Text("No Messages Yet")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("Start a conversation by sharing a post with someone")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // 4) chat list - Instagram style
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(chats) { chat in
                                    let otherId = chat.participants.first { $0 != Auth.auth().currentUser?.uid } ?? ""
                                    InstagramStyleChatRow(
                                        chat: chat,
                                        otherId: otherId,
                                        profile: profiles[otherId],
                                        onDelete: { deleteChat(chat) },
                                        onTap: {
                                            selectedChat = chat
                                            navigateToChat = true
                                        }
                                    )
                                    .onAppear { loadProfile(userId: otherId) }
                                    
                                    if chat.id != chats.last?.id {
                                        Divider()
                                            .padding(.leading, 68)
                                    }
                                }
                            }
                        }
                        .refreshable {
                            await refreshChats()
                        }
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewChatSheet) {
                ShareToUserView { userId in
                    selectedUserId = userId
                    createNewChat(with: userId)
                }
            }
            .navigationDestination(isPresented: $navigateToNewChat) {
                if let chat = selectedChat {
                    ChatDetailView(chat: chat)
                }
            }
            .navigationDestination(isPresented: $navigateToChat) {
                if let chat = selectedChat {
                    ChatDetailView(chat: chat)
                }
            }
        }
        .onAppear { loadChats() }
    }

    // MARK: - New Chat Creation
    private func createNewChat(with userId: String) {
        print("MessagesView: Creating new chat with user: \(userId)")
        // First, check if a chat already exists with this user
        if let existingChat = chats.first(where: { chat in
            chat.participants.contains(userId) && 
            chat.participants.contains(Auth.auth().currentUser?.uid ?? "")
        }) {
            print("MessagesView: Found existing chat: \(existingChat.id)")
            // Chat already exists, navigate to it
            selectedChat = existingChat
            navigateToNewChat = true
        } else {
            print("MessagesView: Creating new chat in Firestore")
            // Create new chat
            createNewChatInFirestore(with: userId)
        }
    }
    
    private func createNewChatInFirestore(with userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Create in Firestore (this will create new or return existing)
        NetworkService.shared.createChat(participants: [currentUserId, userId]) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let chat):
                    print("MessagesView: Chat created/found successfully: \(chat.id)")
                    // Add to local chats array if not already present
                    if !chats.contains(where: { $0.id == chat.id }) {
                        chats.insert(chat, at: 0)
                    }
                    selectedChat = chat
                    navigateToNewChat = true
                case .failure(let error):
                    print("Failed to create chat: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Refresh Function
    @MainActor
    private func refreshChats() async {
        print("MessagesView: Refreshing chats...")
        isRefreshing = true
        
        // Clear existing data
        chats.removeAll()
        profiles.removeAll()
        
        // Reload chats
        loadChats()
        
        // Small delay to ensure chats are loaded before profiles
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Reload profiles for existing chats
        for chat in chats {
            let otherId = chat.participants.first { $0 != Auth.auth().currentUser?.uid } ?? ""
            loadProfile(userId: otherId)
        }
        
        isRefreshing = false
        print("MessagesView: Refresh complete")
    }

    // MARK: - Chat Deletion
    private func deleteChat(_ chat: Chat) {
        print("MessagesView: Deleting chat: \(chat.id)")
        
        // Remove from local array immediately (optimistic update)
        chats.removeAll { $0.id == chat.id }
        
        // Delete from Firestore
        NetworkService.shared.deleteChat(chatId: chat.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("MessagesView: Chat deleted successfully from Firestore")
                case .failure(let error):
                    print("MessagesView: Failed to delete chat from Firestore: \(error.localizedDescription)")
                    // Re-add to local array if deletion failed
                    if !chats.contains(where: { $0.id == chat.id }) {
                        chats.append(chat)
                    }
                }
            }
        }
    }

    // MARK: - Chat Row View
    private struct InstagramStyleChatRow: View {
        let chat: Chat
        let otherId: String
        let profile: (displayName: String, avatarURL: String)?
        let onDelete: () -> Void
        let onTap: () -> Void
        
        @State private var offset: CGFloat = 0
        @State private var isSwiped = false
        
        var body: some View {
            ZStack {
                // Background actions (Instagram-style)
                HStack(spacing: 0) {
                    Spacer()
                    
                    // Delete button only
                    Button(action: onDelete) {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                            Text("Delete")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                    }
                    .frame(width: 80, height: 44)
                    .background(Color.red)
                }
                
                // Main chat row
                HStack(spacing: 16) {
                    // Avatar
                    avatarView
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    // Chat info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile?.displayName ?? "Loading...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text(timeAgoString)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(chat.lastMessage.isEmpty ? "No messages yet" : chat.lastMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offset = max(value.translation.width, -80)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.3)) {
                                if value.translation.width < -50 {
                                    offset = -80
                                    isSwiped = true
                                } else {
                                    offset = 0
                                    isSwiped = false
                                }
                            }
                        }
                )
                .onTapGesture {
                    if isSwiped {
                        withAnimation(.easeOut(duration: 0.3)) {
                            offset = 0
                            isSwiped = false
                        }
                    } else {
                        onTap()
                    }
                }
            }
            .clipped()
        }
        
        // MARK: - Computed Properties
        private var avatarView: some View {
            if let profile = profile, let url = URL(string: profile.avatarURL), !profile.avatarURL.isEmpty {
                AnyView(RemoteImage(url: url.absoluteString, contentMode: .fill))
            } else {
                AnyView(
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundColor(.gray)
                )
            }
        }
        
        private var timeAgoString: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: chat.lastTimestamp, relativeTo: Date())
        }
    }

    private func loadChats(force: Bool = false) {
        guard !isLoading, force || chats.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        NetworkService.shared.fetchChats { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let fetched):
                    self.chats = fetched
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                }
            }
        }
    }

    private func loadProfile(userId: String) {
        guard profiles[userId] == nil else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .getDocument { snap, err in
                guard err == nil, let d = snap?.data() else { return }
                let name   = d["displayName"] as? String ?? ""
                let avatar = d["avatarURL"]   as? String ?? ""
                DispatchQueue.main.async {
                    profiles[userId] = (displayName: name, avatarURL: avatar)
                }
            }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView()
    }
}
