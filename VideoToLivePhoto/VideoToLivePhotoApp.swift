import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreMedia

@main
struct VideoToLivePhotoApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct SelectedVideo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    var status = "待转换"
    var saved = false
}

enum TemporaryFiles {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoToLivePhoto", isDirectory: true)
}

@MainActor
final class ConversionModel: ObservableObject {
    @Published var videos: [SelectedVideo] = []
    @Published var busy = false
    @Published var message = "最多选择 10 个视频；超过 3 秒时取中间 3 秒。"
    private var directory: URL?

    init() {
        // Remove only this app's own workspace, including leftovers after forced termination.
        try? FileManager.default.removeItem(at: TemporaryFiles.root)
    }

    func importVideos(_ results: [PHPickerResult]) async {
        guard !results.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        cleanUp()
        videos = []
        do {
            let folder = TemporaryFiles.root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            directory = folder
            var failures = 0
            for (index, result) in results.prefix(10).enumerated() {
                message = "导入 \(index + 1)/\(min(results.count, 10))…"
                do {
                    let url = try await Self.copyVideo(result.itemProvider, into: folder)
                    videos.append(SelectedVideo(url: url, name: "视频 \(index + 1)"))
                } catch { failures += 1 }
            }
            message = "已导入 \(videos.count) 个视频。" + (failures > 0 ? "\(failures) 个导入失败；请确认视频已下载到本机。" : "点击转换并存入相册。")
        } catch { message = error.localizedDescription }
    }

    // The provider's URL expires as soon as its callback returns. Copy inside that callback.
    nonisolated private static func copyVideo(_ provider: NSItemProvider, into folder: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw LiveError.message("无法导入视频。") }
                    let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func convert() async {
        guard !busy, videos.contains(where: { !$0.saved }) else { return }
        busy = true
        defer { busy = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized else {
            message = "需要“仅添加照片”权限。请到设置 → App → 实况转换 → 照片，允许添加照片后重试。"
            return
        }
        // Keep the app foregrounded while the serial batch runs.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        var failed = 0
        for index in videos.indices where !videos[index].saved {
            videos[index].status = "转换中…"
            message = "正在处理 \(index + 1)/\(videos.count)，请保持 App 在前台。"
            let source = videos[index].url
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await LivePhotoConverter.convertAndSave(source)
                }.value
                try? FileManager.default.removeItem(at: source)
                videos[index].saved = true
                videos[index].status = "已存入相册 · LIVE"
            } catch {
                failed += 1
                videos[index].status = error.localizedDescription
            }
        }
        let saved = videos.filter(\.saved).count
        message = "已保存 \(saved)/\(videos.count) 张实况照片。" + (failed > 0 ? "可点击转换重试失败项，成功项不会重复保存。" : "打开系统相册查看 LIVE 并长按播放。")
    }

    private func cleanUp() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
    deinit {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

struct ContentView: View {
    @StateObject private var model = ConversionModel()
    @State private var showPicker = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "livephoto").font(.system(size: 56)).foregroundStyle(.tint)
                    .padding(.top, 24).accessibilityHidden(true)
                Text("视频 → 实况照片").font(.title2.bold())
                Text("本机转换 · 无订阅 · 无上传").foregroundStyle(.secondary)
                Button("选择视频（最多 10 个）") { showPicker = true }
                    .buttonStyle(.bordered).disabled(model.busy)
                List(model.videos) { video in
                    HStack(alignment: .top) {
                        Image(systemName: video.saved ? "checkmark.circle.fill" : "video")
                            .foregroundStyle(video.saved ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.name)
                            Text(video.status).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.listStyle(.plain)
                if model.busy { ProgressView() }
                Text(model.message).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("转换并存入相册") { Task { await model.convert() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || !model.videos.contains(where: { !$0.saved }))
                Text("离线使用前，请确保所选视频已下载到本机。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.bottom)
            .navigationTitle("实况转换").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPicker) {
                VideoPicker { results in
                    showPicker = false
                    Task { await model.importVideos(results) }
                }
            }
        }
    }
}

// PHPicker grants access only to explicitly selected files, without library-read permission.
struct VideoPicker: UIViewControllerRepresentable {
    let completion: ([PHPickerResult]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 10
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: ([PHPickerResult]) -> Void
        init(_ completion: @escaping ([PHPickerResult]) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { completion(results) }
    }
}

enum LiveError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum LivePhotoConverter {
    static let identifierKey = "com.apple.quicktime.content.identifier"
    static let stillTimeKey = "com.apple.quicktime.still-image-time"

    static func convertAndSave(_ source: URL) async throws {
        let folder = TemporaryFiles.root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let jpeg = folder.appendingPathComponent("cover.jpg")
        let movie = folder.appendingPathComponent("motion.mov")
        let identifier = UUID().uuidString
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw LiveError.message("视频没有可用画面。")
        }
        let range = try await video.load(.timeRange)
        let seconds = range.duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw LiveError.message("视频时长无效。") }
        let duration = CMTime(seconds: min(seconds, 3), preferredTimescale: 600)
        let start = range.start + CMTime(seconds: max(0, (seconds - 3) / 2), preferredTimescale: 600)
        let clipRange = CMTimeRange(start: start, duration: duration)
        let composition = AVMutableComposition()
        guard let clipVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw LiveError.message("无法创建视频轨道。")
        }
        try clipVideo.insertTimeRange(clipRange, of: video, at: .zero)
        clipVideo.preferredTransform = try await video.load(.preferredTransform)
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let audioRange = try await audio.load(.timeRange)
            let intersection = CMTimeRangeGetIntersection(clipRange, audioRange)
            if intersection.duration > .zero,
               let clipAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try clipAudio.insertTimeRange(intersection, of: audio, at: intersection.start - start)
            }
        }
        let generator = AVAssetImageGenerator(asset: composition)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5))
        // Use the actual decoded middle-frame timestamp for the MOV's timed metadata.
        try writeJPEG(frame.image, to: jpeg, identifier: identifier)
        try await writeMOV(composition, to: movie, identifier: identifier, stillTime: frame.actualTime, duration: duration)
        try await validatePair(jpeg: jpeg, movie: movie)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: jpeg, options: nil)
            request.addResource(with: .pairedVideo, fileURL: movie, options: nil)
        }
    }

    static func writeJPEG(_ image: CGImage, to url: URL, identifier: String) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LiveError.message("无法创建封面文件。")
        }
        // Apple MakerNote key 17 is the Live Photo asset identifier; not EXIF ImageUniqueID.
        let properties: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality as String: 0.95
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LiveError.message("写入封面失败。") }
    }

    static func writeMOV(_ asset: AVComposition, to url: URL, identifier: String, stillTime: CMTime, duration: CMTime) async throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let contentID = AVMutableMetadataItem()
        contentID.keySpace = .quickTimeMetadata
        contentID.key = identifierKey as NSString
        contentID.value = identifier as NSString
        contentID.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [contentID]

        guard let track = asset.tracks(withMediaType: .video).first else { throw LiveError.message("视频轨道丢失。") }
        let size = try await track.load(.naturalSize)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { throw LiveError.message("视频尺寸无效。") }
        let videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOutput.alwaysCopiesSampleData = false
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        videoInput.transform = try await track.load(.preferredTransform)
        videoInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw LiveError.message("无法配置视频编码。") }
        reader.add(videoOutput)
        writer.add(videoInput)
        var streams: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = [(videoOutput, videoInput)]
        if let audio = asset.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000
            ])
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw LiveError.message("无法配置音频编码。") }
            reader.add(output)
            writer.add(input)
            streams.append((output, input))
        }

        // A signed int8 value 0 in a TIMED metadata track marks the still frame.
        // Setting a top-level metadata value alone does not produce a Live Photo.
        var description: CMFormatDescription?
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/\(stillTimeKey)",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String
        ]
        let result = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray, formatDescriptionOut: &description)
        guard result == noErr, let description else { throw LiveError.message("无法创建实况时间标记。") }
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else { throw LiveError.message("无法添加实况元数据轨道。") }
        writer.add(metadataInput)
        guard writer.startWriting() else { throw writer.error ?? LiveError.message("无法开始写入 MOV。") }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? LiveError.message("无法解码视频。")
        }
        writer.startSession(atSourceTime: .zero)
        do {
            let marker = AVMutableMetadataItem()
            marker.keySpace = .quickTimeMetadata
            marker.key = stillTimeKey as NSString
            marker.value = NSNumber(value: Int8(0))
            marker.dataType = kCMMetadataBaseDataType_SInt8 as String
            let markerDuration = CMTimeMinimum(CMTime(value: 1, timescale: 30), duration - stillTime)
            guard stillTime >= .zero, markerDuration > .zero else { throw LiveError.message("封面时间不在视频范围内。") }
            try waitUntilReady(metadataInput, writer: writer)
            guard adaptor.append(AVTimedMetadataGroup(items: [marker], timeRange: CMTimeRange(start: stillTime, duration: markerDuration))) else {
                throw writer.error ?? LiveError.message("写入实况时间标记失败。")
            }
            metadataInput.markAsFinished()

            // Interleave tracks to avoid filling one track while another waits for data.
            var finished = Set<Int>()
            var lastProgress = Date()
            while finished.count < streams.count {
                var progressed = false
                for (index, stream) in streams.enumerated() where !finished.contains(index) {
                    if stream.1.isReadyForMoreMediaData {
                        let sample = autoreleasepool { stream.0.copyNextSampleBuffer() }
                        if let sample {
                            guard stream.1.append(sample) else { throw writer.error ?? LiveError.message("写入媒体帧失败。") }
                        } else {
                            guard reader.status != .failed, reader.status != .cancelled else {
                                throw reader.error ?? LiveError.message("读取视频中断。")
                            }
                            stream.1.markAsFinished()
                            finished.insert(index)
                        }
                        progressed = true
                    }
                }
                guard writer.status == .writing else { throw writer.error ?? LiveError.message("MOV 编码中断。") }
                if progressed { lastProgress = Date() }
                else {
                    guard Date().timeIntervalSince(lastProgress) < 60 else { throw LiveError.message("编码超时，请重试。") }
                    pauseForEncoder()
                }
            }
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else { throw writer.error ?? LiveError.message("完成 MOV 写入失败。") }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
    }

    private static func pauseForEncoder() {
        Thread.sleep(forTimeInterval: 0.002)
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) throws {
        let deadline = Date().addingTimeInterval(30)
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing, Date() < deadline else {
                throw writer.error ?? LiveError.message("元数据编码超时。")
            }
            pauseForEncoder()
        }
    }

    // Validate with Apple's Live Photo decoder before adding anything to the library.
    static func validatePair(jpeg: URL, movie: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHLivePhoto.request(withResourceFileURLs: [jpeg, movie], placeholderImage: nil,
                                targetSize: .zero, contentMode: .aspectFit) { photo, info in
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if photo != nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LiveError.message("系统未识别实况配对，未写入相册。"))
                }
            }
        }
    }
}
