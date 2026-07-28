import SwiftUI

struct SplashView: View {
    @State private var scale = 0.7
    @State private var opacity = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.227, green: 0.863, blue: 0.549),
                    Color(red: 0.039, green: 0.510, blue: 0.353),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
                Text("iFakeHealth")
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
