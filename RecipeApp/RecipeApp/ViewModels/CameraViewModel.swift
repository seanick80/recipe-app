import AVFoundation
import Combine
import CoreMotion
import SwiftUI
import UIKit

/// Manages the camera session for scanning features (barcode, OCR, pantry photos).
/// Provides real-time video feed, photo capture, and device coaching (tilt, brightness).
@Observable
class CameraViewModel: NSObject {
    // MARK: - Published State

    var isSessionRunning = false
    var capturedImage: UIImage?
    var brightnessWarning: String?
    var tiltWarning: String?
    var isTooTilted = false
    var isTooDim = false
    var errorMessage: String?

    // MARK: - Camera Session

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session")

    // MARK: - Motion

    private let motionManager = CMMotionManager()
    private static let tiltThreshold = 0.3  // radians (~17 degrees)

    // MARK: - Brightness

    private static let dimThreshold: Double = -1.5  // EV below which we warn
    private static let brightThreshold: Double = 4.0  // EV above which we warn

    // MARK: - Photo Capture Continuation

    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    // MARK: - Setup

    func configure() {
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Camera input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            Task { @MainActor in
                self.errorMessage = "Camera not available"
            }
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // Video data output (for brightness metering)
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.video"))
        if session.canAddOutput(videoOut) {
            session.addOutput(videoOut)
            self.videoOutput = videoOut
        }

        session.commitConfiguration()
    }

    // MARK: - Session Lifecycle

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in
                self.isSessionRunning = true
            }
        }
        startMotionUpdates()
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
        stopMotionUpdates()
    }

    // MARK: - Photo Capture

    func capturePhoto() async -> UIImage? {
        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            sessionQueue.async {
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Motion Coaching

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let pitch = abs(motion.attitude.pitch)
            let roll = abs(motion.attitude.roll)

            // Phone should be roughly upright or flat-over-surface
            let tilted = roll > Self.tiltThreshold
            self.isTooTilted = tilted
            self.tiltWarning = tilted ? "Hold phone more level" : nil
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }
        Task { @MainActor in
            self.capturedImage = image
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (brightness metering)

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let metadata = CMCopyDictionaryOfAttachments(
                allocator: nil,
                target: sampleBuffer,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            ) as? [String: Any]
        else { return }

        guard let exif = metadata["{Exif}"] as? [String: Any],
            let brightness = exif["BrightnessValue"] as? Double
        else { return }

        Task { @MainActor in
            if brightness < Self.dimThreshold {
                self.isTooDim = true
                self.brightnessWarning = "Too dark — find better lighting"
            } else if brightness > Self.brightThreshold {
                self.isTooDim = false
                self.brightnessWarning = "Too bright — avoid direct light"
            } else {
                self.isTooDim = false
                self.brightnessWarning = nil
            }
        }
    }
}
