import SwiftUI

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedImage: UIImage?
    @State private var caption: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showImagePicker = false

    /// Observe the shared location manager
    @StateObject private var locationManager = LocationManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button {
                        showImagePicker = true
                    } label: {
                        if let img = selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .cornerRadius(8)
                        } else {
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Caption")) {
                    TextField("Enter a caption…", text: $caption)
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundColor(.red) }
                }
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: upload)
                        .disabled(selectedImage == nil || caption.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView().scaleEffect(1.5)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
        }
    }

    private func upload() {
        guard let image = selectedImage else { return }
        isLoading = true
        errorMessage = nil

        // grab current coords (nil if not yet determined)
        let latitude  = locationManager.location?.coordinate.latitude
        let longitude = locationManager.location?.coordinate.longitude

        print("📍 live location →", latitude as Any, longitude as Any)

        NetworkService.shared.uploadPost(
            image: image,
            caption: caption,
            latitude: latitude,
            longitude: longitude
        ) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success:
                    dismiss()
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }
}
