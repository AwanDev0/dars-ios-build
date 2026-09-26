import AVFoundation
import Foundation
import Observation
import PhotosUI
import SwiftUI
import Supabase

enum MediaUpload {
    static func chat(_ data: Foundation.Data, conversation: UUID, ext: String, contentType: String) async throws -> String {
        let name = "chat/\(conversation.uuidString.lowercased())/\(UUID().uuidString).\(ext)"
        _ = try await SupabaseService.client.storage.from("chat-media")
            .upload(name, data: data, options: FileOptions(contentType: contentType, upsert: false))
        return publicURL(name)
    }

    static func avatar(_ data: Foundation.Data, me: UUID) async throws -> String {
        let name = "avatars/\(me.uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).jpg"
        _ = try await SupabaseService.client.storage.from("chat-media")
            .upload(name, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return publicURL(name)
    }

    private static func publicURL(_ path: String) -> String {
        "https://evaynmpgtlyjozztktbu.supabase.co/storage/v1/object/public/chat-media/" + path
    }
}

@MainActor
@Observable
final class VoiceRecorder {
    private(set) var recording = false
    private(set) var seconds = 0.0
    private(set) var level: [CGFloat] = Array(repeating: 0.12, count: 26)
    private(set) var denied = false

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var url: URL?

    func start() async {
        guard !recording else { return }
        let session = AVAudioSession.sharedInstance()
        let allowed = await withCheckedContinuation { c in
            session.requestRecordPermission { c.resume(returning: $0) }
        }
        guard allowed else { denied = true; return }
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("dars-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let r = try AVAudioRecorder(url: file, settings: settings)
            r.isMeteringEnabled = true
            r.record()
            recorder = r
            url = file
            recording = true
            seconds = 0
            HapticEngine.play(.impactMedium)
            ticker = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            denied = true
        }
    }

    private func tick() {
        guard let r = recorder, recording else { return }
        r.updateMeters()
        seconds += 0.08
        let db = max(-60, min(0, r.averagePower(forChannel: 0)))
        let v = CGFloat(pow(10, db / 40))
        level.removeFirst()
        level.append(max(0.12, min(1, v * 1.6)))
    }

    func finish(cancel: Bool = false) -> (Foundation.Data, Double)? {
        ticker?.invalidate(); ticker = nil
        recorder?.stop(); recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { url = nil; level = Array(repeating: 0.12, count: 26) }
        guard let url, !cancel, seconds >= 0.6, let data = try? Foundation.Data(contentsOf: url) else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return (data, seconds)
    }
}

struct Composer: View {
    let conversation: UUID
    let me: Profile
    let store: ThreadStore
    @Binding var replyingTo: MessageRow?

    @State private var recorder = VoiceRecorder()
    @State private var photo: PhotosPickerItem?
    @State private var cancelling = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let r = replyingTo { replyBar(r) }
            if recorder.recording {
                recordingBar
            } else {
                normalBar
            }
        }
        .background(GlassSurface(radius: 0, rimmed: false) { Color.clear }.ignoresSafeArea(edges: .bottom))
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Foundation.Data.self) {
                    await store.sendPhoto(data, to: conversation, me: me.id, replyTo: replyingTo?.id)
                    replyingTo = nil
                }
                photo = nil
            }
        }
    }

    private var normalBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 20)).foregroundStyle(DarsColor.labelSecondary)
                    .frame(width: 38, height: 38)
            }
            TextField("Message", text: Binding(get: { store.draft }, set: { store.draft = $0 }), axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DarsColor.separator, lineWidth: 0.5))
            if store.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                micButton
            } else {
                Button {
                    Task { await store.send(to: conversation, me: me.id, replyTo: replyingTo?.id); replyingTo = nil }
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(DarsColor.onAccent)
                        .frame(width: 40, height: 40).background(DarsColor.accent, in: Circle())
                }
                .disabled(store.sending)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
        .animation(Motion.selection, value: store.draft.isEmpty)
    }

    private var micButton: some View {
        Image(systemName: "mic.fill").font(.system(size: 17)).foregroundStyle(DarsColor.onAccent)
            .frame(width: 40, height: 40).background(DarsColor.accent, in: Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !recorder.recording { Task { await recorder.start() } }
                        cancelling = g.translation.width < -60
                    }
                    .onEnded { _ in
                        let cancelled = cancelling
                        cancelling = false
                        if let (data, seconds) = recorder.finish(cancel: cancelled) {
                            Task { await store.sendVoice(data, seconds: seconds, to: conversation, me: me.id, replyTo: replyingTo?.id); replyingTo = nil }
                        } else {
                            HapticEngine.play(.selection)
                        }
                    }
            )
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Circle().fill(DarsColor.danger).frame(width: 10, height: 10)
                .opacity(recorder.seconds.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
            Text(Self.clock(recorder.seconds)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
            HStack(spacing: 2) {
                ForEach(Array(recorder.level.enumerated()), id: \.offset) { _, v in
                    Capsule().fill(cancelling ? DarsColor.danger : DarsColor.accent).frame(width: 2.5, height: max(3, v * 24))
                }
            }
            Spacer()
            Text(cancelling ? "Release to cancel" : "Slide left to cancel")
                .darsType(.caption).foregroundStyle(cancelling ? DarsColor.danger : DarsColor.labelTertiary)
        }
        .padding(.horizontal, Metrics.Space.md).frame(height: 60)
        .transition(.opacity)
        .animation(Motion.selection, value: cancelling)
    }

    private func replyBar(_ r: MessageRow) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(DarsColor.accent).frame(width: 3).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to").darsType(.caption).foregroundStyle(DarsColor.accentLabel)
                Text(r.preview).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary).lineLimit(1)
            }
            Spacer()
            Button { withAnimation(Motion.selection) { replyingTo = nil } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(DarsColor.labelTertiary)
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 8)
        .frame(height: 46)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    static func clock(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
