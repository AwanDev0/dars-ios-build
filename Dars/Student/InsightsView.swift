import Charts
import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class InsightsStore {
    private(set) var report: [ReportRow] = []
    private(set) var attendance: [AttendanceRow] = []
    private(set) var week: WeekReview?
    private(set) var recent: [RecentMark] = []
    private(set) var loading = true
    private let client = SupabaseService.client

    struct WeekReview: Codable, Sendable {
        let weekStart: String?
        let average: Double?
        let teachers: Int?
        let notes: [String]?
        let history: [Double]?
        enum CodingKeys: String, CodingKey {
            case average, teachers, notes, history
            case weekStart = "week_start"
        }
    }

    struct RecentMark: Codable, Identifiable, Sendable {
        let assessmentId: UUID
        let score: Double?
        let updatedAt: String?
        let assessment: Assessment?
        var id: UUID { assessmentId }
        struct Assessment: Codable, Sendable {
            let subject: String?
            let title: String?
            let maxScore: Double?
            let date: String?
            enum CodingKeys: String, CodingKey { case subject, title, date; case maxScore = "max_score" }
        }
        enum CodingKeys: String, CodingKey {
            case score
            case assessmentId = "assessment_id"; case updatedAt = "updated_at"; case assessment = "assessments_v2"
        }
        var percent: Double? {
            guard let score, let max = assessment?.maxScore, max > 0 else { return nil }
            return score * 100 / max
        }
    }

    func load(for profile: Profile, school: SchoolRow?) async {
        let semester = school?.semester ?? "1"
        let year = school?.year ?? SchoolYear.current()
        do {
            async let card: [ReportRow] = try await client.rpc("student_report_card", params: ["p_student": profile.id.uuidString, "p_semester": semester, "p_year": year]).execute().value
            async let register: [AttendanceRow] = (try? await client.from("attendance").select(AttendanceRow.columns).eq("student_id", value: profile.id).limit(400).execute().value) ?? []
            async let marks: [RecentMark] = (try? await client.from("assessment_results_v2")
                .select("assessment_id, student_id, score, updated_at, assessments_v2(subject, title, max_score, date)")
                .eq("student_id", value: profile.id).order("updated_at", ascending: false).limit(10).execute().value) ?? []
            report = try await card
            attendance = try await register
            recent = try await marks
            let weeks: [WeekReview] = (try? await client.rpc("student_week_review", params: ["p_student": profile.id.uuidString]).execute().value) ?? []
            week = weeks.first
        } catch {}
        loading = false
    }

    var graded: [ReportRow] { report.filter { $0.graded && $0.total != nil } }
    var overall: Double? {
        let g = graded.compactMap { $0.total }
        return g.isEmpty ? nil : g.reduce(0, +) / Double(g.count)
    }
    var best: ReportRow? { graded.max { ($0.total ?? 0) < ($1.total ?? 0) } }
    var worst: ReportRow? { graded.min { ($0.total ?? 0) < ($1.total ?? 0) } }
    var rate: Int? {
        guard !attendance.isEmpty else { return nil }
        let here = attendance.filter { $0.status == "present" || $0.status == "late" }.count
        return Int((Double(here) * 100 / Double(attendance.count)).rounded())
    }
    func count(_ s: AttendanceStatus) -> Int { attendance.filter { $0.status == s.rawValue }.count }
}

struct InsightsView: View {
    let profile: Profile
    @State private var store = InsightsStore()
    @State private var school: SchoolRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.graded.isEmpty && store.attendance.isEmpty {
                    ContentUnavailableView("Nothing to show yet", systemImage: "chart.bar.doc.horizontal",
                                           description: Text("Once your teachers enter marks and take the register, this page fills itself in."))
                } else {
                    if !store.graded.isEmpty { subjects }
                    if let week = store.week, let history = week.history, history.count > 1 { weekly(week, history) }
                    if !store.attendance.isEmpty { register }
                    if !store.recent.isEmpty { latest }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            school = try? await DarsData.school(profile.schoolId)
            await store.load(for: profile, school: school)
        }
    }

    private var subjects: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Every subject", trailing: store.overall.map { "average \(Int($0.rounded()))" })
            Chart(store.graded) { row in
                BarMark(
                    x: .value("Mark", row.total ?? 0),
                    y: .value("Subject", row.subject)
                )
                .foregroundStyle(Band(row.total ?? 0).color)
                .cornerRadius(5)
                .annotation(position: .trailing) {
                    Text(String(Int((row.total ?? 0).rounded()))).font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis { AxisMarks(values: [0, 50, 100]) }
            .frame(height: CGFloat(store.graded.count) * 34 + 30)
            .padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let best = store.best, let worst = store.worst, best.subject != worst.subject {
                HStack(spacing: 10) {
                    StatTile(value: best.total.map { String(Int($0.rounded())) } ?? "—", label: "Best · \(best.subject)", symbol: "arrow.up.right", tint: DarsColor.success)
                    StatTile(value: worst.total.map { String(Int($0.rounded())) } ?? "—", label: "Weakest · \(worst.subject)", symbol: "arrow.down.right", tint: (worst.total ?? 100) < 50 ? DarsColor.danger : DarsColor.warning)
                }
            }
        }
    }

    private func weekly(_ week: InsightsStore.WeekReview, _ history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("How the last weeks went", trailing: week.teachers.map { "\($0) teachers" })
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(week.average.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(DarsColor.accentLabel)
                    Text("out of 5 this week").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                }
                Chart(Array(history.reversed().enumerated()), id: \.offset) { point in
                    LineMark(x: .value("Week", point.offset), y: .value("Stars", point.element))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(DarsColor.accent)
                    PointMark(x: .value("Week", point.offset), y: .value("Stars", point.element))
                        .foregroundStyle(DarsColor.accent)
                }
                .chartYScale(domain: 0...5)
                .chartXAxis(.hidden)
                .frame(height: 110)
                if let notes = week.notes, !notes.isEmpty {
                    ForEach(Array(notes.prefix(3).enumerated()), id: \.offset) { _, note in
                        Text("“\(note)”").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                    }
                }
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var register: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Attendance", trailing: store.rate.map { "\($0)% here" })
            Chart {
                ForEach(AttendanceStatus.allCases) { s in
                    SectorMark(angle: .value("Days", store.count(s)), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(s.color)
                        .cornerRadius(3)
                }
            }
            .frame(height: 150)
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(store.rate.map { "\($0)%" } ?? "—").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
                    Text("here").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                }
            }
            HStack(spacing: 12) {
                ForEach(AttendanceStatus.allCases) { s in
                    HStack(spacing: 5) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text("\(String(store.count(s))) \(s.label.lowercased())").darsType(.caption).foregroundStyle(DarsColor.labelSecondary)
                    }
                }
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var latest: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Latest marks")
            CardList {
                ForEach(Array(store.recent.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { RowDivider(inset: Metrics.Space.md) }
                    HStack(spacing: 12) {
                        Rectangle().fill(SubjectColor.of(m.assessment?.subject)).frame(width: 4, height: 30).clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.assessment?.subject ?? "—").darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
                            Text(m.assessment?.title ?? "").darsType(.caption).foregroundStyle(DarsColor.labelTertiary).lineLimit(1)
                        }
                        Spacer()
                        if let score = m.score, let max = m.assessment?.maxScore {
                            Text("\(fmt(score)) / \(fmt(max))")
                                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                                .foregroundStyle(m.percent.map { Band($0).color } ?? DarsColor.labelPrimary)
                        }
                    }
                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                }
            }
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
