import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class StudentRecordStore {
    struct Record: Codable, Sendable {
        var studentId: UUID
        var dateOfBirth: String?
        var birthCity: String?
        var nationality: String?
        var gender: String?
        var bloodType: String?
        var guardianName: String?
        var guardianRelation: String?
        var guardianPhone: String?
        var fatherJob: String?
        var motherJob: String?
        var siblingsCount: Int?
        var siblingsInSchool: Int?
        var economicBand: String?
        var homeCity: String?
        var neighbourhood: String?
        var street: String?
        var homePhone: String?
        var allergies: String?
        var chronicCondition: String?
        var medication: String?
        var doctorPhone: String?
        var emergencyName: String?
        var emergencyRelation: String?
        var emergencyPhone: String?
        var previousSchool: String?
        var yearJoined: String?
        var transport: String?

        static let columns = """
            student_id, date_of_birth, birth_city, nationality, gender, blood_type, \
            guardian_name, guardian_relation, guardian_phone, father_job, mother_job, \
            siblings_count, siblings_in_school, economic_band, home_city, neighbourhood, \
            street, home_phone, allergies, chronic_condition, medication, doctor_phone, \
            emergency_name, emergency_relation, emergency_phone, previous_school, year_joined, transport
            """

        enum CodingKeys: String, CodingKey {
            case gender, nationality, allergies, medication, transport, street, neighbourhood
            case studentId = "student_id"; case dateOfBirth = "date_of_birth"; case birthCity = "birth_city"
            case bloodType = "blood_type"; case guardianName = "guardian_name"; case guardianRelation = "guardian_relation"
            case guardianPhone = "guardian_phone"; case fatherJob = "father_job"; case motherJob = "mother_job"
            case siblingsCount = "siblings_count"; case siblingsInSchool = "siblings_in_school"
            case economicBand = "economic_band"; case homeCity = "home_city"; case homePhone = "home_phone"
            case chronicCondition = "chronic_condition"; case doctorPhone = "doctor_phone"
            case emergencyName = "emergency_name"; case emergencyRelation = "emergency_relation"
            case emergencyPhone = "emergency_phone"; case previousSchool = "previous_school"; case yearJoined = "year_joined"
        }
    }

    var record: Record
    private(set) var loading = true
    private(set) var working = false
    private(set) var saved = false
    private(set) var error: String?
    private let client = SupabaseService.client

    init(student: UUID) { record = Record(studentId: student) }

    func load() async {
        do {
            let rows: [Record] = try await client.from("student_records").select(Record.columns).eq("student_id", value: record.studentId).execute().value
            if let r = rows.first { record = r }
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func bind(_ key: WritableKeyPath<Record, String?>) -> Binding<String> {
        Binding(get: { self.record[keyPath: key] ?? "" },
                set: { self.record[keyPath: key] = $0.isEmpty ? nil : $0; self.saved = false })
    }

    func save() async {
        working = true
        defer { working = false }
        do {
            try await client.from("student_records").upsert(record, onConflict: "student_id").execute()
            saved = true
            HapticEngine.play(.success)
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }
}

struct StudentRecordView: View {
    let student: Profile
    var editable: Bool = true
    @Environment(LanguageStore.self) private var language
    @State private var store: StudentRecordStore

    init(student: Profile, editable: Bool = true) {
        self.student = student
        self.editable = editable
        _store = State(initialValue: StudentRecordStore(student: student.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    group("Health", "A nurse or a teacher has to find these in seconds.") {
                        field("Allergies", \.allergies)
                        field("Long-term condition", \.chronicCondition)
                        field("Medication", \.medication)
                        phone("Doctor", \.doctorPhone)
                    }
                    group("In an emergency", nil) {
                        field("Who to call", \.emergencyName)
                        field("Relation", \.emergencyRelation)
                        phone("Their number", \.emergencyPhone)
                    }
                    group("Born", nil) {
                        field("Date of birth", \.dateOfBirth, placeholder: "yyyy-mm-dd")
                        field("City of birth", \.birthCity)
                        field("Nationality", \.nationality)
                        field("Blood type", \.bloodType)
                        field("Gender", \.gender)
                    }
                    group("Guardian", nil) {
                        field("Name", \.guardianName)
                        field("Relation", \.guardianRelation)
                        phone("Phone", \.guardianPhone)
                    }
                    group("Home", nil) {
                        field("City", \.homeCity)
                        field("Neighbourhood", \.neighbourhood)
                        field("Street", \.street)
                        phone("Home phone", \.homePhone)
                        field("How they get here", \.transport)
                    }
                    group("Family", nil) {
                        field("Father's work", \.fatherJob)
                        field("Mother's work", \.motherJob)
                        number("Brothers and sisters", \.siblingsCount)
                        number("Of those, at this school", \.siblingsInSchool)
                    }
                    group("Before this school", nil) {
                        field("Previous school", \.previousSchool)
                        field("Year they joined", \.yearJoined)
                    }
                    if editable {
                        DarsButton(title: store.saved ? "Saved" : "Save the record", kind: .primary,
                                   systemImage: store.saved ? "checkmark" : "tray.and.arrow.down",
                                   isLoading: store.working, fullWidth: true) { Task { await store.save() } }
                        Text("Only this school's office and this student's own parent can read this page.")
                            .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    }
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(student.displayName(kurdish: language.language.isKurdish))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, _ note: LocalizedStringKey?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            if let note { Text(note).darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4) }
            CardList { content() }
        }
    }

    @ViewBuilder
    private func field(_ title: LocalizedStringKey, _ key: WritableKeyPath<StudentRecordStore.Record, String?>, placeholder: LocalizedStringKey? = nil) -> some View {
        HStack {
            Text(title).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary).frame(width: 130, alignment: .leading)
            TextField(placeholder ?? "—", text: store.bind(key))
                .multilineTextAlignment(.trailing)
                .darsType(.subheadline)
                .disabled(!editable)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11)
        Divider().padding(.leading, Metrics.Space.md)
    }

    @ViewBuilder
    private func phone(_ title: LocalizedStringKey, _ key: WritableKeyPath<StudentRecordStore.Record, String?>) -> some View {
        HStack {
            Text(title).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary).frame(width: 130, alignment: .leading)
            TextField("—", text: store.bind(key))
                .keyboardType(.phonePad).multilineTextAlignment(.trailing).darsType(.subheadline)
                .disabled(!editable)
            if let number = store.record[keyPath: key], !number.isEmpty, let url = URL(string: "tel:\(number)") {
                Link(destination: url) { Image(systemName: "phone.fill").font(.system(size: 13)).foregroundStyle(DarsColor.accentLabel) }
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11)
        Divider().padding(.leading, Metrics.Space.md)
    }

    @ViewBuilder
    private func number(_ title: LocalizedStringKey, _ key: WritableKeyPath<StudentRecordStore.Record, Int?>) -> some View {
        HStack {
            Text(title).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary).frame(width: 170, alignment: .leading)
            TextField("—", text: Binding(
                get: { store.record[keyPath: key].map(String.init) ?? "" },
                set: { store.record[keyPath: key] = Int($0.filter(\.isNumber)) }
            ))
            .keyboardType(.numberPad).multilineTextAlignment(.trailing).darsType(.subheadline)
            .disabled(!editable)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11)
        Divider().padding(.leading, Metrics.Space.md)
    }
}
