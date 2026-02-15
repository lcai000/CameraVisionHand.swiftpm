import SwiftUI
import UIKit
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        v.videoPreviewLayer.session = session
        return v
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        uiView.applyPortraitRotation()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        applyPortraitRotation()
    }
    
    func applyPortraitRotation() {
        guard let conn = videoPreviewLayer.connection else { return }
        
        // Use iOS 17+ API when available, fall back to older API for compatibility
        if #available(iOS 17.0, *) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        } else {
            // Fallback for iOS < 17.0
            conn.videoOrientation = .portrait
        }
    }
}
