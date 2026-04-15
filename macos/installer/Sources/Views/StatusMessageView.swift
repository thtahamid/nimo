import SwiftUI

struct StatusMessageView: View {
    let message: String?
    let isError: Bool

    var body: some View {
        if let message = message, !message.isEmpty {
            Text(message)
                .font(.callout)
                .foregroundColor(isError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
struct StatusMessageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            StatusMessageView(message: "Install succeeded.", isError: false)
            StatusMessageView(message: "Something went wrong.", isError: true)
            StatusMessageView(message: nil, isError: false)
        }
        .padding()
    }
}
#endif
