import SwiftUI

extension DarsError {
    var messageText: Text {
        if let messageKey {
            return Text(LocalizedStringKey(messageKey))
        }
        if case .server(let raw) = self {
            return Text(verbatim: raw)
        }
        return Text("error.network")
    }
}
