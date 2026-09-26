import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class AdminScheduleStore {
    struct Bell: Identifiable, Hashable {
        var slot: Int
        var start: String
        var end: String
        var isBreak: Bool
        var label: String?
        var id: Int { slot }
    }

    private(set) var bells: [Bell] = []
    private(set) var classes: [ClassRow] = []
    private(set) var teachers: [Profile] = []
    private(set) var week: [String: [ScheduleItem]] = [:]
    private(set) var loading = true
    private(set) var working = false
    private(set) var error: String?
    var classId: UUID?
    var day = ScheduleStore.schoolDay(TodayStore.todayKey())
    private let client = SupabaseService.client

    struct BellRow: Codable { let sort_order: Int; let start_time: String; let end_time: String; let is_break: Bool; let label: String? }
    struct BellPayload: Encodable { let start: String; let end: String; let is_break: Bool; let label: String? }
    struct BellsArgs: Encodable { let p_bells: [BellPayload] }
    struct SlotArgs: Encodable { let p_class: UUID; let p_day: String; let p_slot: Int; let p_subject: String; let p_teacher: UUID?; let p_room: String? }
    struct ClearArgs: Encodable { let p_class: UUID; let p_day: String; let p_slot: Int }
    struct CopyDayArgs: Encodable { let p_class: UUID; let p_from: String; let p_to: [String] }
    struct CopyClassArgs: Encodable { let p_from: UUID; let p_to: UUID }

    func load(preselected: UUID?) async {
        do {
            classes = try await DarsData.allClasses()
            classId = preselected ?? classId ?? classes.first?.id
            let people: [Profile] = try await client.from("profiles").select(Profile.columns).eq("role", value: "teacher").order("full_name").execute().value
            teachers = people
            await loadBells()
            await loadWeek()
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func loadBells() async {
        do {
            let rows: [BellRow] = try await client.from("school_bells").select("sort_order, start_time, end_time, is_break, label").order("sort_order").execute().value
            bells = rows.map { Bell(slot: $0.sort_order, start: String($0.start_time.prefix(5)), end: String($0.end_time.prefix(5)), isBreak: $0.is_break, label: $0.label) }
        } catch { bells = [] }
    }

    func loadWeek() async {
        guard let classId else { week = [:]; return }
        do {
            let rows: [ScheduleItem] = try await client.from("schedule_items").select(ScheduleItem.columns).eq("class_id", value: classId).order("sort_order").execute().value
            week = Dictionary(grouping: rows, by: { $0.dayOfWeek ?? "" })
        } catch { week = [:] }
    }

    func saveBells(_ draft: [Bell]) async {
        await write("Bells saved") {
            try await client.rpc("admin_set_bells", params: BellsArgs(p_bells: draft.map { BellPayload(start: $0.start, end: $0.end, is_break: $0.isBreak, label: $0.label) })).execute()
        }
        await loadBells()
        await loadWeek()
    }

    func setSlot(_ slot: Int, subject: String, teacher: UUID?, room: String?) async {
        guard let classId else { return }
        await write("Saved") {
            try await client.rpc("admin_set_slot", params: SlotArgs(p_class: classId, p_day: day, p_slot: slot, p_subject: subject, p_teacher: teacher, p_room: room?.isEmpty == true ? nil : room)).execute()
        }
        await loadWeek()
    }

    func clearSlot(_ slot: Int) async {
        guard let classId else { return }
        await write("Cleared") {
            try await client.rpc("admin_clear_slot", params: ClearArgs(p_class: classId, p_day: day, p_slot: slot)).execute()
        }
        await loadWeek()
    }

    func copyDay(to days: [String]) async {
        guard let classId, !days.isEmpty else { return }
        await write("Day copied") {
            try await client.rpc("admin_copy_day", params: CopyDayArgs(p_class: classId, p_from: day, p_to: days)).execute()
        }
        await loadWeek()
    }

    func copyClass(from other: UUID) async {
        guard let classId else { return }
        await write("Class copied") {
            try await client.rpc("admin_copy_class", params: CopyClassArgs(p_from: other, p_to: classId)).execute()
        }
        await loadWeek()
    }

    private func write(_ what: String, _ job: () async throws -> Void) async {
        working = true
        error = nil
        defer { working = false }
        do { try await job(); HapticEngine.play(.success) }
        catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }

    func slots() -> [(Bell, ScheduleItem?)] {
        let today = week[day] ?? []
        return bells.map { b in (b, today.first { $0.sortOrder == b.slot && !$0.isBreak }) }
    }
    var filled: Int { (week[day] ?? []).filter { !$0.isBreak && !($0.subject ?? "").isEmpty }.count }
    var lessonSlots: Int { bells.filter { !$0.isBreak }.count }
}

struct AdminScheduleView: View {
    let me: Profile
    var preselected: UUID?
    @Environment(LanguageStore.self) private var language
    @State private var store = AdminScheduleStore()
    @State private var editing: AdminScheduleStore.Bell?
    @State private var editingBells = false
    @State private var copyingDay = false
    @State private var copyingClass = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.classes.count > 1 {
                    ChipRow(items: store.classes.map { ($0.id as UUID?, $0.label) }, selected: Binding(get: { store.classId }, set: { v in
                        store.classId = v; Task { await store.loadWeek() }
                    }))
                }
                WeekPicker(day: Binding(get: { store.day }, set: { store.day = $0 }))

                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.bells.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The school has no bells yet").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text("Set the times of the day once — period, break, period — and every class is filled in against them.")
                            .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                        DarsButton(title: "Set the bells", kind: .primary, systemImage: "bell.fill", fullWidth: true) { editingBells = true }
                    }
                    .padding(Metrics.Space.md).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    HStack {
                        Text("\(store.filled) of \(store.lessonSlots) filled").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                        Spacer()
                        Button { HapticEngine.play(.selection); editingBells = true } label: { Label("Bells", systemImage: "bell").font(.system(size: 13, weight: .semibold)) }
                    }
                    VStack(spacing: 6) {
                        ForEach(store.slots(), id: \.0.id) { bell, item in slotRow(bell, item) }
                    }
                    HStack(spacing: 8) {
                        Button { HapticEngine.play(.selection); copyingDay = true } label: {
                            Label("Copy this day", systemImage: "doc.on.doc").font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 42).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button { HapticEngine.play(.selection); copyingClass = true } label: {
                            Label("Copy a class", systemImage: "square.on.square").font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 42).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("A break is a bell, not a lesson — set it once in Bells and it shows in every class.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Timetable")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(preselected: preselected) }
        .sheet(item: $editing) { bell in
            SlotSheet(bell: bell, item: (store.week[store.day] ?? []).first { $0.sortOrder == bell.slot && !$0.isBreak }, teachers: store.teachers,
                      onSave: { subject, teacher, room in Task { await store.setSlot(bell.slot, subject: subject, teacher: teacher, room: room) } },
                      onClear: { Task { await store.clearSlot(bell.slot) } })
        }
        .sheet(isPresented: $editingBells) {
            BellsSheet(bells: store.bells) { draft in Task { await store.saveBells(draft) } }
        }
        .sheet(isPresented: $copyingDay) {
            CopyDaySheet(from: store.day) { days in Task { await store.copyDay(to: days) } }
        }
        .sheet(isPresented: $copyingClass) {
            CopyClassSheet(classes: store.classes.filter { $0.id != store.classId }) { from in Task { await store.copyClass(from: from) } }
        }
    }

    private func slotRow(_ bell: AdminScheduleStore.Bell, _ item: ScheduleItem?) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(bell.start).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(bell.isBreak ? DarsColor.labelTertiary : DarsColor.labelPrimary)
                Text(bell.end).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(DarsColor.labelTertiary)
            }
            .frame(width: 48, alignment: .leading)
            if bell.isBreak {
                Text(bell.label.map { LocalizedStringKey($0) } ?? "Break").darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(DarsColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Button {
                    HapticEngine.play(.selection)
                    editing = bell
                } label: {
                    HStack(spacing: 0) {
                        Rectangle().fill(item == nil ? DarsColor.separator : SubjectColor.of(item?.subject)).frame(width: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item?.subject ?? "Empty").darsType(.headline).foregroundStyle(item == nil ? DarsColor.labelTertiary : DarsColor.labelPrimary)
                            if let item {
                                Text([item.teacher, item.room].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                            } else {
                                Text("Tap to set the lesson").darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        Spacer(minLength: 0)
                        Image(systemName: item == nil ? "plus.circle" : "pencil").font(.system(size: 14)).foregroundStyle(DarsColor.labelTertiary).padding(.trailing, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SlotSheet: View {
    let bell: AdminScheduleStore.Bell
    let item: ScheduleItem?
    let teachers: [Profile]
    let onSave: (String, UUID?, String?) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var subject = ""
    @State private var room = ""
    @State private var teacher: UUID?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("\(bell.start) – \(bell.end)").darsType(.headline).foregroundStyle(DarsColor.accentLabel)
                DarsField(title: "Subject", text: $subject)
                Menu {
                    Button("No teacher") { teacher = nil }
                    ForEach(teachers) { t in
                        Button(t.displayName(kurdish: language.language.isKurdish)) { teacher = t.id }
                    }
                } label: {
                    HStack {
                        Text("Teacher").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                        Spacer()
                        Text(teacher.flatMap { id in teachers.first { $0.id == id }?.displayName(kurdish: language.language.isKurdish) } ?? "Not set")
                            .darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(DarsColor.labelTertiary)
                    }
                    .padding(.horizontal, 14).frame(height: 50)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                DarsField(title: "Room", text: $room)
                Text("The teacher named here is the one whose own timetable this lesson appears on, and who may take this class's register.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                Spacer()
                DarsButton(title: "Save the lesson", kind: .primary, systemImage: "checkmark", fullWidth: true) {
                    onSave(subject.trimmingCharacters(in: .whitespaces), teacher, room.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty)
                if item != nil {
                    Button(role: .destructive) { onClear(); dismiss() } label: {
                        Text("Clear this slot").darsType(.headline).foregroundStyle(DarsColor.danger).frame(maxWidth: .infinity).frame(height: 48)
                            .background(DarsColor.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Period \(bell.slot)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                subject = item?.subject ?? ""
                room = item?.room ?? ""
                teacher = teachers.first { $0.displayName(kurdish: false) == item?.teacher || $0.fullName == item?.teacher }?.id
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct BellsSheet: View {
    @State var bells: [AdminScheduleStore.Bell]
    let onSave: ([AdminScheduleStore.Bell]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($bells) { $b in
                        HStack(spacing: 8) {
                            Image(systemName: b.isBreak ? "cup.and.saucer.fill" : "book.fill").font(.system(size: 13)).foregroundStyle(b.isBreak ? DarsColor.labelTertiary : DarsColor.accentLabel).frame(width: 22)
                            TextField("08:00", text: $b.start).frame(width: 62).monospacedDigit()
                            Text("–").foregroundStyle(DarsColor.labelTertiary)
                            TextField("08:45", text: $b.end).frame(width: 62).monospacedDigit()
                            Spacer()
                            Toggle("", isOn: $b.isBreak).labelsHidden().tint(DarsColor.accent)
                        }
                    }
                    .onDelete { bells.remove(atOffsets: $0); renumber() }
                    .onMove { bells.move(fromOffsets: $0, toOffset: $1); renumber() }
                } header: {
                    Text("Period · times · is it a break")
                } footer: {
                    Text("Times are 24-hour, HH:mm. Changing a bell re-times that period in every class at once.")
                }
                Section {
                    Button {
                        let last = bells.last
                        bells.append(.init(slot: (bells.map { $0.slot }.max() ?? 0) + 1, start: last?.end ?? "08:00", end: "", isBreak: false, label: nil))
                    } label: { Label("Add a period", systemImage: "plus") }
                }
            }
            .navigationTitle("Bells")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(clean()); dismiss() }.disabled(clean().isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }

    private func renumber() {
        for i in bells.indices { bells[i].slot = i + 1 }
    }
    private func clean() -> [AdminScheduleStore.Bell] {
        bells.filter { $0.start.count == 5 && $0.end.count == 5 }
    }
}

struct CopyDaySheet: View {
    let from: String
    let onCopy: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("Copy \(dayName(from))'s lessons onto other days. What is already on those days is replaced.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                CardList {
                    ForEach(ScheduleStore.days.filter { $0 != from }, id: \.self) { d in
                        Button {
                            HapticEngine.play(.selection)
                            if chosen.contains(d) { chosen.remove(d) } else { chosen.insert(d) }
                        } label: {
                            HStack {
                                Text(dayName(d)).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                Spacer()
                                Image(systemName: chosen.contains(d) ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen.contains(d) ? DarsColor.accent : DarsColor.labelTertiary)
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                DarsButton(title: "Copy", kind: .primary, systemImage: "doc.on.doc", fullWidth: true) { onCopy(Array(chosen)); dismiss() }
                    .disabled(chosen.isEmpty)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Copy the day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct CopyClassSheet: View {
    let classes: [ClassRow]
    let onCopy: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: UUID?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("Take another class's whole week and put it on this one. Everything here is replaced.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                ScrollView {
                    CardList {
                        ForEach(Array(classes.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { RowDivider(inset: Metrics.Space.md) }
                            Button { HapticEngine.play(.selection); chosen = c.id } label: {
                                HStack {
                                    Text(c.label).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                    Spacer()
                                    if chosen == c.id { Image(systemName: "checkmark").foregroundStyle(DarsColor.accentLabel) }
                                }
                                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DarsButton(title: "Copy onto this class", kind: .primary, systemImage: "square.on.square", fullWidth: true) {
                    if let chosen { onCopy(chosen) }; dismiss()
                }
                .disabled(chosen == nil)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Copy a class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
