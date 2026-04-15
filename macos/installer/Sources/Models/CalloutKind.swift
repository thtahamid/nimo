import SwiftUI

enum CalloutKind: Equatable {
    case info
    case success
    case warning
    case error

    var iconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct CalloutAction: Equatable {
    let title: String
    let url: URL
}

struct StatusCallout: Equatable {
    let kind: CalloutKind
    let message: String
    let action: CalloutAction?

    init(kind: CalloutKind, message: String, action: CalloutAction? = nil) {
        self.kind = kind
        self.message = message
        self.action = action
    }
}
