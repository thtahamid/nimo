import Foundation

enum InstallationState: Equatable {
    case idle
    case working
    case success(String)
    case failure(String)

    static func == (lhs: InstallationState, rhs: InstallationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.working, .working):
            return true
        case let (.success(l), .success(r)):
            return l == r
        case let (.failure(l), .failure(r)):
            return l == r
        default:
            return false
        }
    }
}
