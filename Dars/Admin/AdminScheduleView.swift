import Foundation
import Observation
import SwiftUI
import Supabase

struct TimetableItem: Codable, Identifiable, Hashable, Sendable {
    static let columns = "id, day_of_week, subject, teacher, teacher_id, room, start_time, end_time, is_break, sort_order"
    var id: String
    var dayOfWeek: String?
    var subject: String?
    var teacher: String?
    var teacherId: UUID?
    var room: String?
    var startTime: String?
    var endTime: String?
    var isBreak: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, subject, teacher, room
        case dayOfWeek = "day_of_week"
        case teacherId = "teacher_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case isBreak = "is_break"
        case sortOrder = "sort_order"
    }
}

struct TimetableBell: Identifiable, Hashable, Sendable {
    var slot: Int
    var start: String
    var end: String
    var isBreak: Bool
    var label: String?
    var period: Int = 0
    var id: Int { slot }
    var minutes: Int { Clock.minutes(end) - Clock.minutes(start) }
}

struct TeacherChoice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let subject: String?
}

struct TimetableCell: Hashable, Identifiable, Sendable {
    let day: String
    let slot: Int
    var id: String { "\(day)-\(slot)" }
}

enum Clock {
    static func minutes(_ s: String) -> Int {
        let parts = s.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        return h * 60 + m
    }

    static func string(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }

    static func date(_ s: String) -> Date {
        let m = minutes(s)
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    static func string(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

struct BellTemplate: Equatable {
    var start = Clock.date("08:00")
    var periodMinutes = 45
    var periods = 7
    var breaksAfter: Set<Int> = [3]
    var breakMinutes = 20

    func bells() -> [TimetableBell] {
        var out: [TimetableBell] = []
        var t = Clock.minutes(Clock.string(start))
        var slot = 0
        for p in 1...max(periods, 1) {
            out.append(TimetableBell(slot: slot, start: Clock.string(t), end: Clock.string(t + periodMinutes), isBreak: false, period: p))
            slot += 1
            t += periodMinutes
            if breaksAfter.contains(p) && p < periods {
                out.append(TimetableBell(slot: slot, start: Clock.string(t), end: Clock.string(t + breakMinutes), isBreak: true, label: "Break"))
                slot += 1
                t += breakMinutes
            }
        }
        return out
    }

    static func from(_ bells: [TimetableBell]) -> BellTemplate {
        guard let first = bells.first else { return BellTemplate() }
        var template = BellTemplate()
        template.start = Clock.date(first.start)
        let lessons = bells.filter { !$0.isBreak }
        template.periods = max(lessons.count, 1)
        if let m = lessons.first?.minutes, m > 0 { template.periodMinutes = m }
        if let m = bells.first(where: { $0.isBreak })?.minutes, m > 0 { template.breakMinutes = m }
        var index = 0
        var after = Set<Int>()
        for b in bells {
            if b.isBreak { after.insert(index) } else { index += 1 }
        }
        template.breaksAfter = after
        return template
    }
}

@MainActor
@Observable
final class AdminScheduleStore {
    static let days = ["Sun", "Mon", "Tue", "Wed", "Thu"]

    private(set) var classes: [ClassRow] = []
    private(set) var classId: UUID?
    private(set) var bells: [TimetableBell] = []
    private(set) var week: [String: [TimetableItem]] = [:]
    private(set) var teachers: [TeacherChoice] = []
    private(set) var rooms: [String] = []
    private(set) var loading = true
    private(set) var saving = false
    private(set) var canUndo = false
    var error: String?

    private struct Edit { let cell: TimetableCell; let before: TimetableItem? }
    private var undoStack: [Edit] = []
    private var tail: Task<Void, Never>?
    private let client = SupabaseService.client

    private struct BellRow: Decodable { let sort_order: Int; let start_time: String; let end_time: String; let is_break: Bool?; let label: String? }
    private struct TeacherRow: Decodable { let id: UUID; let full_name: String?; let subject: String? }
    private struct RoomRow: Decodable { let room: String? }

    private struct SetSlotArgs: Encodable, Sendable {
        let p_class: UUID
        let p_day: String
        let p_slot: Int
        let p_subject: String
        let p_teacher: UUID?
        let p_room: String
        enum CodingKeys: String, CodingKey { case p_class, p_day, p_slot, p_subject, p_teacher, p_room }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_class, forKey: .p_class)
            try c.encode(p_day, forKey: .p_day)
            try c.encode(p_slot, forKey: .p_slot)
            try c.encode(p_subject, forKey: .p_subject)
            try c.encode(p_teacher, forKey: .p_teacher)
            try c.encode(p_room, forKey: .p_room)
        }
    }
    private struct ClearArgs: Encodable, Sendable { let p_class: UUID; let p_day: String; let p_slot: Int }
    private struct CopyDayArgs: Encodable, Sendable { let p_class: UUID; let p_from: String; let p_to: [String] }
    private struct CopyClassArgs: Encodable, Sendable { let p_from: UUID; let p_to: UUID }
    private struct BellPayload: Encodable, Sendable {
        let start: String
        let end: String
        let is_break: Bool
        let label: String?
        enum CodingKeys: String, CodingKey { case start, end, is_break, label }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
            try c.encode(is_break, forKey: .is_break)
            try c.encode(label, forKey: .label)
        }
    }
    private struct BellsArgs: Encodable, Sendable { let p_bells: [BellPayload] }
    private struct InsertBellArgs: Encodable, Sendable {
        let p_at: Int
        let p_start: String
        let p_end: String
        let p_is_break: Bool
        let p_label: String?
        enum CodingKeys: String, CodingKey { case p_at, p_start, p_end, p_is_break, p_label }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_at, forKey: .p_at)
            try c.encode(p_start, forKey: .p_start)
            try c.encode(p_end, forKey: .p_end)
            try c.encode(p_is_break, forKey: .p_is_break)
            try c.encode(p_label, forKey: .p_label)
        }
    }
    private struct UpdateBellArgs: Encodable, Sendable {
        let p_at: Int
        let p_start: String
        let p_end: String
        let p_label: String?
        enum CodingKeys: String, CodingKey { case p_at, p_start, p_end, p_label }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_at, forKey: .p_at)
            try c.encode(p_start, forKey: .p_start)
            try c.encode(p_end, forKey: .p_end)
            try c.encode(p_label, forKey: .p_label)
        }
    }
    private struct DeleteBellArgs: Encodable, Sendable { let p_at: Int }

    var currentClass: ClassRow? { classes.first { $0.id == classId } }
    var lessonBells: [TimetableBell] { bells.filter { !$0.isBreak } }
    var totalCells: Int { lessonBells.count * Self.days.count }
    var filledCells: Int {
        Self.days.reduce(0) { sum, d in sum + lessonBells.filter { cell(d, $0.slot) != nil }.count }
    }

    func cell(_ day: String, _ slot: Int) -> TimetableItem? {
        week[day]?.first { $0.sortOrder == slot && !$0.isBreak && !($0.subject ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func filled(on day: String) -> Int { lessonBells.filter { cell(day, $0.slot) != nil }.count }

    func teacherFor(_ subject: String) -> TeacherChoice? {
        let used = week.values.joined().first { $0.subject == subject && $0.teacherId != nil }?.teacherId
        if let used, let t = teachers.first(where: { $0.id == used }) { return t }
        let matching = teachers.filter { ($0.subject ?? "").caseInsensitiveCompare(subject) == .orderedSame }
        return matching.first
    }

    func roomFor(_ subject: String) -> String? {
        week.values.joined().first { $0.subject == subject && !($0.room ?? "").isEmpty }?.room
    }

    private var order: [TimetableCell] {
        Self.days.flatMap { d in lessonBells.map { TimetableCell(day: d, slot: $0.slot) } }
    }

    func nextEmpty(after cell: TimetableCell) -> TimetableCell? {
        let all = order
        guard let i = all.firstIndex(of: cell) else { return firstEmpty() }
        let rotated = Array(all[(i + 1)...]) + Array(all[...i])
        return rotated.first { self.cell($0.day, $0.slot) == nil }
    }

    func firstEmpty() -> TimetableCell? { order.first { cell($0.day, $0.slot) == nil } }

    var subjects: [String] {
        let base = Curriculum.forGrade(currentClass?.grade)
        let extra = week.values.joined().filter { !$0.isBreak }.compactMap { s -> String? in
            let t = (s.subject ?? "").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        var seen = Set<String>()
        return (base + extra).filter { seen.insert($0).inserted }
    }

    func load(preselected: UUID?) async {
        loading = classes.isEmpty
        error = nil
        do {
            let rows = try await DarsData.allClasses()
            classes = rows
            if let preselected, rows.contains(where: { $0.id == preselected }) {
                classId = preselected
            } else if classId == nil || !rows.contains(where: { $0.id == classId }) {
                classId = rows.first?.id
            }
            let people: [TeacherRow] = (try? await client.from("profiles").select("id, full_name, subject").eq("role", value: "teacher").order("full_name").execute().value) ?? []
            teachers = people.map { TeacherChoice(id: $0.id, name: ($0.full_name ?? "").isEmpty ? "—" : $0.full_name!, subject: $0.subject?.trimmingCharacters(in: .whitespaces)) }
            let roomRows: [RoomRow] = (try? await client.from("schedule_items").select("room").neq("room", value: "").execute().value) ?? []
            var seen = Set<String>()
            rooms = roomRows.compactMap { $0.room?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }.sorted()
            await loadBells()
            await loadWeek()
        } catch {
            self.error = Self.describe(error)
        }
        loading = false
    }

    func loadBells() async {
        let rows: [BellRow] = (try? await client.from("school_bells").select("sort_order, start_time, end_time, is_break, label").order("sort_order").execute().value) ?? []
        var n = 0
        bells = rows.map { r in
            let isBreak = r.is_break ?? false
            if !isBreak { n += 1 }
            return TimetableBell(slot: r.sort_order, start: String(r.start_time.prefix(5)), end: String(r.end_time.prefix(5)), isBreak: isBreak, label: r.label, period: isBreak ? 0 : n)
        }
    }

    func loadWeek() async {
        guard let classId else { week = [:]; return }
        let rows: [TimetableItem] = (try? await client.from("schedule_items").select(TimetableItem.columns).eq("class_id", value: classId).order("sort_order").execute().value) ?? []
        guard classId == self.classId else { return }
        week = Dictionary(grouping: rows, by: { $0.dayOfWeek ?? "" })
    }

    func selectClass(_ id: UUID) {
        guard id != classId else { return }
        classId = id
        undoStack.removeAll()
        canUndo = false
        week = [:]
        Task { await loadWeek() }
    }

    func setSlot(_ cell: TimetableCell, subject: String, teacher: UUID?, room: String?) {
        guard let classId, let bell = bells.first(where: { $0.slot == cell.slot }) else { return }
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { return }
        let before = self.cell(cell.day, cell.slot)
        let cleanRoom = room?.trimmingCharacters(in: .whitespaces)
        let item = TimetableItem(
            id: before?.id ?? "local-\(cell.day)-\(cell.slot)",
            dayOfWeek: cell.day,
            subject: subject,
            teacher: teachers.first { $0.id == teacher }?.name,
            teacherId: teacher,
            room: (cleanRoom ?? "").isEmpty ? nil : cleanRoom,
            startTime: bell.start,
            endTime: bell.end,
            isBreak: false,
            sortOrder: cell.slot
        )
        remember(Edit(cell: cell, before: before))
        apply(cell, item)
        if let r = item.room, !rooms.contains(r) { rooms = (rooms + [r]).sorted() }
        queue(revert: { [weak self] in self?.apply(cell, before) }) { [client] in
            try await client.rpc("admin_set_slot", params: SetSlotArgs(p_class: classId, p_day: cell.day, p_slot: cell.slot, p_subject: subject, p_teacher: teacher, p_room: item.room ?? "")).execute()
        }
    }

    func clearSlot(_ cell: TimetableCell) {
        guard let classId, let before = self.cell(cell.day, cell.slot) else { return }
        remember(Edit(cell: cell, before: before))
        apply(cell, nil)
        queue(revert: { [weak self] in self?.apply(cell, before) }) { [client] in
            try await client.rpc("admin_clear_slot", params: ClearArgs(p_class: classId, p_day: cell.day, p_slot: cell.slot)).execute()
        }
    }

    func undo() {
        guard let classId, let edit = undoStack.popLast() else { return }
        canUndo = !undoStack.isEmpty
        let now = cell(edit.cell.day, edit.cell.slot)
        apply(edit.cell, edit.before)
        let prev = edit.before
        queue(revert: { [weak self] in self?.apply(edit.cell, now) }) { [client] in
            if let prev {
                try await client.rpc("admin_set_slot", params: SetSlotArgs(p_class: classId, p_day: edit.cell.day, p_slot: edit.cell.slot, p_subject: prev.subject ?? "", p_teacher: prev.teacherId, p_room: prev.room ?? "")).execute()
            } else {
                try await client.rpc("admin_clear_slot", params: ClearArgs(p_class: classId, p_day: edit.cell.day, p_slot: edit.cell.slot)).execute()
            }
        }
        HapticEngine.play(.selection)
    }

    func clearDay(_ day: String) {
        guard let classId else { return }
        let slots = lessonBells.compactMap { cell(day, $0.slot) != nil ? $0.slot : nil }
        guard !slots.isEmpty else { return }
        forgetUndo()
        write { [client] in
            for slot in slots {
                try await client.rpc("admin_clear_slot", params: ClearArgs(p_class: classId, p_day: day, p_slot: slot)).execute()
            }
        }
    }

    func copyDay(_ from: String) {
        guard let classId else { return }
        let others = Self.days.filter { $0 != from }
        forgetUndo()
        write { [client] in
            try await client.rpc("admin_copy_day", params: CopyDayArgs(p_class: classId, p_from: from, p_to: others)).execute()
        }
    }

    func copyClass(to target: UUID) {
        guard let classId, classId != target else { return }
        write { [client] in
            try await client.rpc("admin_copy_class", params: CopyClassArgs(p_from: classId, p_to: target)).execute()
        }
    }

    func saveTemplate(_ template: BellTemplate) {
        forgetUndo()
        let list = template.bells()
        write { [weak self] in
            try await self?.sendBells(list)
            await self?.loadBells()
        }
    }

    func updateBell(_ slot: Int, start: String, end: String, label: String?, moveLater: Bool) {
        guard let old = bells.first(where: { $0.slot == slot }) else { return }
        let delta = Clock.minutes(end) - Clock.minutes(old.end)
        let current = bells
        write { [weak self, client] in
            if moveLater && delta != 0 && current.contains(where: { $0.slot > slot }) {
                let retimed = current.map { b -> TimetableBell in
                    var b = b
                    if b.slot == slot {
                        b.start = start; b.end = end
                        if b.isBreak { b.label = label ?? b.label }
                    } else if b.slot > slot {
                        b.start = Clock.string(Clock.minutes(b.start) + delta)
                        b.end = Clock.string(Clock.minutes(b.end) + delta)
                    }
                    return b
                }
                try await self?.sendBells(retimed)
            } else {
                try await client.rpc("admin_update_bell", params: UpdateBellArgs(p_at: slot, p_start: start, p_end: end, p_label: label)).execute()
            }
            await self?.loadBells()
        }
    }

    func insertBell(at: Int, isBreak: Bool, minutes: Int, label: String?) {
        let current = bells
        let start = at > 0 ? (current.first { $0.slot == at - 1 }?.end ?? current.last?.end ?? "08:00") : (current.first?.start ?? "08:00")
        let end = Clock.string(Clock.minutes(start) + minutes)
        forgetUndo()
        write { [weak self, client] in
            try await client.rpc("admin_insert_bell", params: InsertBellArgs(p_at: at, p_start: start, p_end: end, p_is_break: isBreak, p_label: label)).execute()
            if at < current.count {
                var shifted: [TimetableBell] = current.filter { $0.slot < at }
                shifted.append(TimetableBell(slot: at, start: start, end: end, isBreak: isBreak, label: label ?? (isBreak ? "Break" : nil)))
                for b in current where b.slot >= at {
                    var moved = b
                    moved.slot = b.slot + 1
                    moved.start = Clock.string(Clock.minutes(b.start) + minutes)
                    moved.end = Clock.string(Clock.minutes(b.end) + minutes)
                    shifted.append(moved)
                }
                try await self?.sendBells(shifted)
            }
            await self?.loadBells()
        }
    }

    func deleteBell(_ slot: Int) {
        guard bells.count > 1 else { return }
        forgetUndo()
        write { [weak self, client] in
            try await client.rpc("admin_delete_bell", params: DeleteBellArgs(p_at: slot)).execute()
            await self?.loadBells()
        }
    }

    private func sendBells(_ list: [TimetableBell]) async throws {
        let payload = list.sorted { $0.slot < $1.slot }.map { BellPayload(start: $0.start, end: $0.end, is_break: $0.isBreak, label: $0.label) }
        try await client.rpc("admin_set_bells", params: BellsArgs(p_bells: payload)).execute()
    }

    private func remember(_ edit: Edit) {
        undoStack.append(edit)
        if undoStack.count > 50 { undoStack.removeFirst() }
        canUndo = true
    }

    private func forgetUndo() {
        undoStack.removeAll()
        canUndo = false
    }

    private func apply(_ cell: TimetableCell, _ item: TimetableItem?) {
        var list = (week[cell.day] ?? []).filter { !($0.sortOrder == cell.slot && !$0.isBreak) }
        if let item { list.append(item) }
        week[cell.day] = list.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func queue(revert: @escaping @MainActor () -> Void, _ job: @escaping @MainActor () async throws -> Void) {
        let previous = tail
        tail = Task { @MainActor [weak self] in
            await previous?.value
            do {
                try await job()
            } catch {
                revert()
                self?.error = Self.describe(error)
                HapticEngine.play(.error)
            }
        }
    }

    private func write(_ job: @escaping @MainActor () async throws -> Void) {
        let previous = tail
        tail = Task { @MainActor [weak self] in
            await previous?.value
            self?.saving = true
            self?.error = nil
            do {
                try await job()
                HapticEngine.play(.success)
            } catch {
                self?.error = Self.describe(error)
                HapticEngine.play(.error)
            }
            await self?.loadWeek()
            self?.saving = false
        }
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? URLError, e.code == .notConnectedToInternet || e.code == .timedOut {
            return "No connection. The last change was not saved."
        }
        return String(describing: error)
    }
}

struct AdminScheduleView: View {
    let me: Profile
    var preselected: UUID?

    @Environment(LanguageStore.self) private var language
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = AdminScheduleStore()
    @State private var selection: TimetableCell?
    @State private var bellEditing: TimetableBell?
    @State private var detailsFor: TimetableCell?
    @State private var customFor: TimetableCell?
    @State private var showingBells = false
    @State private var showingTemplate = false
    @State private var showingCopyClass = false
    @State private var confirm: Confirm?
    @State private var weekDone = false

    private let timeWidth: CGFloat = 50
    private let gap: CGFloat = 4
    private let lessonHeight: CGFloat = 60
    private let breakHeight: CGFloat = 30

    enum Confirm: Identifiable {
        case copyDay(String)
        case clearDay(String)
        case deleteBell(TimetableBell)
        var id: String {
            switch self {
            case .copyDay(let d): return "copy-\(d)"
            case .clearDay(let d): return "clear-\(d)"
            case .deleteBell(let b): return "bell-\(b.slot)"
            }
        }
    }

    private var kurdish: Bool { language.language.isKurdish }

    var body: some View {
        VStack(spacing: 0) {
            if store.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.bells.isEmpty {
                noBells
            } else {
                dayHeader
                ScrollViewReader { proxy in
                    ScrollView {
                        grid
                            .padding(.horizontal, 12)
                            .padding(.bottom, 20)
                    }
                    .onChange(of: selection) { _, cell in
                        guard let cell else { return }
                        withAnimation(reduceMotion ? nil : Motion.decelerate) { proxy.scrollTo(cell, anchor: .center) }
                    }
                }
                if let selection {
                    palette(selection)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.decelerate, value: selection == nil)
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .hidesDarsTabBar()
        .overlay(alignment: .top) { banner }
        .task { await store.load(preselected: preselected) }
        .sheet(item: $bellEditing) { bell in
            BellEditSheet(
                bell: bell,
                isLast: bell.slot == store.bells.last?.slot,
                onSave: { start, end, label, moveLater in store.updateBell(bell.slot, start: start, end: end, label: label, moveLater: moveLater) },
                onInsert: { isBreak in store.insertBell(at: bell.slot + 1, isBreak: isBreak, minutes: isBreak ? 15 : (store.lessonBells.first?.minutes ?? 45), label: isBreak ? "Break" : nil) },
                onDelete: { confirm = .deleteBell(bell) }
            )
        }
        .sheet(item: $detailsFor) { cell in
            if let item = store.cell(cell.day, cell.slot) {
                TimetableDetailsSheet(
                    title: title(for: cell),
                    item: item,
                    teachers: store.teachers,
                    rooms: store.rooms,
                    onSave: { teacher, room in store.setSlot(cell, subject: item.subject ?? "", teacher: teacher, room: room) }
                )
            }
        }
        .sheet(item: $customFor) { cell in
            CustomSubjectSheet { name in fill(cell, subject: name) }
        }
        .sheet(isPresented: $showingBells) {
            BellsListSheet(
                bells: store.bells,
                onEdit: { bell in showingBells = false; bellEditing = bell },
                onTemplate: { showingBells = false; showingTemplate = true }
            )
        }
        .sheet(isPresented: $showingTemplate) {
            BellTemplateSheet(template: BellTemplate.from(store.bells)) { store.saveTemplate($0) }
        }
        .sheet(isPresented: $showingCopyClass) {
            CopyWeekSheet(classes: store.classes.filter { $0.id != store.classId }, from: store.currentClass?.label ?? "") { target in
                store.copyClass(to: target)
            }
        }
        .alert(item: $confirm) { c in
            switch c {
            case .copyDay(let d):
                let name = DayName.full(d, kurdish: kurdish)
                return Alert(
                    title: Text("Copy \(name) to the other days?"),
                    message: Text("The other days become the same as \(name)."),
                    primaryButton: .default(Text("Copy")) { store.copyDay(d) },
                    secondaryButton: .cancel()
                )
            case .clearDay(let d):
                let name = DayName.full(d, kurdish: kurdish)
                return Alert(
                    title: Text("Clear \(name)?"),
                    message: Text("Every lesson on \(name) is removed."),
                    primaryButton: .destructive(Text("Clear")) { store.clearDay(d) },
                    secondaryButton: .cancel()
                )
            case .deleteBell(let b):
                return Alert(
                    title: Text(b.isBreak ? "Delete this break?" : "Delete this period?"),
                    message: Text("Its lessons are removed from every class."),
                    primaryButton: .destructive(Text("Delete")) { selection = nil; store.deleteBell(b.slot) },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(store.classes) { c in
                    Button {
                        selection = nil
                        store.selectClass(c.id)
                    } label: {
                        if c.id == store.classId { Label(c.label, systemImage: "checkmark") } else { Text(verbatim: c.label) }
                    }
                }
                Divider()
                Button("Copy this week to another class", systemImage: "doc.on.doc") { showingCopyClass = true }
                    .disabled(store.classes.count < 2)
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text(verbatim: store.currentClass?.label ?? "—").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(DarsColor.labelSecondary)
                    }
                    Text("\(store.filledCells) of \(store.totalCells) lessons set").darsType(.caption).foregroundStyle(DarsColor.labelSecondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingBells = true } label: { Image(systemName: "clock") }
                .accessibilityLabel(Text("Bells"))
        }
    }

    private var dayHeader: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: timeWidth, height: 1)
            ForEach(AdminScheduleStore.days, id: \.self) { d in
                Menu {
                    Button("Copy to the other days", systemImage: "doc.on.doc") { confirm = .copyDay(d) }
                        .disabled(store.filled(on: d) == 0)
                    Button("Clear the day", systemImage: "trash", role: .destructive) { confirm = .clearDay(d) }
                        .disabled(store.filled(on: d) == 0)
                } label: {
                    VStack(spacing: 3) {
                        Text(verbatim: DayName.short(d, kurdish: kurdish))
                            .darsType(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(isToday(d) ? DarsColor.accentLabel : DarsColor.labelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Circle().fill(isToday(d) ? DarsColor.accent : Color.clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(verbatim: DayName.full(d, kurdish: kurdish)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var grid: some View {
        VStack(spacing: gap) {
            ForEach(store.bells) { bell in
                if bell.isBreak {
                    breakRow(bell)
                } else {
                    lessonRow(bell)
                }
            }
            Button {
                let last = store.bells.last?.slot ?? -1
                store.insertBell(at: last + 1, isBreak: false, minutes: store.lessonBells.first?.minutes ?? 45, label: nil)
            } label: {
                Label("Add a period", systemImage: "plus")
                    .darsType(.headline)
                    .foregroundStyle(DarsColor.accentLabel)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func lessonRow(_ bell: TimetableBell) -> some View {
        HStack(spacing: gap) {
            Button { bellEditing = bell } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: bell.start).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
                    Text(verbatim: bell.end).font(.system(size: 12, weight: .regular)).monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
                }
                .frame(width: timeWidth, height: lessonHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Period \(bell.period), \(bell.start) to \(bell.end)"))
            ForEach(AdminScheduleStore.days, id: \.self) { d in
                lessonCell(TimetableCell(day: d, slot: bell.slot))
            }
        }
        .frame(height: lessonHeight)
    }

    private func breakRow(_ bell: TimetableBell) -> some View {
        Button { bellEditing = bell } label: {
            HStack(spacing: gap) {
                Text(verbatim: bell.start).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
                    .frame(width: timeWidth, alignment: .leading)
                Text("\(breakName(bell)) · \(bell.minutes) min")
                    .darsType(.footnote)
                    .foregroundStyle(DarsColor.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: breakHeight)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func breakName(_ bell: TimetableBell) -> String {
        let label = (bell.label ?? "").trimmingCharacters(in: .whitespaces)
        if label.isEmpty || label == "Break" { return kurdish ? "پشوو" : "Break" }
        return label
    }

    private func lessonCell(_ cell: TimetableCell) -> some View {
        let item = store.cell(cell.day, cell.slot)
        let isSelected = selection == cell
        let color = SubjectColor.of(item?.subject)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            HapticEngine.play(.selection)
            selection = isSelected ? nil : cell
        } label: {
            ZStack(alignment: .topLeading) {
                shape.fill(item == nil ? DarsColor.surface.opacity(scheme == .dark ? 0.55 : 0.8) : color.opacity(scheme == .dark ? 0.30 : 0.16))
                if let item {
                    HStack(spacing: 0) {
                        Rectangle().fill(color).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: SubjectName.short(item.subject, kurdish: kurdish))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DarsColor.labelPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                            if let t = item.teacher, !t.isEmpty {
                                Text(verbatim: t)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(DarsColor.labelSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 5)
                        .padding(.trailing, 3)
                        .padding(.vertical, 5)
                        Spacer(minLength: 0)
                    }
                } else if isSelected {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DarsColor.accentLabel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(shape)
            .overlay {
                if isSelected { shape.strokeBorder(DarsColor.accent, lineWidth: 2.5) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .id(cell)
        .contextMenu {
            if item != nil {
                Button("Teacher & room", systemImage: "person.crop.rectangle") { detailsFor = cell }
                Button("Clear", systemImage: "xmark", role: .destructive) { store.clearSlot(cell) }
            }
        }
        .accessibilityLabel(Text(verbatim: accessibility(cell, item)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibility(_ cell: TimetableCell, _ item: TimetableItem?) -> String {
        let day = DayName.full(cell.day, kurdish: kurdish)
        let period = store.bells.first { $0.slot == cell.slot }?.period ?? 0
        let what = item.map { SubjectName.label($0.subject, kurdish: kurdish) } ?? (kurdish ? "بەتاڵ" : "Empty")
        return "\(day), \(period): \(what)"
    }

    private func title(for cell: TimetableCell) -> String {
        let day = DayName.full(cell.day, kurdish: kurdish)
        let period = store.bells.first { $0.slot == cell.slot }?.period ?? 0
        return kurdish ? "\(day) · وانەی \(period)" : "\(day) · Period \(period)"
    }

    private func palette(_ cell: TimetableCell) -> some View {
        let bell = store.bells.first { $0.slot == cell.slot }
        let item = store.cell(cell.day, cell.slot)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title(for: cell)).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    Text(verbatim: "\(bell?.start ?? "")–\(bell?.end ?? "")").darsType(.caption).monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
                }
                Spacer(minLength: 4)
                if store.canUndo {
                    pill("Undo", symbol: "arrow.uturn.backward") { store.undo() }
                }
                Button { selection = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(DarsColor.labelSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Done"))
            }
            .padding(.horizontal, 16)
            if item != nil {
                HStack(spacing: 8) {
                    pill("Teacher & room", symbol: "person.crop.rectangle") { detailsFor = cell }
                    pill("Clear", symbol: "xmark", tint: DarsColor.danger) { store.clearSlot(cell) }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.subjects, id: \.self) { subject in
                        let on = item?.subject == subject
                        Button { fill(cell, subject: subject) } label: {
                            HStack(spacing: 7) {
                                Circle().fill(SubjectColor.of(subject)).frame(width: 8, height: 8)
                                Text(verbatim: SubjectName.label(subject, kurdish: kurdish))
                                    .darsType(.subheadline)
                                    .foregroundStyle(DarsColor.labelPrimary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(SubjectColor.of(subject).opacity(on ? 0.34 : (scheme == .dark ? 0.18 : 0.10)), in: Capsule())
                            .overlay { if on { Capsule().strokeBorder(SubjectColor.of(subject), lineWidth: 1.5) } }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { customFor = cell } label: {
                        Label("Other", systemImage: "plus")
                            .darsType(.subheadline)
                            .foregroundStyle(DarsColor.labelPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(DarsColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func pill(_ title: LocalizedStringKey, symbol: String, tint: Color = DarsColor.labelPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .darsType(.subheadline)
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(DarsColor.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private func fill(_ cell: TimetableCell, subject: String) {
        let teacher = store.teacherFor(subject)
        let room = store.roomFor(subject)
        store.setSlot(cell, subject: subject, teacher: teacher?.id, room: room)
        if let next = store.nextEmpty(after: cell) {
            selection = next
        } else {
            selection = nil
            HapticEngine.play(.success)
            withAnimation(reduceMotion ? nil : Motion.decelerate) { weekDone = true }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(reduceMotion ? nil : Motion.decelerate) { weekDone = false }
            }
        }
    }

    private var noBells: some View {
        DarsEmptyState(title: "No bells yet", message: "Set when each lesson starts and ends. Every class uses the same bells.", systemImage: "clock") {
            DarsButton(title: "Set the bells", kind: .primary) { showingTemplate = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var banner: some View {
        if let error = store.error {
            Button { store.error = nil } label: {
                Text(verbatim: error)
                    .darsType(.footnote)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(DarsColor.danger, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.horizontal, 16)
            .transition(.opacity)
        } else if weekDone {
            Label("The week is set", systemImage: "checkmark.circle.fill")
                .darsType(.subheadline)
                .foregroundStyle(DarsColor.onAccent)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(DarsColor.accent, in: Capsule())
                .padding(.top, 6)
                .transition(.opacity)
        }
    }

    private func isToday(_ day: String) -> Bool { TodayStore.todayKey() == day }
}

struct BellEditSheet: View {
    let bell: TimetableBell
    let isLast: Bool
    let onSave: (String, String, String?, Bool) -> Void
    let onInsert: (Bool) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var label: String
    @State private var moveLater = true

    init(bell: TimetableBell, isLast: Bool, onSave: @escaping (String, String, String?, Bool) -> Void, onInsert: @escaping (Bool) -> Void, onDelete: @escaping () -> Void) {
        self.bell = bell
        self.isLast = isLast
        self.onSave = onSave
        self.onInsert = onInsert
        self.onDelete = onDelete
        _start = State(initialValue: Clock.date(bell.start))
        _end = State(initialValue: Clock.date(bell.end))
        _label = State(initialValue: bell.label ?? "")
    }

    private var valid: Bool { Clock.minutes(Clock.string(end)) > Clock.minutes(Clock.string(start)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    if !valid {
                        Text("It has to end after it starts").darsType(.footnote).foregroundStyle(DarsColor.danger)
                    }
                }
                .environment(\.locale, Locale(identifier: "en_GB"))
                if bell.isBreak {
                    Section { TextField("Name", text: $label) }
                }
                if !isLast {
                    Section { Toggle("Move the later bells with it", isOn: $moveLater) }
                }
                Section {
                    Button("Add a period after this", systemImage: "plus") { dismiss(); onInsert(false) }
                    Button("Add a break after this", systemImage: "cup.and.saucer") { dismiss(); onInsert(true) }
                }
                Section {
                    Button(bell.isBreak ? "Delete this break" : "Delete this period", systemImage: "trash", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle(bell.isBreak ? Text("Break") : Text("Period \(bell.period)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = label.trimmingCharacters(in: .whitespaces)
                        onSave(Clock.string(start), Clock.string(end), bell.isBreak ? (name.isEmpty ? nil : name) : nil, moveLater && !isLast)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct BellsListSheet: View {
    let bells: [TimetableBell]
    let onEdit: (TimetableBell) -> Void
    let onTemplate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(bells) { bell in
                        Button { onEdit(bell) } label: {
                            HStack {
                                (bell.isBreak ? Text(verbatim: breakTitle(bell)) : Text("Period \(bell.period)"))
                                    .foregroundStyle(bell.isBreak ? DarsColor.labelSecondary : DarsColor.labelPrimary)
                                Spacer()
                                Text(verbatim: "\(bell.start)–\(bell.end)").monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
                            }
                        }
                    }
                } footer: {
                    Text("Tap a time to change it")
                }
                Section {
                    Button("Start again from a template", systemImage: "wand.and.stars") { onTemplate() }
                }
            }
            .navigationTitle(Text("Bells"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func breakTitle(_ bell: TimetableBell) -> String {
        let label = (bell.label ?? "").trimmingCharacters(in: .whitespaces)
        if label.isEmpty || label == "Break" { return language.language.isKurdish ? "پشوو" : "Break" }
        return label
    }
}

struct BellTemplateSheet: View {
    @State var template: BellTemplate
    let onSave: (BellTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("First lesson starts", selection: $template.start, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                    Stepper(value: $template.periodMinutes, in: 20...90, step: 5) {
                        Text("Each lesson: \(template.periodMinutes) min")
                    }
                    Stepper(value: $template.periods, in: 1...10) {
                        Text("Lessons a day: \(template.periods)")
                    }
                    Stepper(value: $template.breakMinutes, in: 5...60, step: 5) {
                        Text("Each break: \(template.breakMinutes) min")
                    }
                }
                Section {
                    ForEach(1..<max(template.periods, 2), id: \.self) { p in
                        Toggle(isOn: Binding(
                            get: { template.breaksAfter.contains(p) },
                            set: { on in if on { template.breaksAfter.insert(p) } else { template.breaksAfter.remove(p) } }
                        )) {
                            Text("Break after lesson \(p)")
                        }
                    }
                } header: {
                    Text("Breaks")
                }
                Section {
                    ForEach(template.bells()) { bell in
                        HStack {
                            (bell.isBreak ? Text("Break") : Text("Period \(bell.period)"))
                                .foregroundStyle(bell.isBreak ? DarsColor.labelSecondary : DarsColor.labelPrimary)
                            Spacer()
                            Text(verbatim: "\(bell.start)–\(bell.end)").monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
                        }
                    }
                } header: {
                    Text("The day")
                } footer: {
                    Text("Every class uses these bells. Lessons already set keep their period number.")
                }
            }
            .navigationTitle(Text("Bells"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(template); dismiss() } }
            }
        }
    }
}

struct TimetableDetailsSheet: View {
    let title: String
    let item: TimetableItem
    let teachers: [TeacherChoice]
    let rooms: [String]
    let onSave: (UUID?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var teacherId: UUID?
    @State private var room: String
    @State private var showAll = false

    init(title: String, item: TimetableItem, teachers: [TeacherChoice], rooms: [String], onSave: @escaping (UUID?, String?) -> Void) {
        self.title = title
        self.item = item
        self.teachers = teachers
        self.rooms = rooms
        self.onSave = onSave
        _teacherId = State(initialValue: item.teacherId)
        _room = State(initialValue: item.room ?? "")
    }

    private var matching: [TeacherChoice] {
        teachers.filter { ($0.subject ?? "").caseInsensitiveCompare(item.subject ?? "") == .orderedSame }
    }

    private var shown: [TeacherChoice] {
        if showAll || matching.isEmpty { return teachers }
        var list = matching
        if let chosen = teachers.first(where: { $0.id == teacherId }), !list.contains(chosen) { list.insert(chosen, at: 0) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { teacherId = nil } label: {
                        HStack {
                            Text("No teacher").foregroundStyle(DarsColor.labelPrimary)
                            Spacer()
                            if teacherId == nil { Image(systemName: "checkmark").foregroundStyle(DarsColor.accentLabel) }
                        }
                    }
                    ForEach(shown) { t in
                        Button { teacherId = t.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: t.name).foregroundStyle(DarsColor.labelPrimary)
                                    if let s = t.subject, !s.isEmpty {
                                        Text(verbatim: SubjectName.label(s, kurdish: language.language.isKurdish)).darsType(.caption).foregroundStyle(DarsColor.labelSecondary)
                                    }
                                }
                                Spacer()
                                if teacherId == t.id { Image(systemName: "checkmark").foregroundStyle(DarsColor.accentLabel) }
                            }
                        }
                    }
                    if !matching.isEmpty && matching.count < teachers.count {
                        Button(showAll ? "Only this subject's teachers" : "Show every teacher") { showAll.toggle() }
                    }
                } header: {
                    Text("Teacher")
                }
                Section {
                    TextField("Room", text: $room)
                    if !rooms.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(rooms, id: \.self) { r in
                                    Button { room = r } label: {
                                        Text(verbatim: r)
                                            .darsType(.subheadline)
                                            .foregroundStyle(room == r ? DarsColor.onAccent : DarsColor.labelPrimary)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(room == r ? DarsColor.accent : DarsColor.surfaceGrouped, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Room")
                }
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let r = room.trimmingCharacters(in: .whitespaces)
                        onSave(teacherId, r.isEmpty ? nil : r)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CustomSubjectSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle(Text("Other"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(220)])
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        onSave(n)
        dismiss()
    }
}

struct CopyWeekSheet: View {
    let classes: [ClassRow]
    let from: String
    let onCopy: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var target: ClassRow?

    var body: some View {
        NavigationStack {
            List(classes) { c in
                Button { target = c } label: {
                    HStack {
                        Text(verbatim: c.label).foregroundStyle(DarsColor.labelPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                    }
                }
            }
            .navigationTitle(Text("Copy \(from)'s week to"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert(item: $target) { c in
                Alert(
                    title: Text("Copy to \(c.label)?"),
                    message: Text("\(c.label)'s week becomes the same as \(from)'s."),
                    primaryButton: .default(Text("Copy")) { onCopy(c.id); dismiss() },
                    secondaryButton: .cancel()
                )
            }
        }
        .presentationDetents([.medium, .large])
    }
}
