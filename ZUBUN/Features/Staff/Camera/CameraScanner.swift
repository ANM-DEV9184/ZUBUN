//
//  CameraScanner.swift
//  ZUBUN
//
//  AVFoundation QR scanner wrapped for SwiftUI (spec §5.3). Reads dayem:c: and
//  dayem:r: codes; supports a torch toggle. iOS-only; other platforms get a stub.
//

import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

/// Coordinator is fully nonisolated: AVFoundation calls its delegate on a private
/// queue. It hops to the main thread before invoking the SwiftUI handler.
nonisolated final class ScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    nonisolated(unsafe) var onScan: ((String) -> Void)?

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        let callback = onScan
        DispatchQueue.main.async { callback?(value) }
    }
}

final class ScannerPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraScannerView: UIViewRepresentable {
    /// Called on the main thread with the raw scanned string.
    var onScan: (String) -> Void
    /// Drives the torch.
    var torchOn: Bool

    func makeCoordinator() -> ScannerCoordinator {
        let c = ScannerCoordinator()
        c.onScan = onScan
        return c
    }

    func makeUIView(context: Context) -> ScannerPreviewView {
        let view = ScannerPreviewView()
        view.backgroundColor = .black
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return view
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue(label: "io.zubun.scanner"))
            output.metadataObjectTypes = [.qr]
        }

        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        // Start on a background queue (startRunning blocks).
        let bg = DispatchQueue(label: "io.zubun.scanner.session")
        bg.async { session.startRunning() }
        context.coordinator.onScan = onScan
        return view
    }

    func updateUIView(_ uiView: ScannerPreviewView, context: Context) {
        context.coordinator.onScan = onScan
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }
}

enum CameraPermission {
    static func ensureAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

#else

// Non-iOS fallback so the project compiles for macOS/xrOS targets.
struct CameraScannerView: View {
    var onScan: (String) -> Void
    var torchOn: Bool
    var body: some View {
        EmptyStateView(systemImage: "camera.fill",
                       title: "Camera unavailable",
                       message: "QR scanning requires an iOS device.")
    }
}

enum CameraPermission {
    static func ensureAccess() async -> Bool { false }
}

#endif
