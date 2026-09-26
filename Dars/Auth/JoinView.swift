import Foundation
import Observation
import SwiftUI
import Supabase

struct JoinView: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var found: String?
    @State private var looking = false
    @State private var working = false
    @State private var joined = false
    @State private var error: String?
    @State private var scanning = false

    private var isParent: Bool { profile.role == .parent }

    struct ClassLookup: Codable, Sendable {
        let classId: UUID
        let name: String?
        let grade: String?
        let section: String?
        let schoolName: String?
        enum CodingKeys: String, CodingKey {
            case name, grade, section
            case classId = "class_id"; case schoolName = "school_name"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text(isParent
                     ? "Type your child's family code to add them to your account."
                     : "Type the code your teacher shows on the class page.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                HStack(spacing: 8) {
                    TextField(isParent ? "Family code" : "Class code", text: Binding(get: { code }, set: { code = $0.uppercased() }))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(size: 22, weight: .bold, design: .rounded)).kerning(2)
                        .submitLabel(.search).onSubmit { Task { await look() } }
                        .padding(.horizontal, 14).frame(height: 56)
                        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button { HapticEngine.play(.selection); scanning = true } label: {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 19)).frame(width: 56, height: 56)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if looking { ProgressView().frame(maxWidth: .infinity) }
                if let found {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success)
                        Text(found).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    }
                    .padding(Metrics.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DarsColor.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                if !isParent && found != nil {
                    Text("Joining moves you into this class. A student is in one class at a time.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                Spacer()
                DarsButton(title: isParent ? "Link this child" : "Join this class", kind: .primary, systemImage: "checkmark", isLoading: working, fullWidth: true) {
                    Task { await commit() }
                }
                .disabled(found == nil)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle(isParent ? "Add a child" : "Join a class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $scanning) { ScanCodeSheet { code = $0; Task { await look() } } }
            .animation(Motion.arrive, value: found)
            .onChange(of: joined) { if joined { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func look() async {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard c.count >= 4 else { return }
        looking = true
        error = nil
        found = nil
        defer { looking = false }
        do {
            if isParent {
                let rows: [ParentSignUpStore.Lookup] = try await SupabaseService.client.rpc("family_code_lookup", params: ["code": c]).execute().value
                if let r = rows.first {
                    found = [r.fullName, [r.grade, r.section].compactMap { $0 }.joined()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                } else { error = "No student has that code." }
            } else {
                let rows: [ClassLookup] = try await SupabaseService.client.rpc("class_code_lookup", params: ["code": c]).execute().value
                if let r = rows.first {
                    found = [(r.grade ?? "") + (r.section ?? ""), r.schoolName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                } else { error = "No class has that code." }
            }
            if found != nil { HapticEngine.play(.success) } else { HapticEngine.play(.error) }
        } catch {
            self.error = "Couldn't reach the school. Check the connection."
        }
    }

    private func commit() async {
        working = true
        error = nil
        defer { working = false }
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            _ = try await SupabaseService.client.rpc(isParent ? "link_child" : "join_class", params: ["code": c]).execute()
            HapticEngine.play(.success)
            joined = true
        } catch {
            let t = String(describing: error)
            if t.contains("unknown_code") { self.error = "That code is not right." }
            else if t.contains("wrong_school") { self.error = "That code belongs to another school." }
            else if t.contains("not_a_student") { self.error = "Only a student can join a class." }
            else { self.error = "Couldn't do it. Try again." }
            HapticEngine.play(.error)
        }
    }
}
