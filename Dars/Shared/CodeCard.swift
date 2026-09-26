import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct CodeCard: View {
    let code: String
    var caption: LocalizedStringKey = "Students sign in with this code and their own name."
    @State private var showingBig = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            HStack(spacing: Metrics.Space.md) {
                if let qr = QRCode.image(code) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .padding(6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(code).font(.system(size: 28, weight: .bold, design: .rounded)).kerning(3).foregroundStyle(DarsColor.accentLabel)
                    HStack(spacing: 14) {
                        Button { UIPasteboard.general.string = code; HapticEngine.play(.success) } label: {
                            Label("Copy", systemImage: "doc.on.doc").font(.system(size: 13, weight: .semibold))
                        }
                        Button { HapticEngine.play(.selection); showingBig = true } label: {
                            Label("Show the class", systemImage: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Text(caption).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fullScreenCover(isPresented: $showingBig) { BigCode(code: code) { showingBig = false } }
    }
}

private struct BigCode: View {
    let code: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                if let qr = QRCode.image(code, side: 900) {
                    Image(uiImage: qr).interpolation(.none).resizable()
                        .frame(width: 280, height: 280)
                }
                Text(code)
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .kerning(8)
                    .foregroundStyle(.black)
                Text("Open Dars → I'm a student → scan or type this")
                    .font(.system(size: 15)).foregroundStyle(.black.opacity(0.55))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 40, height: 40).background(.black.opacity(0.07), in: Circle())
            }
            .padding()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

enum QRCode {
    static func image(_ text: String, side: CGFloat = 300) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Foundation.Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
