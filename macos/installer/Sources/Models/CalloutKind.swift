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

struct StatusCallout: Equatable {
    let kind: CalloutKind
    let message: String
}
