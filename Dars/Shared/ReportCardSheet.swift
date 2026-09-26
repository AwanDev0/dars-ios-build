import Foundation
import SwiftUI
import UIKit

struct ReportCardSheet: View {
    let student: Profile
    let school: SchoolRow?
    let rows: [ReportRow]
    let semester: String
    let year: String
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Environment(\.displayScale) private var displayScale
    @State private var sharing: SharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                page(kurdish: language.language.isKurdish)
                    .frame(width: 520)
                    .scaleEffect(0.66, anchor: .top)
                    .frame(height: 520 * 1.414 * 0.66)
                    .padding(.vertical, Metrics.Space.md)
            }
            .frame(maxWidth: .infinity)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Report card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { export() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .sheet(item: $sharing) { payload in ShareLinkSheet(url: payload.url) }
        }
    }

    private func page(kurdish: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(school?.displayName(kurdish: kurdish) ?? "School")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
                if let address = school?.address, !address.isEmpty {
                    Text(address).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Report card · Semester \(semester) · \(year)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x8F6A00))
            }
            Rectangle().fill(Color(hex: 0xFAB900)).frame(height: 3)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(student.displayName(kurdish: kurdish)).font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                    Text(student.classLabel.map { "Class \($0)" } ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if let overall {
                    VStack(spacing: 0) {
                        Text(String(Int(overall.rounded()))).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.black)
                        Text("overall").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 0) {
                HStack {
                    cell("Subject", 168, .leading, bold: true)
                    cell("10", 42, .center, bold: true)
                    cell("20", 42, .center, bold: true)
                    cell("10", 42, .center, bold: true)
                    cell("60", 42, .center, bold: true)
                    cell("Total", 56, .center, bold: true)
                    cell("Band", 78, .leading, bold: true)
                }
                .padding(.vertical, 7)
                .background(Color(hex: 0xF2F2F7))
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    HStack {
                        cell(r.subject, 168, .leading)
                        cell(fmt(r.c1), 42, .center)
                        cell(fmt(r.c2), 42, .center)
                        cell(fmt(r.c3), 42, .center)
                        cell(fmt(r.final), 42, .center)
                        cell(r.total.map { String(Int($0.rounded())) } ?? "—", 56, .center, bold: true)
                        Text(r.total.map { Band($0).label } ?? "—")
                            .font(.system(size: 11)).foregroundStyle(.black.opacity(0.7))
                            .frame(width: 78, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    .background(i.isMultiple(of: 2) ? Color.white : Color(hex: 0xFAFAFB))
                }
            }
            .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))

            Text("Marks are out of 100: first ten, midterm out of twenty, second ten, final out of sixty.")
                .font(.system(size: 10)).foregroundStyle(.secondary)

            Spacer(minLength: 24)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date().formatted(date: .long, time: .omitted)).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("Issued by Dars").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Rectangle().fill(Color.black.opacity(0.35)).frame(width: 150, height: 0.7)
                    Text(school?.ownerName ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                    Text(school?.ownerTitle ?? "Principal").font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(30)
        .frame(width: 520, height: 520 * 1.414, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var overall: Double? {
        let g = rows.compactMap { $0.graded ? $0.total : nil }
        return g.isEmpty ? nil : g.reduce(0, +) / Double(g.count)
    }

    private func cell(_ text: String, _ width: CGFloat, _ alignment: Alignment, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: bold ? 11 : 12, weight: bold ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(.black)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 4)
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func export() {
        let renderer = ImageRenderer(content: page(kurdish: language.language.isKurdish))
        renderer.scale = max(2, displayScale)
        let size = CGSize(width: 520, height: 520 * 1.414)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Report-\(student.fullName.replacingOccurrences(of: " ", with: "-"))-S\(semester).pdf")
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        HapticEngine.play(.success)
        sharing = SharePayload(url: url)
    }
}

struct ShareLinkSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
