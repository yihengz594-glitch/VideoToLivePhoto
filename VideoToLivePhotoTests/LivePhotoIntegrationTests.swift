import XCTest
import AVFoundation
import Photos
import ImageIO
@testable import VideoToLivePhoto

final class LivePhotoIntegrationTests: XCTestCase {
    func testSilentVideoPairAndPortraitOrientation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4")
        let movie = folder.appendingPathComponent("pair.mov")
        let jpeg = folder.appendingPathComponent("pair.jpg")
        let identifier = UUID().uuidString
        try await makeVideo(at: source)
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        let sourceTracks = try await asset.loadTracks(withMediaType: .video)
        let sourceTrack = try XCTUnwrap(sourceTracks.first)
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)), of: sourceTrack, at: .zero)
        track.preferredTransform = try await sourceTrack.load(.preferredTransform)
        let generator = AVAssetImageGenerator(asset: composition)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600))
        XCTAssertEqual(frame.image.width, 240)
        XCTAssertEqual(frame.image.height, 320)
        try LivePhotoConverter.writeJPEG(frame.image, to: jpeg, identifier: identifier)
        try await LivePhotoConverter.writeMOV(composition, to: movie, identifier: identifier,
                                              stillTime: frame.actualTime, duration: CMTime(seconds: 3, preferredTimescale: 600))
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
        let maker = try XCTUnwrap(properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any])
        XCTAssertEqual(maker["17"] as? String, identifier)
        let output = AVURLAsset(url: movie)
        let metadata = try await output.load(.metadata)
        let idItem = try XCTUnwrap(metadata.first { ($0.key as? String) == LivePhotoConverter.identifierKey })
        let actualID = try await idItem.load(.stringValue)
        XCTAssertEqual(actualID, identifier)
        let outputDuration = try await output.load(.duration)
        XCTAssertEqual(outputDuration.seconds, 3, accuracy: 0.05)
        let outputTracks = try await output.loadTracks(withMediaType: .video)
        let outputTrack = try XCTUnwrap(outputTracks.first)
        let transform = try await outputTrack.load(.preferredTransform)
        XCTAssertEqual(transform, track.preferredTransform)
        let metadataTracks = try await output.loadTracks(withMediaType: .metadata)
        let metadataTrack = try XCTUnwrap(metadataTracks.first)
        let reader = try AVAssetReader(asset: output)
        let metadataOutput = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        reader.add(metadataOutput)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: metadataOutput)
        XCTAssertTrue(reader.startReading())
        let group = try XCTUnwrap(adaptor.nextTimedMetadataGroup())
        XCTAssertEqual(group.timeRange.start.seconds, frame.actualTime.seconds, accuracy: 0.001)
        let marker = try XCTUnwrap(group.items.first)
        XCTAssertEqual(marker.key as? String, LivePhotoConverter.stillTimeKey)
        XCTAssertEqual(marker.numberValue?.intValue, 0)
        // This exercises Apple's actual pair decoder without saving or asking for read permission.
        try await LivePhotoConverter.validatePair(jpeg: jpeg, movie: movie)
    }

    func testMismatchedIdentifiersAreRejected() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4")
        let movie = folder.appendingPathComponent("pair.mov")
        let jpeg = folder.appendingPathComponent("wrong.jpg")
        try await makeVideo(at: source)
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        let sourceTracks = try await asset.loadTracks(withMediaType: .video)
        let sourceTrack = try XCTUnwrap(sourceTracks.first)
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)), of: sourceTrack, at: .zero)
        let generator = AVAssetImageGenerator(asset: composition)
        let frame = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600))
        try LivePhotoConverter.writeJPEG(frame.image, to: jpeg, identifier: UUID().uuidString)
        try await LivePhotoConverter.writeMOV(composition, to: movie, identifier: UUID().uuidString,
                                              stillTime: frame.actualTime, duration: CMTime(seconds: 3, preferredTimescale: 600))
        do {
            try await LivePhotoConverter.validatePair(jpeg: jpeg, movie: movie)
            XCTFail("A mismatched pair must not be accepted")
        } catch { /* expected rejection */ }
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240
        ])
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 240, ty: 0)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<90 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                guard Date() < deadline, writer.status == .writing else { throw LiveError.message("Fixture encoder stalled") }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            XCTAssertEqual(status, kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)), Int32(index * 2), CVPixelBufferGetBytesPerRow(pixels) * 240)
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 3, timescale: 1))
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        XCTAssertEqual(writer.status, .completed)
    }
}
