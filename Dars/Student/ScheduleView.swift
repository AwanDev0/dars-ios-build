import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class ScheduleStore {
    private(set) var week: [String: [ScheduleItem]] = [:]
    private(set) var loading = true
    private(set) var error: DarsError?
    var day: String = ScheduleStore.schoolDay(TodayStore.todayKey())

    static let days = ["Sun", "Mon", "Tue", "Wed", "Thu"]
    private let client = SupabaseService.client

    static func schoolDay(_ key: String) -> String { days.contains(key) ? key : "Sun" }

    func load(classId: UUID?) async {
        error = nil
        guard let classId else { loading = false; return }
        do {
            let items: [ScheduleItem] = try await client.from("schedule_items").select(ScheduleItem.columns)
                .eq("class_id", value: classId).order("sort_order").execute().value
            week = Dictionary(grouping: items, by: { $0.dayOfWeek ?? "" })
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    func load(student: Profile) async {
        do {
            let rows: [StudentClass] = try await client.rpc("student_class", params: ["uid": student.id.uuidString]).execute().value
            await load(classId: rows.first?.classId)
        } catch {
            self.error = .server(String(describing: error))
            loading = false
        }
    }

    var items: [ScheduleItem] { week[day] ?? [] }
    var lessons: Int { items.filter { !$0.isBreak }.count }
}

struct ScheduleView: View {
    let profile: Profile
    var classId: UUID? = nil
    var title: LocalizedStringKey = "Schedule"
    @State private var store = ScheduleStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                ScreenTitle(title: title, subtitle: store.loading ? nil : "\(dayName(store.day)) · \(store.lessons) lessons")
                WeekPicker(day: $store.day)
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.items.isEmpty {
                    EmptyCard("No lessons this day.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.items) { p in PeriodRow(item: p) }
                    }
                    .animation(Motion.arrive, value: store.day)
                }
                if let error = store.error { error.messageText.darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .task {
            if let classId { await store.load(classId: classId) } else { await store.load(student: profile) }
        }
        .refreshable {
            if let classId { await store.load(classId: classId) } else { await store.load(student: profile) }
        }
    }
}

struct WeekPicker: View {
    @Binding var day: String
    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleStore.days, id: \.self) { d in
                let on = d == day
                let today = d == TodayStore.todayKey()
                Button {
                    HapticEngine.play(.selection)
                    withAnimation(Motion.selection) { day = d }
                } label: {
                    VStack(spacing: 3) {
                        Text(String(dayName(d).prefix(3))).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? DarsColor.onAccent : DarsColor.labelPrimary)
                        Circle().fill(today ? (on ? DarsColor.onAccent : DarsColor.accent) : .clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(on ? DarsColor.accent : DarsColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PeriodRow: View {
    let item: ScheduleItem
    var now: Bool = false
    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String((item.startTime ?? "").prefix(5))).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(item.isBreak ? DarsColor.labelTertiary : DarsColor.labelPrimary)
                Text(String((item.endTime ?? "").prefix(5))).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(DarsColor.labelTertiary)
            }
            .frame(width: 48, alignment: .leading)
            if item.isBreak {
                Text("Break").darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(DarsColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                HStack(spacing: 0) {
                    Rectangle().fill(SubjectColor.of(item.subject)).frame(width: 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.subject ?? "").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text([item.teacher, item.room].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    Spacer(minLength: 0)
                    if now {
                        Text("Now").font(.system(size: 11, weight: .bold)).foregroundStyle(DarsColor.onAccent)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(DarsColor.accent, in: Capsule()).padding(.trailing, 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

func dayName(_ key: String) -> String {
    let keys = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    guard let i = keys.firstIndex(of: key) else { return key }
    return Calendar.current.weekdaySymbols[i]
}
