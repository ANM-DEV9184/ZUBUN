//
//  SelfieCamera.swift
//  ZUBUN
//
//  Front-camera selfie capture for clock-in/out (buddy-punch check, spec §5.4).
//  Uses UIImagePickerController and returns a JPEG compressed to ≤600KB.
//

import SwiftUI

#if os(iOS)
import UIKit

struct SelfieCamera: UIViewControllerRepresentable {
    /// Called with JPEG data (≤600KB) or nil if cancelled.
    var onCapture: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .front
        }
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    nonisolated final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        nonisolated(unsafe) let onCapture: (Data?) -> Void
        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            let data = image.flatMap { Self.compress($0, maxBytes: 600_000) }
            let cb = onCapture
            DispatchQueue.main.async {
                picker.dismiss(animated: true)
                cb(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            let cb = onCapture
            DispatchQueue.main.async {
                picker.dismiss(animated: true)
                cb(nil)
            }
        }

        nonisolated static func compress(_ image: UIImage, maxBytes: Int) -> Data? {
            var quality: CGFloat = 0.7
            var data = image.jpegData(compressionQuality: quality)
            while let d = data, d.count > maxBytes, quality > 0.1 {
                quality -= 0.1
                data = image.jpegData(compressionQuality: quality)
            }
            return data
        }
    }
}

#else

struct SelfieCamera: View {
    var onCapture: (Data?) -> Void
    var body: some View {
        EmptyStateView(systemImage: "camera.fill",
                       title: "Camera unavailable",
                       message: "Clock-in photos require an iOS device.")
    }
}

#endif
