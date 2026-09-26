import Foundation
import Observation
import PhotosUI
import SwiftUI
import Supabase
import UIKit

@MainActor
@Observable
final class EditProfileStore {
    var name = ""
    var nameKu = ""
    var initials = ""
    var color = "#FAB900"
    private(set) var avatarURL: String?
    private(set) var working = false
    private(set) var saved = false
    private(set) var error: String?
    private let client = SupabaseService.client

    static let colors = ["#FAB900", "#FF9500", "#FF3B30", "#FF2D55", "#AF52DE", "#5856D6",
                         "#007AFF", "#32ADE6", "#00C7BE", "#34C759", "#8E8E93", "#5E6B7E"]

    struct Patch: Encodable {
        let full_name: String
        let full_name_ku: String?
        let avatar_initials: String
        let avatar_color: String
        let avatar_url: String?
    }

    func load(_ profile: Profile) {
        name = profile.fullName
        nameKu = profile.fullNameKu ?? ""
        initials = profile.avatarInitials ?? Self.initials(from: profile.fullName)
        color = profile.avatarColor ?? "#FAB900"
        avatarURL = profile.avatarURL
    }

    static func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    func upload(_ data: Foundation.Data, me: UUID) async {
        working = true
        defer { working = false }
        guard let image = UIImage(data: data), let jpeg = Self.shrink(image) else {
            error = "That photo could not be read."
            return
        }
        do {
            let url = try await MediaUpload.avatar(jpeg, me: me)
            avatarURL = url
            HapticEngine.play(.success)
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }

    static func shrink(_ image: UIImage, to side: CGFloat = 512) -> Foundation.Data? {
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let out = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.82)
    }

    func removePhoto() {
        avatarURL = nil
        HapticEngine.play(.selection)
    }

    func save(me: UUID) async -> Bool {
        working = true
        defer { working = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { error = "A name needs at least two letters."; return false }
        do {
            try await client.from("profiles").update(Patch(
                full_name: trimmed,
                full_name_ku: nameKu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nameKu.trimmingCharacters(in: .whitespacesAndNewlines),
                avatar_initials: initials.isEmpty ? Self.initials(from: trimmed) : String(initials.prefix(2)).uppercased(),
                avatar_color: color,
                avatar_url: avatarURL
            )).eq("id", value: me).execute()
            saved = true
            HapticEngine.play(.success)
            return true
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
            return false
        }
    }
}

struct EditProfileView: View {
    let profile: Profile
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = EditProfileStore()
    @State private var photo: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                avatarBlock
                nameBlock
                colourBlock
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                DarsButton(title: "Save", kind: .primary, systemImage: "checkmark", isLoading: store.working, fullWidth: true) {
                    Task { if await store.save(me: profile.id) { onSaved(); dismiss() } }
                }
                Text("Your name and face are visible to your school. Nobody outside it sees either.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                Spacer(minLength: 60)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.load(profile) }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Foundation.Data.self) {
                    await store.upload(data, me: profile.id)
                }
                photo = nil
            }
        }
    }

    private var avatarBlock: some View {
        VStack(spacing: Metrics.Space.sm) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(url: store.avatarURL, initials: store.initials.isEmpty ? "?" : store.initials, color: store.color, size: 104)
                if store.working {
                    Circle().fill(.black.opacity(0.35)).frame(width: 104, height: 104)
                    ProgressView().tint(.white)
                }
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(DarsColor.onAccent)
                        .frame(width: 32, height: 32).background(DarsColor.accent, in: Circle())
                        .overlay(Circle().strokeBorder(DarsColor.backgroundBase, lineWidth: 3))
                }
            }
            if store.avatarURL != nil {
                Button("Remove the photo") { store.removePhoto() }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.danger)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var nameBlock: some View {
        SectionLabel("Name")
        DarsField(title: "Full name", text: Binding(get: { store.name }, set: { store.name = $0; store.initials = EditProfileStore.initials(from: $0) }))
        DarsField(title: "Name in Kurdish", text: Binding(get: { store.nameKu }, set: { store.nameKu = $0 }))
        SectionLabel("Initials")
        HStack(spacing: 10) {
            TextField("AB", text: Binding(get: { store.initials }, set: { store.initials = String($0.prefix(2)).uppercased() }))
                .textInputAutocapitalization(.characters)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(width: 80, height: 50)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Shown when you have no photo.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
        }
    }

    @ViewBuilder
    private var colourBlock: some View {
        SectionLabel("Colour")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
            ForEach(EditProfileStore.colors, id: \.self) { hex in
                Button {
                    HapticEngine.play(.selection)
                    withAnimation(Motion.selection) { store.color = hex }
                } label: {
                    ZStack {
                        Circle().fill(Color(hexString: hex)).frame(width: 46, height: 46)
                        if store.color == hex {
                            Circle().strokeBorder(DarsColor.labelPrimary, lineWidth: 2.5).frame(width: 54, height: 54)
                            Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(height: 56)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
