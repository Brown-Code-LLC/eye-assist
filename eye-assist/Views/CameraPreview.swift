import SwiftUI
import AVFoundation

/// Live camera preview (AVCaptureVideoPreviewLayer, aspect-fill).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Maps a Vision-normalized bbox (origin bottom-left, upright image space)
/// to view coordinates, matching an aspect-fill 720×1280 portrait feed.
func viewRect(for bbox: CGRect, in size: CGSize) -> CGRect {
    let imageAspect: CGFloat = 720.0 / 1280.0 // rotated portrait feed w/h
    let viewAspect = size.width / size.height

    var scale: CGSize // how much of the image survives the aspect-fill crop
    if viewAspect > imageAspect {
        // View is wider → image cropped top/bottom.
        scale = CGSize(width: 1, height: imageAspect / viewAspect)
    } else {
        // View is taller/narrower → image cropped left/right.
        scale = CGSize(width: viewAspect / imageAspect, height: 1)
    }

    // Visible sub-rect of the normalized image, centered.
    let visibleOrigin = CGPoint(x: (1 - scale.width) / 2, y: (1 - scale.height) / 2)

    // Flip y (Vision origin bottom-left → UIKit top-left).
    let topLeftY = 1 - bbox.maxY
    let x = (bbox.minX - visibleOrigin.x) / scale.width * size.width
    let y = (topLeftY - visibleOrigin.y) / scale.height * size.height
    let w = bbox.width / scale.width * size.width
    let h = bbox.height / scale.height * size.height
    return CGRect(x: x, y: y, width: w, height: h)
}
