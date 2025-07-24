//
//  ClickableHashtagText.swift
//  FitSpo
//
//  A SwiftUI view that makes hashtags clickable and blue, like Instagram
//

import SwiftUI

struct ClickableHashtagText: View {
    let text: String
    let onHashtagTap: (String) -> Void
    
    var body: some View {
        let words = text.components(separatedBy: " ")
        
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                if word.hasPrefix("#") && word.count > 1 {
                    Text(word)
                        .foregroundColor(.blue)
                        .onTapGesture {
                            let hashtag = String(word.dropFirst())
                            onHashtagTap(hashtag)
                        }
                } else {
                    Text(word)
                        .foregroundColor(.primary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ClickableHashtagText(text: "Love this outfit! #fashion #ootd #style") { hashtag in
            print("Tapped hashtag: \(hashtag)")
        }
        
        ClickableHashtagText(text: "Just regular text without hashtags") { hashtag in
            print("Tapped hashtag: \(hashtag)")
        }
        
        ClickableHashtagText(text: "Mix of #hashtags and regular text #cool") { hashtag in
            print("Tapped hashtag: \(hashtag)")
        }
    }
    .padding()
} 