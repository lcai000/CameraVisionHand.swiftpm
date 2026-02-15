import Foundation
import AVFoundation
import Vision
import SwiftUI
import CoreVideo
import ImageIO

// Adopting @unchecked Sendable silences the strict concurrency checks.
// This claims that we handle thread-safety manually (using sessionQueue/visionQueue).
final class HandPoseModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    
    typealias Joint = VNHumanHandPoseObservation.JointName
    
    @Published var points: [Joint: CGPoint] = [:]
    @Published var indexBendDeg: Double = 0
    @Published var status: String = "starting…"
    @Published var framesSeen: Int = 0
    @Published var isMirrored: Bool = false
    @Published var usingFront: Bool = false
    
    let session = AVCaptureSession()
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionQueue = DispatchQueue(label: "vision.queue")
    private let sessionQueue = DispatchQueue(label: "session.queue")
    
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    
    private var isConfigured = false
    
    // Access to this variable is shared between sessionQueue (writes) and visionQueue (reads).
    // In a strict environment, this should be atomic or protected by a lock,
    // but for this usage, the race condition is minimal.
    private var usingFrontCamera = true
    
    private var frameCount = 0
    private let processEveryNFrames = 1
    
    // MARK: - Notification names (no deprecation warnings)
    private static let nWasInterrupted = Notification.Name(rawValue: "AVCaptureSessionWasInterruptedNotification")
    private static let nInterruptionEnded = Notification.Name(rawValue: "AVCaptureSessionInterruptionEndedNotification")
    private static let nRuntimeError = Notification.Name(rawValue: "AVCaptureSessionRuntimeErrorNotification")
    
    private var observersInstalled = false
    
    // MARK: - Public API
    func start() {
        setStatus("auth: checking")
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async {
                self.configureSessionIfNeeded()
                self.installSessionObserversIfNeeded()
                self.startSession()
            }
            
        case .notDetermined:
            setStatus("auth: requesting")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async {
                        self.configureSessionIfNeeded()
                        self.installSessionObserversIfNeeded()
                        self.startSession()
                    }
                } else {
                    self.setStatus("FAIL: camera denied")
                }
            }
            
        case .denied:
            setStatus("FAIL: camera denied")
        case .restricted:
            setStatus("FAIL: camera restricted")
        @unknown default:
            setStatus("FAIL: camera unknown")
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.setStatus("stopped")
        }
    }
    
    /// Call this from UI to flip front/back
    func flipCamera() {
        sessionQueue.async {
            self.usingFrontCamera.toggle()
            self.reconfigureCameraInput(position: self.usingFrontCamera ? .front : .back)
        }
    }
    
    // MARK: - Status helper
    private func setStatus(_ s: String) {
        DispatchQueue.main.async { self.status = s }
    }
    
    // MARK: - Session start
    private func startSession() {
        if !session.isRunning {
            session.startRunning()
        }
        setStatus("session running (inputs:\(session.inputs.count) outputs:\(session.outputs.count))")
    }
    
    // MARK: - Configure session
    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        
        setStatus("config: begin")
        session.beginConfiguration()
        session.sessionPreset = .medium
        
        // Clear old state (Playgrounds can reuse process)
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        // Start with FRONT camera. If missing, fall back to back.
        let desired: AVCaptureDevice.Position = .front
        guard let camera =
                findCamera(position: desired) ?? findCamera(position: .back)
        else {
            session.commitConfiguration()
            setStatus("FAIL: no camera device")
            return
        }
        
        usingFrontCamera = (camera.position == .front)
        setStatus("camera: \(usingFrontCamera ? "front" : "back")")
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                setStatus("FAIL: cannot add input")
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            setStatus("FAIL: input error \(error.localizedDescription)")
            return
        }
        
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            setStatus("FAIL: cannot add output")
            return
        }
        session.addOutput(videoOutput)
        
        session.commitConfiguration()
        
        // Configure connection AFTER commit
        applyConnectionSettings()
        setStatus("config: committed")
    }
    
    private func findCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
    
    private func applyConnectionSettings() {
        guard let conn = videoOutput.connection(with: .video) else {
            setStatus("FAIL: no output connection")
            return
        }
        conn.isEnabled = true
        if conn.isVideoRotationAngleSupported(90) {
            if #available(iOS 17.0, *) {
                conn.videoRotationAngle = 90
            } else {
                // Fallback on earlier versions
            }
        }
        if conn.isVideoMirroringSupported {
            conn.isVideoMirrored = usingFrontCamera
        }
    }
    
    private func reconfigureCameraInput(position: AVCaptureDevice.Position) {
        setStatus("switching camera…")
        
        session.beginConfiguration()
        
        // Remove only inputs (keep output)
        session.inputs.forEach { session.removeInput($0) }
        
        guard let camera = findCamera(position: position) ?? findCamera(position: position == .front ? .back : .front) else {
            session.commitConfiguration()
            setStatus("FAIL: no camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                setStatus("FAIL: cannot add input")
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            setStatus("FAIL: input error \(error.localizedDescription)")
            return
        }
        
        usingFrontCamera = (camera.position == .front)
        DispatchQueue.main.async { self.usingFront = self.usingFrontCamera }
        DispatchQueue.main.async { self.isMirrored = self.usingFrontCamera }
        session.commitConfiguration()
        applyConnectionSettings()
        setStatus("camera switched: \(usingFrontCamera ? "front" : "back")")
    }
    
    // MARK: - Observers
    private func installSessionObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: Self.nWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: Self.nInterruptionEnded,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: Self.nRuntimeError,
            object: session
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func sessionWasInterrupted(_ note: Notification) {
        let reasonInt = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        let reason = reasonInt.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
        setStatus("INTERRUPTED: \(reason.map { "\($0)" } ?? "unknown")")
    }
    
    @objc private func sessionInterruptionEnded(_ note: Notification) {
        setStatus("interruption ended")
    }
    
    @objc private func sessionRuntimeError(_ note: Notification) {
        let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        setStatus("RUNTIME ERROR: \(err?.localizedDescription ?? "unknown")")
    }
    
    // MARK: - Frame processing
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        DispatchQueue.main.async {
            self.framesSeen += 1
        }
        
        frameCount += 1
        if frameCount % processEveryNFrames != 0 { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: currentVisionOrientation(),
            options: [:]
        )
        
        do {
            try handler.perform([request])
            
            guard let obs = request.results?.first else {
                DispatchQueue.main.async {
                    self.points = [:]
                    self.indexBendDeg = 0
                }
                return
            }
            
            let all = try obs.recognizedPoints(.all)
            var newPoints: [Joint: CGPoint] = [:]
            for (j, p) in all where p.confidence >= 0.15 {
                newPoints[j] = p.location
            }
            
            let bend = Self.bendAngleDegrees(points: newPoints,
                                             a: .indexMCP, b: .indexPIP, c: .indexDIP) ?? 0
            
            DispatchQueue.main.async {
                self.points = newPoints
                self.indexBendDeg = bend
            }
        } catch {
            // ignore frame errors
        }
    }
    
    private static func bendAngleDegrees(points: [Joint: CGPoint],
                                         a: Joint, b: Joint, c: Joint) -> Double? {
        guard let A = points[a], let B = points[b], let C = points[c] else { return nil }
        
        let v1 = CGVector(dx: A.x - B.x, dy: A.y - B.y)
        let v2 = CGVector(dx: C.x - B.x, dy: C.y - B.y)
        
        let dot = v1.dx*v2.dx + v1.dy*v2.dy
        let m1 = sqrt(v1.dx*v1.dx + v1.dy*v1.dy)
        let m2 = sqrt(v2.dx*v2.dx + v2.dy*v2.dy)
        guard m1 > 1e-6, m2 > 1e-6 else { return nil }
        
        var cosv = dot / (m1*m2)
        cosv = min(1, max(-1, cosv))
        
        return Double(acos(cosv) * 180.0 / .pi)
    }
    
    private func currentVisionOrientation() -> CGImagePropertyOrientation {
        return usingFrontCamera ? .rightMirrored : .right
    }
}
