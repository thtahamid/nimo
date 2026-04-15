import SwiftUI

struct ModeSelectionView: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Mode:")
                .font(.body)
            Text("Direct (No Proxy)")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .disabled(true)
    }
}

#if DEBUG
struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ModeSelectionView().padding()
    }
}
#endif
