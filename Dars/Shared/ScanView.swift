import AVFoundation
import SwiftUI
import UIKit

struct ScanView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done,
                  let object = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            done = true
            Task { @MainActor in
                HapticEngine.play(.success)
                self.onCode(value)
            }
        }
    }

    final class ScannerController: UIViewController {
        weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = [.qr, .code128, .ean13]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                Task.detached(priority: .userInitiated) { [session] in session.startRunning() }
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }
    }
}

struct ScanCodeSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    var body: some View {
        ZStack {
            if denied {
                VStack(spacing: Metrics.Space.md) {
                    ContentUnavailableView("The camera is off for Dars", systemImage: "camera.fill",
                                           description: Text("Settings → Dars → Camera, then come back."))
                    DarsButton(title: "Close", kind: .secondary) { dismiss() }
                }
                .padding(Metrics.Space.lg)
            } else {
                ScanView { code in
                    onCode(code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    dismiss()
                }
                .ignoresSafeArea()
                overlay
            }
        }
        .task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined {
                denied = !(await AVCaptureDevice.requestAccess(for: .video))
            } else {
                denied = status != .authorized
            }
        }
    }

    private var overlay: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(.black.opacity(0.4), in: Circle())
                }
                .padding()
            }
            Spacer()
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DarsColor.brandGold, lineWidth: 3)
                .frame(width: 230, height: 230)
            Spacer()
            Text("Point it at the code on the class page.")
                .darsType(.subheadline).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 50)
        }
    }
}
