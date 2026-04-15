import SwiftUI

struct StatusMessageView: View {
    let callout: StatusCallout?

    var body: some View {
        if let callout = callout {
            CalloutView(kind: callout.kind, title: callout.message, action: callout.action)
        }
    }
}

#if DEBUG
struct StatusMessageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            StatusMessageView(callout: StatusCallout(kind: .success, message: "Installation complete."))
            StatusMessageView(callout: StatusCallout(kind: .error, message: "Permission denied."))
            StatusMessageView(callout: nil)
        }
        .padding()
        .frame(width: 420)
    }
}
#endif
