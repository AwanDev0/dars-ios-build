import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class AttendanceCalendarStore {
    private(set) var rows: [AttendanceRow] = []
    private(set) var loading = true
    var month: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()

    func load(student: UUID) async {
        do {
            rows = try await SupabaseService.client.from("attendance").select(AttendanceRow.columns)
                .eq("student_id", value: student).order("date", ascending: false).limit(400).execute().value
        } catch { rows = [] }
        loading = false
    }

    var byDay: [String: AttendanceRow] { Dictionary(rows.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a }) }
    func count(_ s: AttendanceStatus) -> Int { rows.filter { $0.status == s.rawValue }.count }
    var rate: Int? {
        guard !rows.isEmpty else { return nil }
        let here = rows.filter { $0.status == "present" || $0.status == "late" }.count
        return Int((Double(here) * 100 / Double(rows.count)).rounded())
    }
    var monthRows: [AttendanceRow] {
        let key = String(DayKey.string(month).prefix(7))
        return rows.filter { $0.date.hasPrefix(key) }.sorted { $0.date > $1.date }
    }
}

struct AttendanceCalendarView: View {
    let student: Profile
    @State private var store = AttendanceCalendarStore()
    @Environment(LanguageStore.self) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    summary
                    monthHeader
                    MonthGrid(month: store.month, marks: store.byDay)
                    legend
                    if !store.monthRows.isEmpty {
                        SectionLabel("This month")
                        CardList {
                            ForEach(Array(store.monthRows.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { RowDivider(inset: Metrics.Space.md) }
                                let s = AttendanceStatus(rawValue: r.status) ?? .present
                                HStack(spacing: 12) {
                                    Circle().fill(s.color).frame(width: 10, height: 10)
                                    Text(DayKey.date(r.date)?.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) ?? r.date).darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary)
                                    Spacer()
                                    Text(LocalizedStringKey(s.label)).darsType(.footnote).foregroundStyle(s.color)
                                }
                                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11)
                                if let note = r.note, !note.isEmpty {
                                    Text(note).darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, Metrics.Space.md).padding(.bottom, 8)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(student.displayName(kurdish: language.language.isKurdish))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(student: student.id) }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatTile(value: store.rate.map { "\($0)%" } ?? "—", label: "Attendance", symbol: "checkmark.seal.fill", tint: DarsColor.success)
            StatTile(value: String(store.count(.absent)), label: "Absent", symbol: "xmark.circle.fill", tint: DarsColor.danger)
            StatTile(value: String(store.count(.late)), label: "Late", symbol: "clock.fill", tint: DarsColor.warning)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36).background(DarsColor.surface, in: Circle()) }
            Spacer()
            Text(store.month.formatted(.dateTime.month(.wide).year())).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36).background(DarsColor.surface, in: Circle()) }
        }
        .foregroundStyle(DarsColor.labelPrimary)
    }

    private func shift(_ by: Int) {
        HapticEngine.play(.selection)
        withAnimation(Motion.selection) { store.month = Calendar.current.date(byAdding: .month, value: by, to: store.month) ?? store.month }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(AttendanceStatus.allCases) { s in
                HStack(spacing: 5) {
                    Circle().fill(s.color).frame(width: 8, height: 8)
                    Text(LocalizedStringKey(s.label)).darsType(.caption).foregroundStyle(DarsColor.labelSecondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct MonthGrid: View {
    let month: Date
    let marks: [String: AttendanceRow]

    var body: some View {
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: month)
        let lead = firstWeekday - 1
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        VStack(spacing: 6) {
            HStack {
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[i]).font(.system(size: 11, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(1...days, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: month)!
                    let key = DayKey.string(date)
                    let status = marks[key].flatMap { AttendanceStatus(rawValue: $0.status) }
                    let today = cal.isDateInToday(date)
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(status.map { $0.color.opacity(0.18) } ?? DarsColor.surface)
                        if today { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DarsColor.accent, lineWidth: 1.5) }
                        VStack(spacing: 2) {
                            Text(String(d)).font(.system(size: 13, weight: today ? .bold : .medium)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
                            Circle().fill(status?.color ?? .clear).frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 36)
                }
            }
        }
        .padding(10)
        .background(DarsColor.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
