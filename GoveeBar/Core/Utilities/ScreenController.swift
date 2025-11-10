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
    private let govee: NetworkController
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])  // Use GPU
    private var stream: SCStream?
    private var outputHandler: StreamOutputHandler?
    private var lastColor: NSColor?
    private let colorDeltaThreshold: CGFloat = 0.08  // Slightly higher to reduce flickering
    private let queue = DispatchQueue(label: "com.rohitmanivel.GoveeBar", qos: .userInteractive)  // Higher priority

    init(goveeController: NetworkController) {
        self.govee = goveeController
    }

    func start(pollInterval: TimeInterval = 0.033, downscaleWidth: Int = 160, downscaleHeight: Int = 90) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Acquire shareable content via completion-handler API
            SCShareableContent.getWithCompletionHandler { content, error in
                if let error = error {
                    print("SCShareableContent error: \(error)")
                    return
                }
                guard let content = content else {
                    print("No shareable content")
                    return
                }

                // pick main display or fallback to first
                let mainDisplayID = CGMainDisplayID() // type: CGDirectDisplayID (UInt32)
                let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first

                guard let display = display else {
                    print("No displays found")
                    return
                }

                // Build content filter for that display
                let filter = SCContentFilter(display: display, excludingWindows: [])

                // Configure stream - optimized for low latency
                let config = SCStreamConfiguration()
                config.width = downscaleWidth
                config.height = downscaleHeight
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1.0 / pollInterval == 0 ? 1 : Int64(1.0 / pollInterval)))
                config.showsCursor = false
                config.queueDepth = 3  // Lower queue depth for faster updates

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
                            print("Failed to start capture: \(startError)")
                        } else {
                            print("ScreenCaptureKit stream started (30fps, 160x90)")
                        }
                    }
                } catch {
                    print("Failed to create or configure SCStream: \(error)")
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stream?.stopCapture { err in
                if let err = err {
                    print("stopCapture error: \(err)")
                } else {
                    print("Stream stopped")
                }
            }
            self.stream = nil
            self.outputHandler = nil
        }
    }

    // MARK: - Frame processing (optimized for speed & accuracy)
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // ---- optimized params for performance ----
        let targetSize = 32              // smaller = faster (32x18 for 16:9)
        let quantStep = 32               // larger step = fewer buckets = faster (32 -> 0..7)
        let minPct = 0.02                // lower threshold = more responsive to small changes
        let satThreshold = 0.12          // slightly lower = catch more colors
        let brightThreshold = 0.92       // slightly lower = avoid pure whites earlier
        let topN = 4                     // fewer buckets to check = faster
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

        // Build quantized histogram (optimized with pre-filtering)
        var counts: [UInt32: Int] = [:]
        var totalPixels = 0
        
        // Process pixels with early filtering for speed
        for i in stride(from: 0, to: raw.count, by: 4) {
            let a = raw[i+3]
            if a == 0 { continue } // skip fully transparent
            
            let r = Int(raw[i])
            let g = Int(raw[i+1])
            let b = Int(raw[i+2])
            
            // Quick pre-filter: skip obvious blacks/whites before quantizing
            let maxVal = max(r, g, b)
            let minVal = min(r, g, b)
            if maxVal < 13 { continue }  // skip near-black (faster than HSV check)
            if maxVal > 235 && (maxVal - minVal) < 20 { continue }  // skip near-white/gray
            
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


        var chosenRGB: (r:Int,g:Int,b:Int)? = nil
        for item in readable {
            // Relaxed filters for instant response
            if item.pct < minPct { continue }
            if item.v < 0.08 { continue }  // allow darker colors
            if item.v > brightThreshold && item.s < satThreshold { continue }
            if item.s < satThreshold { continue }
            chosenRGB = (item.r, item.g, item.b)
            break
        }

        // Quick fallback - just use top color if it has any saturation
        if chosenRGB == nil, let first = readable.first {
            if first.s > 0.05 && first.v > 0.1 {
                chosenRGB = (first.r, first.g, first.b)
            }
        }

        // Send immediately without delta checking for instant response
        if let chosen = chosenRGB {
            let newColor = NSColor(calibratedRed: CGFloat(chosen.r)/255.0,
                                   green: CGFloat(chosen.g)/255.0,
                                   blue: CGFloat(chosen.b)/255.0,
                                   alpha: 1.0)
            
            // Only send if color actually changed (reduce network spam)
            if shouldSendColor(newColor) {
                DispatchQueue.main.async {
                    self.govee.sendColor(r: chosen.r, g: chosen.g, b: chosen.b)
                    self.lastColor = newColor
                }
            }
        }

    }
    
    // Check if color change is significant enough to send
    private func shouldSendColor(_ newColor: NSColor) -> Bool {
        guard let last = lastColor else { return true }
        
        // Fast RGB distance check (avoid expensive color space conversions)
        let dr = abs(newColor.redComponent - last.redComponent)
        let dg = abs(newColor.greenComponent - last.greenComponent)
        let db = abs(newColor.blueComponent - last.blueComponent)
        let maxDelta = max(dr, dg, db)
        
        return maxDelta > colorDeltaThreshold
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
