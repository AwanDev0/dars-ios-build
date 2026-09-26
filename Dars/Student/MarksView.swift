import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class MarksStore {
    private(set) var rows: [ReportRow] = []
    private(set) var loading = true
    private(set) var error: DarsError?
    var semester = "1"
    private(set) var year = ""

    private let client = SupabaseService.client

    func load(for profile: Profile) async {
        error = nil
        do {
            if year.isEmpty, let school = profile.schoolId {
                struct SchoolBits: Decodable { let school_year: String?; let current_semester: String? }
                let bits: [SchoolBits] = try await client.from("schools").select("school_year, current_semester").eq("id", value: school).execute().value
                year = bits.first?.school_year ?? Self.defaultYear()
                if let s = bits.first?.current_semester, !s.isEmpty { semester = s }
            }
            if year.isEmpty { year = Self.defaultYear() }
            rows = try await client
                .rpc("student_report_card", params: ["p_student": profile.id.uuidString, "p_semester": semester, "p_year": year])
                .execute()
                .value
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    static func defaultYear() -> String {
        let y = Calendar.current.component(.year, from: Date())
        let m = Calendar.current.component(.month, from: Date())
        return m >= 9 ? "\(y)-\(y + 1)" : "\(y - 1)-\(y)"
    }

    var graded: [ReportRow] { rows.filter { $0.graded && $0.total != nil } }
    var overall: Double? {
        let g = graded.compactMap { $0.total }
        return g.isEmpty ? nil : g.reduce(0, +) / Double(g.count)
    }
    var highest: ReportRow? { graded.max { ($0.total ?? 0) < ($1.total ?? 0) } }
    var lowest: ReportRow? { graded.min { ($0.total ?? 0) < ($1.total ?? 0) } }
}

struct ReportRow: Codable, Identifiable, Equatable, Sendable {
    var id: String { subject }
    let subject: String
    let classId: UUID?
    let className: String?
    let c1: Double?
    let c2: Double?
    let c3: Double?
    let final: Double?
    let total: Double?
    let graded: Bool

    enum CodingKeys: String, CodingKey {
        case subject, c1, c2, c3, final, total, graded
        case classId = "class_id"
        case className = "class_name"
    }
}

enum Band {
    case excellent, veryGood, good, medium, acceptable, fail
    init(_ total: Double) {
        switch total {
        case 90...: self = .excellent
        case 80..<90: self = .veryGood
        case 70..<80: self = .good
        case 60..<70: self = .medium
        case 50..<60: self = .acceptable
        default: self = .fail
        }
    }
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .veryGood: return "Very good"
        case .good: return "Good"
        case .medium: return "Medium"
        case .acceptable: return "Acceptable"
        case .fail: return "Below pass"
        }
    }
    var color: Color {
        switch self {
        case .excellent, .veryGood: return DarsColor.success
        case .good, .medium, .acceptable: return DarsColor.warning
        case .fail: return DarsColor.danger
        }
    }
}

struct MarksView: View {
    let profile: Profile
    @State private var store = MarksStore()
    @State private var school: SchoolRow?
    @State private var printing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Report card").darsType(.largeTitle).foregroundStyle(DarsColor.labelPrimary)
                        Text("Semester \(store.semester) · \(store.year)").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                    }
                    Spacer()
                    Button { HapticEngine.play(.selection); printing = true } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(DarsColor.onAccent)
                            .frame(width: 36, height: 36).background(DarsColor.accent, in: Circle())
                    }
                    .accessibilityLabel("Share the report card")
                    .disabled(store.rows.isEmpty)
                }
                Picker("Semester", selection: $store.semester) {
                    Text("Semester 1").tag("1")
                    Text("Semester 2").tag("2")
                }
                .pickerStyle(.segmented)
                .onChange(of: store.semester) { Task { await store.load(for: profile) } }

                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    overallCard
                    if let low = store.lowest, let t = low.total, t < 50 {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DarsColor.danger)
                            Text("\(low.subject) needs attention").darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
                            Spacer()
                        }
                        .padding(Metrics.Space.md)
                        .background(DarsColor.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap").font(.system(size: 12))
                        Text("Tap a subject for its four parts — 10 · 20 · 10 · 60.")
                    }
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    VStack(spacing: 8) {
                        ForEach(store.rows) { row in SubjectCard(row: row) }
                    }
                }
                if let error = store.error { error.messageText.darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .task {
            school = try? await DarsData.school(profile.schoolId)
            await store.load(for: profile)
        }
        .refreshable { await store.load(for: profile) }
        .sheet(isPresented: $printing) {
            ReportCardSheet(student: profile, school: school, rows: store.rows, semester: store.semester, year: store.year)
        }
    }

    private var overallCard: some View {
        let overall = store.overall
        let band = overall.map(Band.init)
        return HStack(spacing: Metrics.Space.md) {
            ZStack {
                Circle().stroke(DarsColor.separator, lineWidth: 8)
                Circle().trim(from: 0, to: CGFloat((overall ?? 0) / 100)).stroke(DarsColor.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(Motion.moment, value: overall)
                VStack(spacing: 0) {
                    Text(overall.map { String(Int($0.rounded())) } ?? "—").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
                    Text("/100").font(.system(size: 11)).foregroundStyle(DarsColor.labelTertiary)
                }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 3) {
                Text("OVERALL").font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(DarsColor.labelTertiary)
                Text(band?.label ?? "No marks yet").font(.system(size: 24, weight: .bold)).foregroundStyle(DarsColor.accentLabel)
                Text("\(store.graded.count) of \(store.rows.count) subjects marked").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                if let h = store.highest, let t = h.total {
                    HStack(spacing: 6) { Circle().fill(DarsColor.success).frame(width: 7, height: 7); Text("Highest · \(h.subject)").foregroundStyle(DarsColor.labelSecondary); Text(String(Int(t.rounded()))).fontWeight(.bold).foregroundStyle(DarsColor.labelPrimary) }.font(.system(size: 12.5))
                }
                if let l = store.lowest, let t = l.total, store.graded.count > 1 {
                    HStack(spacing: 6) { Circle().fill(DarsColor.danger).frame(width: 7, height: 7); Text("Lowest · \(l.subject)").foregroundStyle(DarsColor.labelSecondary); Text(String(Int(t.rounded()))).fontWeight(.bold).foregroundStyle(DarsColor.labelPrimary) }.font(.system(size: 12.5))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.Space.md)
        .background(
            LinearGradient(colors: [DarsColor.accent.opacity(0.22), DarsColor.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous).strokeBorder(DarsColor.accent.opacity(0.3), lineWidth: 1))
    }
}

struct SubjectCard: View {
    let row: ReportRow
    @State private var open = false

    var body: some View {
        let band = row.total.map(Band.init)
        VStack(alignment: .leading, spacing: 10) {
            Button {
                HapticEngine.play(.selection)
                withAnimation(Motion.arrive) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(row.subject).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    if let b = band {
                        Text(b.label).font(.system(size: 11, weight: .bold)).foregroundStyle(b.color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(b.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Spacer()
                    Text(row.total.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 24, weight: .bold)).monospacedDigit()
                        .foregroundStyle(row.total == nil ? DarsColor.labelTertiary : DarsColor.labelPrimary)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            PartsBar(row: row, color: band?.color ?? DarsColor.labelTertiary)

            if open {
                HStack(spacing: 8) {
                    part("Part 1", row.c1, of: 10)
                    part("Midterm", row.c2, of: 20)
                    part("Part 3", row.c3, of: 10)
                    part("Final", row.final, of: 60)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func part(_ name: String, _ v: Double?, of max: Int) -> some View {
        VStack(spacing: 2) {
            Text(v.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "—").font(.system(size: 16, weight: .bold)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
            Text("\(name) /\(max)").font(.system(size: 10.5)).foregroundStyle(DarsColor.labelTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DarsColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PartsBar: View {
    let row: ReportRow
    let color: Color
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { g in
            let usable = max(0, g.size.width - gap * 3)
            HStack(spacing: gap) {
                segment(row.c1, of: 10, width: usable * 0.10)
                segment(row.c2, of: 20, width: usable * 0.20)
                segment(row.c3, of: 10, width: usable * 0.10)
                segment(row.final, of: 60, width: usable * 0.60)
            }
        }
        .frame(height: 6)
    }

    private func segment(_ v: Double?, of max: Double, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(DarsColor.separator)
            Capsule().fill(color).frame(width: width * CGFloat(min(1, Swift.max(0, (v ?? 0) / max))))
        }
        .frame(width: width, height: 6)
    }
}
