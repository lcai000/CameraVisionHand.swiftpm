import SwiftUI

struct ContentView: View {
    @StateObject private var model = HandPoseModel()
    
    var body: some View {
        ZStack {
            // Background Camera Layer
            CameraPreview(session: model.session)
                .ignoresSafeArea()
            
            // Vision Overlay Layer
            HandOverlay(points: model.points, mirrored: !model.isMirrored)
                .ignoresSafeArea()
            
            // UI Controls Layer
            VStack {
                HStack {
                    Text("Tracked points: \(model.points.count)")
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    
                    Button("Flip") { model.flipCamera() }
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    
                    Spacer()
                    
                    Text("Frames: \(model.framesSeen)")
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    
                    Text(String(format: "Index bend: %.1f°", model.indexBendDeg))
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
                .padding()
                
                Spacer()
                
                Text(model.status)
                    .padding(10)
                    .background(.black.opacity(0.7))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
