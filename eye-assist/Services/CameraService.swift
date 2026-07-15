import Foundation
import AVFoundation
import CoreVideo

/// Owns the capture session: back camera video frames plus synchronized LiDAR
/// depth when the device has it (R1.1, R1.5). Frames are delivered on a
/// background queue via `onFrame`.
final class CameraService: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "audiovision.camera.session")
    private let dataQueue = DispatchQueue(label: "audiovision.camera.data")

    private let videoOutput = AVCaptureVideoDataOutput()
    private var depthOutput: AVCaptureDepthDataOutput?
    private var synchronizer: AVCaptureDataOutputSynchronizer?

    private(set) var hasLiDAR = false
    /// Called on `dataQueue` with each video frame and its depth (if any).
    var onFrame: ((CVPixelBuffer, AVDepthData?) -> Void)?

    func configureAndStart() {
        sessionQueue.async { [self] in
            guard session.inputs.isEmpty else {
                if !session.isRunning { session.startRunning() }
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720

            let device: AVCaptureDevice?
            if let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
                device = lidar
                hasLiDAR = true
            } else {
                device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }
            guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(videoOutput)

            if hasLiDAR {
                let depth = AVCaptureDepthDataOutput()
                depth.isFilteringEnabled = true
                if session.canAddOutput(depth) {
                    session.addOutput(depth)
                    depthOutput = depth
                    let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depth])
                    sync.setDelegate(self, queue: dataQueue)
                    synchronizer = sync
                }
            }
            if synchronizer == nil {
                videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
            }

            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, nil)
    }
}

extension CameraService: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput)
                as? AVCaptureSynchronizedSampleBufferData,
              !videoData.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) else { return }

        var depth: AVDepthData?
        if let depthOutput,
           let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput)
            as? AVCaptureSynchronizedDepthData,
           !depthData.depthDataWasDropped {
            depth = depthData.depthData
        }
        onFrame?(pixelBuffer, depth)
    }
}
