import UIKit

@MainActor
enum HapticEngine {
    enum Event {
        case selection
        case impactLight
        case impactMedium
        case impactRigid
        case success
        case error
        case warning
    }

    static func play(_ event: Event) {
        switch event {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .impactLight:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .impactMedium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .impactRigid:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    static func prepare() {
        UISelectionFeedbackGenerator().prepare()
        UIImpactFeedbackGenerator(style: .light).prepare()
    }
}
