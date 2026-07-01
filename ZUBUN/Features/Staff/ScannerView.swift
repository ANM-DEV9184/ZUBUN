//
//  ScannerView.swift
//  ZUBUN
//
//  Dark, immersive staff scanner home (spec §5.3). Camera viewport + torch +
//  phone fallback; a result overlay surfaces the outcome with the right tone.
//

import SwiftUI

struct ScannerView: View {
    @State private var vm = ScannerViewModel()
    @State private var authorized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let offline = OfflineQueue.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if authorized {
                CameraScannerView(onScan: vm.handleScan, torchOn: vm.torchOn)
                    .ignoresSafeArea()
                reticle
            } else {
                permissionPrompt
            }

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding()

            if let outcome = vm.outcome {
                ResultOverlay(outcome: outcome,
                              canBonus: vm.lastCustomerQR != nil && outcome.tone != .error,
                              onBonus: { count in Task { await vm.bonus(count: count) } },
                              onDismiss: { vm.outcome = nil })
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: vm.outcome)
        .task {
            authorized = await CameraPermission.ensureAccess()
            await offline.replayAll()
        }
        .sheet(isPresented: $vm.showPhonePad) {
            PhonePadSheet(onSubmit: { phone in Task { await vm.phoneFallback(phone) } })
                .presentationDetents([.medium])
        }
    }

    private var topBar: some View {
        HStack {
            if offline.pendingCount > 0 {
                Label("\(offline.pendingCount) queued", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { vm.torchOn.toggle() } label: {
                Image(systemName: vm.torchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3).padding(12)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Toggle torch")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if vm.isProcessing {
                ProgressView().tint(.white)
            }
            Button {
                vm.showPhonePad = true
            } label: {
                Label("Enter phone", systemImage: "keyboard")
                    .font(.brandHeadline())
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Brand.amber, lineWidth: 3)
            .frame(width: 240, height: 240)
            .shadow(color: .black.opacity(0.4), radius: 12)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.system(size: 48)).foregroundStyle(.white)
            Text("Camera access needed", comment: "Scanner permission title")
                .font(.brandHeadline()).foregroundStyle(.white)
            Text("Enable camera in Settings to scan loyalty codes.", comment: "Scanner permission body")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

/// Manual phone entry fallback when the QR won't scan (spec B7).
struct PhonePadSheet: View {
    var onSubmit: (String) -> Void
    @State private var phone = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("+9715XXXXXXXX", text: $phone)
                    .zKeyboard(.phone)
                    .font(.title2)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding()
                    .background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))

                PrimaryButton(title: String(localized: "fallback.stamp", defaultValue: "Give stamp")) {
                    onSubmit(phone)
                    dismiss()
                }
                .disabled(phone.count < 7)
                Spacer()
            }
            .padding()
            .navigationTitle(Text("Phone entry", comment: "Phone fallback title"))
            .zInlineTitle()
        }
    }
}
