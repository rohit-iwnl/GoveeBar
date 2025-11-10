// ScreenCaptureSync.swift
// Requires macOS 12.3+
// Uses ScreenCaptureKit correctly (completion-handler APIs and a concrete SCStreamOutput)

import Foundation
import SwiftUI
import CoreImage
import ScreenCaptureKit
import AVFoundation
import AppKit

@available(macOS 12.3, *)
final class ScreenCaptureSync {
    private let govee: GoveeDeviceController
    private let ciContext = CIContext(options: nil)
    private var stream: SCStream?
    private var outputHandler: StreamOutputHandler?
    private var lastColor: NSColor?
    private let colorDeltaThreshold: CGFloat = 0.05
    private let queue = DispatchQueue(label: "com.yourapp.screencapture.queue", qos: .userInitiated)

    init(goveeController: GoveeDeviceController) {
        self.govee = goveeController
    }

    func start(pollInterval: TimeInterval = 0.05, downscaleWidth: Int = 320, downscaleHeight: Int = 180) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Acquire shareable content via completion-handler API
            SCShareableContent.getWithCompletionHandler { content, error in
                if let error = error {
                    print("❌ SCShareableContent error: \(error)")
                    return
                }
                guard let content = content else {
                    print("❌ No shareable content")
                    return
                }

                // pick main display or fallback to first
                let mainDisplayID = CGMainDisplayID() // type: CGDirectDisplayID (UInt32)
                let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first

                guard let display = display else {
                    print("❌ No displays found")
                    return
                }

                // Build content filter for that display
                // The SCContentFilter initializers allow constructing a filter for a display
                let filter = SCContentFilter(display: display, excludingWindows: [])

                // Configure stream
                let config = SCStreamConfiguration()
                config.width = downscaleWidth
                config.height = downscaleHeight
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1.0 / pollInterval == 0 ? 1 : Int64(1.0 / pollInterval)))
                config.showsCursor = false

                // Create the stream (strong reference kept)
                do {
                    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                    self.stream = stream

                    // Create and keep a strong reference to our SCStreamOutput-conforming handler
                    let handler = StreamOutputHandler { [weak self] sampleBuffer in
                        self?.processSampleBuffer(sampleBuffer)
                    }
                    self.outputHandler = handler

                    // add output and start capture using macOS 12.3 signature
                    try stream.addStreamOutput(handler,
                                               type: .screen,
                                               sampleHandlerQueue: self.queue)

                    stream.startCapture { startError in
                        if let startError = startError {
                            print("❌ Failed to start capture: \(startError)")
                        } else {
                            print("✔️ ScreenCaptureKit stream started for display \(display.displayID)")
                        }
                    }
                } catch {
                    print("❌ Failed to create or configure SCStream: \(error)")
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stream?.stopCapture { err in
                if let err = err {
                    print("❌ stopCapture error: \(err)")
                } else {
                    print("✔️ Stream stopped")
                }
            }
            self.stream = nil
            self.outputHandler = nil
        }
    }

    // MARK: - Frame processing
    // MARK: - Frame processing
    // MARK: - Frame processing (dominant-with-fallback)
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // ---- tuning params ----
        let targetSize = 40              // sample image max dimension (40x?)
        let quantStep = 16               // quantize channel by this step (16 -> 0..15)
        let minPct = 0.03                // a bucket must cover >= 3% to be considered
        let satThreshold = 0.15          // minimum saturation to be considered (ignore desaturated)
        let brightThreshold = 0.95       // consider v>brightThreshold with low sat as white
        let topN = 6                     // how many top buckets to print
        // ------------------------

        // Downscale while keeping aspect so we render a small bitmap
        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 else { return }
        let scale = CGFloat(targetSize) / max(extent.width, extent.height)
        let smallImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = max(1, Int(round(extent.width * scale)))
        let height = max(1, Int(round(extent.height * scale)))

        // Render the downscaled CIImage to a RGBA bitmap
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var raw = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        ciContext.render(
            smallImage,
            toBitmap: &raw,
            rowBytes: bytesPerRow,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // Build quantized histogram
        var counts: [UInt32: Int] = [:]
        var totalPixels = 0
        for i in stride(from: 0, to: raw.count, by: 4) {
            let a = raw[i+3]
            if a == 0 { continue } // skip fully transparent if present
            let r = Int(raw[i])
            let g = Int(raw[i+1])
            let b = Int(raw[i+2])

            let br = r / quantStep
            let bg = g / quantStep
            let bb = b / quantStep
            let key = UInt32(br << 16 | bg << 8 | bb)
            counts[key, default: 0] += 1
            totalPixels += 1
        }
        if totalPixels == 0 { return }

        // Sort buckets by count
        let sorted = counts.sorted { $0.value > $1.value }
        let topBuckets = Array(sorted.prefix(topN))

        // Helper: convert bucket key back to 0..255 approximated center value
        func bucketToRGB(_ key: UInt32) -> (r: Int, g: Int, b: Int) {
            let br = Int((key >> 16) & 0xFF)
            let bg = Int((key >> 8) & 0xFF)
            let bb = Int(key & 0xFF)
            let center = { (bucket: Int) -> Int in
                // center of bucket = (bucket + 0.5) * step
                Int(round((Double(bucket) + 0.5) * Double(quantStep)))
            }
            return (center(br), center(bg), center(bb))
        }

        // Helper: RGB -> HSV (0..1)
        func rgbToHSV(r: Int, g: Int, b: Int) -> (h: Double, s: Double, v: Double) {
            let rf = Double(r) / 255.0
            let gf = Double(g) / 255.0
            let bf = Double(b) / 255.0
            let maxv = max(rf, gf, bf)
            let minv = min(rf, gf, bf)
            let delta = maxv - minv
            let v = maxv
            let s = (maxv == 0) ? 0 : (delta / maxv)
            var h: Double = 0
            if delta != 0 {
                if maxv == rf {
                    h = (gf - bf) / delta
                } else if maxv == gf {
                    h = 2 + (bf - rf) / delta
                } else {
                    h = 4 + (rf - gf) / delta
                }
                h *= 60
                if h < 0 { h += 360 }
            }
            return (h/360.0, s, v)
        }

        // Build readable list for print and apply filters
        var readable: [(r:Int,g:Int,b:Int,pct:Double,s:Double,v:Double)] = []
        for (key, count) in topBuckets {
            let (r, g, b) = bucketToRGB(key)
            let pct = Double(count) / Double(totalPixels)
            let (_, s, v) = rgbToHSV(r: r, g: g, b: b)
            readable.append((r,g,b,pct,s,v))
        }

        // Print top buckets
        let topStrings = readable.map { item in
            String(format: "(%d,%d,%d) %.1f%% s=%.2f v=%.2f", item.r, item.g, item.b, item.pct * 100.0, item.s, item.v)
        }
        print("🎨 Top colors: " + topStrings.joined(separator: ", "))

        // Choose first bucket that passes filters
        var chosenRGB: (r:Int,g:Int,b:Int)? = nil
        for item in readable {
            // skip undersize
            if item.pct < minPct { continue }
            // skip near-black
            if item.v < 0.05 { continue }
            // skip near-white / very desaturated but very bright
            if item.v > brightThreshold && item.s < satThreshold { continue }
            // skip low saturation if you want only vivid colors (optional)
            if item.s < satThreshold { continue }
            chosenRGB = (item.r, item.g, item.b)
            break
        }

        // If nothing acceptable, fallback to average color (so we still send something)
        if chosenRGB == nil {
            // compute average via CIAreaAverage (fast)
            if let avgColor = averageColor(ciImage: ciImage) {
                let r = Int(round(avgColor.redComponent * 255.0))
                let g = Int(round(avgColor.greenComponent * 255.0))
                let b = Int(round(avgColor.blueComponent * 255.0))
                print("👉 No dominant passed thresholds — falling back to average R:\(r) G:\(g) B:\(b)")
                chosenRGB = (r,g,b)
            } else {
                // as a last resort, pick top bucket raw
                if let first = readable.first {
                    chosenRGB = (first.r, first.g, first.b)
                    print("👉 Fallback to top bucket R:\(first.r) G:\(first.g) B:\(first.b)")
                } else {
                    return
                }
            }
        } else {
            let c = chosenRGB!
            print("👉 Chosen dominant color → R:\(c.r) G:\(c.g) B:\(c.b)")
        }

        // send the chosen color
        if let chosen = chosenRGB {
            DispatchQueue.main.async {
                self.govee.sendColor(r: chosen.r, g: chosen.g, b: chosen.b)
                self.lastColor = NSColor(calibratedRed: CGFloat(chosen.r)/255.0,
                                         green: CGFloat(chosen.g)/255.0,
                                         blue: CGFloat(chosen.b)/255.0,
                                         alpha: 1.0)
            }
        }

        // Helper: compute average via CIAreaAverage (used for fallback)
        func averageColor(ciImage: CIImage) -> NSColor? {
            let extent = ciImage.extent
            let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extentVector]),
                  let output = filter.outputImage else {
                return nil
            }
            var bitmap = [UInt8](repeating: 0, count: 4)
            let outRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            ciContext.render(output,
                             toBitmap: &bitmap,
                             rowBytes: 4,
                             bounds: outRect,
                             format: .RGBA8,
                             colorSpace: CGColorSpaceCreateDeviceRGB())
            let r = CGFloat(bitmap[0]) / 255.0
            let g = CGFloat(bitmap[1]) / 255.0
            let b = CGFloat(bitmap[2]) / 255.0
            return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        }
    }


}

/// Concrete SCStreamOutput implementer. Receives CMSampleBuffers from SCStream.
/// You must keep a strong reference to this object while the stream is active
@available(macOS 12.3, *)
private final class StreamOutputHandler: NSObject, SCStreamOutput {
    private let onBuffer: (CMSampleBuffer) -> Void

    init(onBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    // SCStreamOutput method
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        // only process screen frames
        guard outputType == .screen else { return }
        // forward the buffer to processor
        onBuffer(sampleBuffer)
    }
}
