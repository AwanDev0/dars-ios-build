import Foundation
import Observation
import SwiftUI
import Supabase

struct SchoolInfoView: View {
    let me: Profile
    @State private var school: SchoolRow?
    @State private var loading = true
    @State private var working = false
    @State private var saved = false
    @State private var error: String?
    @State private var name = ""
    @State private var nameKu = ""
    @State private var owner = ""
    @State private var ownerTitle = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""

    struct Patch: Encodable {
        let name: String; let name_ku: String?; let owner_name: String?; let owner_title: String?
        let address: String?; let phone: String?; let email: String?; let website: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    SectionLabel("Name")
                    DarsField(title: "School name", text: $name)
                    DarsField(title: "Name in Kurdish", text: $nameKu)
                    SectionLabel("Who signs")
                    DarsField(title: "Owner or principal", text: $owner)
                    DarsField(title: "Their title", text: $ownerTitle)
                    SectionLabel("Where and how to reach it")
                    DarsField(title: "Address", text: $address)
                    DarsField(title: "Phone", text: $phone, keyboard: .phonePad)
                    DarsField(title: "Email", text: $email, keyboard: .emailAddress, capitalization: .never)
                    DarsField(title: "Website", text: $website, keyboard: .URL, capitalization: .never)
                    if let code = school?.code {
                        SectionLabel("School code")
                        Text(code).font(.system(size: 20, weight: .bold, design: .rounded)).kerning(2).foregroundStyle(DarsColor.accentLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Metrics.Space.md).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    DarsButton(title: saved ? "Saved" : "Save", kind: .primary, systemImage: saved ? "checkmark" : "tray.and.arrow.down", isLoading: working, fullWidth: true) {
                        Task { await save() }
                    }
                    Text("The name and the signature here are what appear on a printed report card.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("School details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            school = try? await DarsData.school(me.schoolId)
            name = school?.name ?? ""; nameKu = school?.nameKu ?? ""
            owner = school?.ownerName ?? ""; ownerTitle = school?.ownerTitle ?? ""
            address = school?.address ?? ""; phone = school?.phone ?? ""
            email = school?.email ?? ""; website = school?.website ?? ""
            loading = false
        }
    }

    private func save() async {
        guard let id = me.schoolId else { return }
        working = true
        defer { working = false }
        func blank(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.trimmingCharacters(in: .whitespaces) }
        do {
            try await SupabaseService.client.from("schools").update(
                Patch(name: name.trimmingCharacters(in: .whitespaces), name_ku: blank(nameKu), owner_name: blank(owner), owner_title: blank(ownerTitle),
                      address: blank(address), phone: blank(phone), email: blank(email), website: blank(website))
            ).eq("id", value: id).execute()
            saved = true
            HapticEngine.play(.success)
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }
}

@MainActor
@Observable
final class SchoolYearStore {
    struct Settings: Codable, Sendable {
        let schoolYear: String?
        let semester: String?
        let attendanceAnyDay: Bool?
        let terms: [Term]?
        let daysOff: [DayOff]?
        enum CodingKeys: String, CodingKey {
            case terms, semester
            case schoolYear = "school_year"; case attendanceAnyDay = "attendance_any_day"; case daysOff = "days_off"
        }
    }
    struct Term: Codable, Sendable, Hashable { let semester: String?; let startsOn: String?; let endsOn: String?
        enum CodingKeys: String, CodingKey { case semester; case startsOn = "starts_on"; case endsOn = "ends_on" } }
    struct DayOff: Codable, Identifiable, Sendable, Hashable { let id: UUID; let date: String; let kind: String?; let reason: String?; let reasonKu: String?
        enum CodingKeys: String, CodingKey { case id, date, kind, reason; case reasonKu = "reason_ku" } }

    private(set) var settings: Settings?
    private(set) var loading = true
    private(set) var working = false
    private(set) var error: String?
    private let client = SupabaseService.client

    struct YearArgs: Encodable { let p_school: UUID; let p_year: String; let p_semester: String; let p_s1_start: String?; let p_s1_end: String?; let p_s2_start: String?; let p_s2_end: String? }
    struct AnyDayArgs: Encodable { let p_school: UUID; let p_on: Bool }
    struct DayOffArgs: Encodable { let p_school: UUID; let p_date: String; let p_kind: String; let p_reason: String?; let p_reason_ku: String? }

    func load(_ school: UUID) async {
        do {
            let s: Settings = try await client.rpc("school_year_settings", params: ["p_school": school.uuidString]).execute().value
            settings = s
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func setYear(_ school: UUID, year: String, semester: String) async {
        let t1 = settings?.terms?.first { $0.semester == "1" }
        let t2 = settings?.terms?.first { $0.semester == "2" }
        await run(school) {
            try await client.rpc("admin_set_year", params: YearArgs(p_school: school, p_year: year, p_semester: semester,
                                                                   p_s1_start: t1?.startsOn, p_s1_end: t1?.endsOn,
                                                                   p_s2_start: t2?.startsOn, p_s2_end: t2?.endsOn)).execute()
        }
    }

    func setAnyDay(_ school: UUID, _ on: Bool) async {
        await run(school) { try await client.rpc("admin_set_attendance_any_day", params: AnyDayArgs(p_school: school, p_on: on)).execute() }
    }

    func addDayOff(_ school: UUID, date: Date, kind: String, reason: String) async {
        await run(school) {
            try await client.rpc("admin_add_day_off", params: DayOffArgs(p_school: school, p_date: DayKey.string(date), p_kind: kind,
                                                                         p_reason: reason.isEmpty ? nil : reason, p_reason_ku: nil)).execute()
        }
    }

    func removeDayOff(_ school: UUID, _ id: UUID) async {
        await run(school) { try await client.rpc("admin_remove_day_off", params: ["p_id": id.uuidString]).execute() }
    }

    private func run(_ school: UUID, _ job: () async throws -> Void) async {
        working = true
        error = nil
        defer { working = false }
        do { try await job(); HapticEngine.play(.success); await load(school) }
        catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }
}

struct SchoolYearView: View {
    let me: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = SchoolYearStore()
    @State private var adding = false
    @State private var year = ""
    @State private var semester = "1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("This year")
                        DarsField(title: "School year", text: $year)
                        Picker("Semester", selection: $semester) { Text("Semester 1").tag("1"); Text("Semester 2").tag("2") }
                            .pickerStyle(.segmented)
                        DarsButton(title: "Save the year", kind: .primary, systemImage: "checkmark", isLoading: store.working, fullWidth: true) {
                            if let s = me.schoolId { Task { await store.setYear(s, year: year, semester: semester) } }
                        }
                        Text("The semester here is the one every report card and gradebook opens on.")
                            .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Registers")
                        Toggle(isOn: Binding(get: { store.settings?.attendanceAnyDay ?? false }, set: { on in
                            if let s = me.schoolId { Task { await store.setAnyDay(s, on) } }
                        })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Allow marking on any day").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                Text("Off: a teacher may only take today's register").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                            }
                        }
                        .tint(DarsColor.accent)
                        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Days off", trailing: "\(store.settings?.daysOff?.count ?? 0)")
                        if (store.settings?.daysOff ?? []).isEmpty {
                            EmptyCard("No closures set. Every school day is open.")
                        } else {
                            CardList {
                                ForEach(Array((store.settings?.daysOff ?? []).enumerated()), id: \.element.id) { i, d in
                                    if i > 0 { RowDivider(inset: Metrics.Space.md) }
                                    HStack(spacing: 12) {
                                        Image(systemName: d.kind == "holiday" ? "sun.max.fill" : "cloud.rain.fill").foregroundStyle(DarsColor.warning).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(DayKey.date(d.date)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? d.date).darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
                                            Text((language.language.isKurdish ? (d.reasonKu ?? d.reason) : d.reason) ?? (d.kind ?? "Closed")).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                        }
                                        Spacer()
                                        Button { if let s = me.schoolId { Task { await store.removeDayOff(s, d.id) } } } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(DarsColor.danger)
                                        }
                                    }
                                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                                }
                            }
                        }
                        Button { HapticEngine.play(.selection); adding = true } label: {
                            CardList { LinkRow(title: "Add a day off", symbol: "calendar.badge.plus", tint: DarsColor.warning) }
                        }
                        .buttonStyle(.plain)
                        Text("A closed day turns every register off and tells the app to skip it when it says \"tomorrow\".")
                            .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    }
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Year & days off")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let s = me.schoolId else { return }
            await store.load(s)
            year = store.settings?.schoolYear ?? SchoolYear.current()
            semester = store.settings?.semester ?? "1"
        }
        .sheet(isPresented: $adding) {
            DayOffSheet { date, kind, reason in
                if let s = me.schoolId { Task { await store.addDayOff(s, date: date, kind: kind, reason: reason) } }
            }
        }
    }
}

struct DayOffSheet: View {
    let onAdd: (Date, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var kind = "holiday"
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                DatePicker("Day", selection: $date, displayedComponents: .date)
                    .padding(.horizontal, 14).frame(height: 50)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Picker("Kind", selection: $kind) {
                    Text("Holiday").tag("holiday"); Text("Closed").tag("closure"); Text("Exam day").tag("exam")
                }
                .pickerStyle(.segmented)
                DarsField(title: "Reason", text: $reason)
                Spacer()
                DarsButton(title: "Add", kind: .primary, systemImage: "plus", fullWidth: true) { onAdd(date, kind, reason.trimmingCharacters(in: .whitespaces)); dismiss() }
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Day off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct NewTeacherView: View {
    let me: Profile
    @State private var name = ""
    @State private var nameKu = ""
    @State private var subject = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var password = ResetPasswordSheet.suggestion()
    @State private var chosen: Set<UUID> = []
    @State private var classes: [ClassRow] = []
    @State private var working = false
    @State private var createdLogin: String?
    @State private var error: String?

    struct Request: Encodable {
        let full_name: String; let full_name_ku: String?; let email: String?
        let password: String; let subject: String; let phone: String?; let classes: [String]
    }
    struct Reply: Decodable { let ok: Bool?; let email: String?; let error: String? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if let login = createdLogin {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Teacher added", systemImage: "checkmark.circle.fill").foregroundStyle(DarsColor.success).darsType(.headline)
                        Text("Give them these, out loud. They change the password in Profile.").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(login).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(DarsColor.labelPrimary).textSelection(.enabled)
                            Text(password).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(DarsColor.accentLabel).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metrics.Space.md).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button { UIPasteboard.general.string = "\(login)\n\(password)"; HapticEngine.play(.success) } label: {
                            Label("Copy both", systemImage: "doc.on.doc").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(Metrics.Space.md).background(DarsColor.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    SectionLabel("Who they are")
                    DarsField(title: "Full name", text: $name)
                    DarsField(title: "Name in Kurdish", text: $nameKu)
                    DarsField(title: "Subject", text: $subject)
                    SectionLabel("How they sign in")
                    DarsField(title: "Phone", text: $phone, keyboard: .phonePad)
                    DarsField(title: "Email (optional)", text: $email, keyboard: .emailAddress, capitalization: .never)
                    HStack(spacing: 8) {
                        DarsField(title: "Password", text: $password, capitalization: .never)
                        Button { password = ResetPasswordSheet.suggestion(); HapticEngine.play(.selection) } label: {
                            Image(systemName: "die.face.5").font(.system(size: 17)).frame(width: 50, height: 50).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("With a phone and no email the app makes them a login from the number. Either way they sign in with what you give them here.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    SectionLabel("Classes they take", trailing: "\(chosen.count)")
                    CardList {
                        ForEach(Array(classes.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { RowDivider(inset: Metrics.Space.md) }
                            Button {
                                HapticEngine.play(.selection)
                                if chosen.contains(c.id) { chosen.remove(c.id) } else { chosen.insert(c.id) }
                            } label: {
                                HStack {
                                    Text(c.label).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                    Text(c.name ?? "").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                    Spacer()
                                    Image(systemName: chosen.contains(c.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen.contains(c.id) ? DarsColor.accent : DarsColor.labelTertiary)
                                }
                                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    DarsButton(title: "Create the teacher", kind: .primary, systemImage: "person.badge.plus", isLoading: working, fullWidth: true) { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || subject.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 6)
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
            .animation(Motion.arrive, value: createdLogin)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Add a teacher")
        .navigationBarTitleDisplayMode(.inline)
        .task { classes = (try? await DarsData.allClasses()) ?? [] }
    }

    private func create() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let reply: Reply = try await SupabaseService.client.functions.invoke("teacher-signup", options: FunctionInvokeOptions(body:
                Request(full_name: name.trimmingCharacters(in: .whitespaces),
                        full_name_ku: nameKu.trimmingCharacters(in: .whitespaces).isEmpty ? nil : nameKu.trimmingCharacters(in: .whitespaces),
                        email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
                        password: password,
                        subject: subject.trimmingCharacters(in: .whitespaces),
                        phone: phone.filter(\.isNumber).isEmpty ? nil : phone.filter(\.isNumber),
                        classes: chosen.map { $0.uuidString })))
            if reply.ok == true {
                createdLogin = reply.email ?? email
                HapticEngine.play(.success)
            } else {
                error = reply.error ?? "Couldn't create the account."
                HapticEngine.play(.error)
            }
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }
}
