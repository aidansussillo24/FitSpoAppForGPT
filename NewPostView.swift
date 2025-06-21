//  Replace file: NewPostView.swift
//  FitSpo
//
//  • Starts LocationManager when Post flow opens.
//  • 3-column grid with 1-pt separators (Instagram style).
//  • Preview collapses on scroll.

import SwiftUI
import PhotosUI

private struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct NewPostView: View {

    // PhotoKit
    @State private var assets: [PHAsset] = []
    private let manager = PHCachingImageManager()

    // Selection
    @State private var selected : PHAsset?
    @State private var preview  : UIImage?
    @State private var collapsed = false
    @State private var showCaption = false

    // Start location updates as soon as this view appears
    @StateObject private var locationManager = LocationManager.shared

    // Grid
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // -------- Preview ----------
                Group {
                    if let img = preview {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: collapsed ? 0 : 300)
                .clipped()
                .cornerRadius(12)
                .animation(.easeInOut(duration: 0.25), value: collapsed)
                .padding(.horizontal)
                .padding(.top, 8)

                // -------- Grid -------------
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: OffsetKey.self,
                                        value: geo.frame(in: .named("scroll")).minY)
                    }
                    .frame(height: 0)

                    LazyVGrid(columns: cols, spacing: 1) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Thumb(asset: asset,
                                  manager: manager,
                                  selected: asset == selected) {
                                select(asset)
                            }
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(OffsetKey.self) { y in
                    withAnimation { collapsed = y < -40 }
                }
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Next") { showCaption = true }
                        .disabled(preview == nil)
                }
            }
            .background(
                NavigationLink(isActive: $showCaption) {
                    if let img = preview { PostCaptionView(image: img) }
                } label: { EmptyView() }.hidden()
            )
            .task(loadAssets)
        }
    }

    // MARK: – Load PhotoKit
    private func loadAssets() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 60
        let fetch = PHAsset.fetchAssets(with: .image, options: opts)

        var tmp: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in tmp.append(a) }
        assets = tmp
        if let first = assets.first { select(first) }
    }

    private func select(_ asset: PHAsset) {
        selected  = asset
        collapsed = false
        let size  = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        manager.requestImage(for: asset,
                             targetSize: size,
                             contentMode: .aspectFit,
                             options: nil) { img, _ in
            preview = img
        }
    }
}

// MARK: – Thumbnail with thin border
fileprivate struct Thumb: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let selected: Bool
    let onTap: () -> Void

    @State private var img: UIImage?
    private var side: CGFloat { (UIScreen.main.bounds.width - 2) / 3 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let t = img {
                Image(uiImage: t)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            } else {
                Color.gray.opacity(0.15)
                    .frame(width: side, height: side)
            }

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .padding(4)
            }
        }
        .overlay(
            Rectangle().stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .onAppear(perform: loadThumb)
        .onTapGesture { onTap() }
    }

    private func loadThumb() {
        guard img == nil else { return }
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 300, height: 300),
                             contentMode: .aspectFill,
                             options: nil) { i, _ in img = i }
    }
}
