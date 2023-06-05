import Foundation
import AVFoundation
import CoreMedia

// sample video https://download.blender.org/demo/movies/BBB/

/// A high-performance, flexible and easy to use Video compressor library written by Swift.
/// Using hardware-accelerator APIs in AVFoundation.
public class FYVideoCompressor {
    public enum VideoCompressorError: Error, LocalizedError {
        case noVideo
        case compressedFailed(_ error: Error)
        case outputPathNotValid(_ path: URL)
        
        public var errorDescription: String? {
            switch self {
            case .noVideo:
                return "No video"
            case .compressedFailed(let error):
                return error.localizedDescription
            case .outputPathNotValid(let path):
                return "Output path is invalid: \(path)"
            }
        }
    }
    
    /// Quality configuration. VideoCompressor will compress video by decreasing fps and bitrate.
    /// Bitrate has a minimum value: `minimumVideoBitrate`, you can change it if need.
    /// The video will be compressed using H.264, audio will be compressed using AAC.
    public enum VideoQuality: Equatable {
        /// Scale video size proportionally, not large than 224p and
        /// reduce fps and bit rate if need.
        case lowQuality
        
        /// Scale video size proportionally, not large than 480p and
        /// reduce fps and bit rate if need.
        case mediumQuality
        
        /// Scale video size proportionally, not large than 1080p and
        /// reduce fps and bit rate if need.
        case highQuality
        
        /// reduce fps and bit rate if need.
        /// Scale video size with specified `scale`.
        case custom(fps: Float = 24, bitrate: Int = 1000_000, scale: CGSize)
        
        /// fps and bitrate.
        /// This bitrate value is the maximum value. Depending on the video original bitrate, the video bitrate after compressing may be lower than this value.
        /// Considering that the video size taken by mobile phones is reversed, we don't hard code scale value.
        var value: (fps: Float, bitrate: Int) {
            switch self {
            case .lowQuality:
                return (15, 250_000)
            case .mediumQuality:
                return (24, 2500_000)
            case .highQuality:
                return (30, 8000_000)
            case .custom(fps: let fps, bitrate: let bitrate, _):
                return (fps, bitrate)
            }
        }
        
    }
    
    // Compression Encode Parameters
    public struct CompressionConfig {
        //Tag: video
        
        /// Config video bitrate.
        /// If the input video bitrate is less than this value, it will be ignored.
        /// bitrate use 1000 for 1kbps. https://en.wikipedia.org/wiki/Bit_rate.
        /// Default is 1Mbps
        public var videoBitrate: Int
        
        /// A key to access the maximum interval between keyframes. 1 means key frames only, H.264 only. Default is 10.
        public var videomaxKeyFrameInterval: Int //
        
        /// If video's fps less than this value, this value will be ignored. Default is 24.
        public var fps: Float
        
        //Tag: audio
        
        /// Sample rate must be between 8.0 and 192.0 kHz inclusive
        /// Default 44100
        public var audioSampleRate: Int
        
        /// Default is 128_000
        /// If the input audio bitrate is less than this value, it will be ignored.
        public var audioBitrate: Int
        
        /// Default is mp4
        public var fileType: AVFileType
        
        /// Scale (resize) the input video
        /// 1. If you need to simply resize your video to a specific size (e.g 320×240), you can use the scale: CGSize(width: 320, height: 240)
        /// 2. If you want to keep the aspect ratio, you need to specify only one component, either width or height, and set the other component to -1
        ///    e.g CGSize(width: 320, height: -1)
        public var scale: CGSize?
        
        ///  compressed video will be moved to this path. If no value is set, `FYVideoCompressor` will create it for you.
        ///  Default is nil.
        public var outputPath: URL?
        
        
        public init() {
            self.videoBitrate = 1000_000
            self.videomaxKeyFrameInterval = 10
            self.fps = 24
            self.audioSampleRate = 44100
            self.audioBitrate = 128_000
            self.fileType = .mp4
            self.scale = nil
            self.outputPath = nil
        }
        
        public init(videoBitrate: Int = 1000_000,
                    videomaxKeyFrameInterval: Int = 10,
                    fps: Float = 24,
                    audioSampleRate: Int = 44100,
                    audioBitrate: Int = 128_000,
                    fileType: AVFileType = .mp4,
                    scale: CGSize? = nil,
                    outputPath: URL? = nil) {
            self.videoBitrate = videoBitrate
            self.videomaxKeyFrameInterval = videomaxKeyFrameInterval
            self.fps = fps
            self.audioSampleRate = audioSampleRate
            self.audioBitrate = audioBitrate
            self.fileType = fileType
            self.scale = scale
            self.outputPath = outputPath
        }
    }
    
    private let group = DispatchGroup()
    private let videoCompressQueue = DispatchQueue.init(label: "com.video.compress_queue")
    private lazy var audioCompressQueue = DispatchQueue.init(label: "com.audio.compress_queue")
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var compressVideoPaths: [URL] = []
    
    @available(*, deprecated, renamed: "init()", message: "In the case of batch compression, singleton causes a crash, be sure to use init method - init()")
    static public let shared: FYVideoCompressor = FYVideoCompressor()
    
    public var videoFrameReducer: VideoFrameReducer!
    
    public init() { }
    
    /// Youtube suggests 1Mbps for 24 frame rate 360p video, 1Mbps = 1000_000bps.
    /// Custom quality will not be affected by this value.
    static public var minimumVideoBitrate = 1000 * 200
    
    /// Compress Video with quality.
    
    /// Compress Video with quality.
    /// - Parameters:
    ///   - url: path of the video that needs to be compressed
    ///   - quality: the quality of the output video. Default is mediumQuality.
    ///   - outputPath: compressed video will be moved to this path. If no value is set, `FYVideoCompressor` will create it for you. Default is nil.
    ///   - frameReducer: video frame reducer to reduce fps of the video.
    ///   - completion: completion block
    public func compressVideo(_ url: URL,
                              quality: VideoQuality = .mediumQuality,
                              outputPath: URL? = nil,
                              frameReducer: VideoFrameReducer = ReduceFrameEvenlySpaced(),
                              completion: @escaping (Result<URL, Error>) -> Void) {
        self.videoFrameReducer = frameReducer
        let asset = AVAsset(url: url)
        // setup
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(VideoCompressorError.noVideo))
            return
        }
        
        print("video codec type: \(videoCodecType(for: videoTrack))")
        
        // --- Video ---
        // video bit rate
        let targetVideoBitrate = getVideoBitrateWithQuality(quality, originalBitrate: videoTrack.estimatedDataRate)
        
        // scale size
        let scaleSize = calculateSizeWithQuality(quality, originalSize: videoTrack.naturalSize)
        
        let videoSettings = createVideoSettingsWithBitrate(targetVideoBitrate,
                                                           maxKeyFrameInterval: 10,
                                                           size: scaleSize)
#if DEBUG
        print("************** Video info **************")
#endif
        var audioTrack: AVAssetTrack?
        var audioSettings: [String: Any]?
        if let adTrack = asset.tracks(withMediaType: .audio).first {
            // --- Audio ---
            audioTrack = adTrack
            let audioBitrate: Int
            let audioSampleRate: Int
            
            audioBitrate = quality == .lowQuality ? 96_000 : 128_000 // 96_000
            audioSampleRate = 44100
            audioSettings = createAudioSettingsWithAudioTrack(adTrack, bitrate: Float(audioBitrate), sampleRate: audioSampleRate)
        }
#if DEBUG
        print("🎬 Video ")
        print("ORIGINAL:")
        print("video size: \(url.sizePerMB())M")
        print("bitrate: \(videoTrack.estimatedDataRate) b/s")
        print("fps: \(videoTrack.nominalFrameRate)") //
        print("scale size: \(videoTrack.naturalSize)")
        
        print("TARGET:")
        print("video bitrate: \(targetVideoBitrate) b/s")
        print("fps: \(quality.value.fps)")
        print("scale size: (\(scaleSize))")
        
        print("****************************************")
#endif
        var _outputPath: URL
        if let outputPath = outputPath {
            _outputPath = outputPath
        } else {
            _outputPath = FileManager.tempDirectory(with: "CompressedVideo")
        }
        _compress(asset: asset,
                  fileType: .mp4,
                  videoTrack,
                  videoSettings,
                  audioTrack,
                  audioSettings,
                  targetFPS: quality.value.fps,
                  outputPath: _outputPath,
                  completion: completion)
    }
    
    /// Compress Video with config.
    public func compressVideo(_ url: URL, config: CompressionConfig, frameReducer: VideoFrameReducer = ReduceFrameEvenlySpaced(), completion: @escaping (Result<URL, Error>) -> Void) {
        self.videoFrameReducer = frameReducer
        
        let asset = AVAsset(url: url)
        // setup
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(VideoCompressorError.noVideo))
            return
        }
        
#if DEBUG
        print("video codec type: \(videoCodecType(for: videoTrack))")
#endif
        let targetVideoBitrate: Float
        if Float(config.videoBitrate) > videoTrack.estimatedDataRate {
            let tempBitrate = videoTrack.estimatedDataRate/4
            targetVideoBitrate = max(tempBitrate, Float(Self.minimumVideoBitrate))
        } else {
            targetVideoBitrate = Float(config.videoBitrate)
        }
        
        let targetSize = calculateSizeWithScale(config.scale, originalSize: videoTrack.naturalSize)
        let videoSettings = createVideoSettingsWithBitrate(targetVideoBitrate,
                                                           maxKeyFrameInterval: config.videomaxKeyFrameInterval,
                                                           size: targetSize)
        
        var audioTrack: AVAssetTrack?
        var audioSettings: [String: Any]?
        
        if let adTrack = asset.tracks(withMediaType: .audio).first {
            audioTrack = adTrack
            let targetAudioBitrate: Float
            if Float(config.audioBitrate) < adTrack.estimatedDataRate {
                targetAudioBitrate = Float(config.audioBitrate)
            } else {
                targetAudioBitrate = 64_000
            }
            
            let targetSampleRate: Int
            if config.audioSampleRate < 8000 {
                targetSampleRate = 8000
            } else if config.audioSampleRate > 192_000 {
                targetSampleRate = 192_000
            } else {
                targetSampleRate = config.audioSampleRate
            }
            audioSettings = createAudioSettingsWithAudioTrack(adTrack, bitrate: targetAudioBitrate, sampleRate: targetSampleRate)
        }
        
        var _outputPath: URL
        if let outputPath = config.outputPath {
            _outputPath = outputPath
        } else {
            _outputPath = FileManager.tempDirectory(with: "CompressedVideo")
        }
        
#if DEBUG
        print("************** Video info **************")
        
        print("🎬 Video ")
        print("ORIGINAL:")
        print("video size: \(url.sizePerMB())M")
        print("bitrate: \(videoTrack.estimatedDataRate) b/s")
        print("fps: \(videoTrack.nominalFrameRate)") //
        print("scale size: \(videoTrack.naturalSize)")
        
        print("TARGET:")
        print("video bitrate: \(targetVideoBitrate) b/s")
        print("fps: \(config.fps)")
        print("scale size: (\(targetSize))")
        print("****************************************")
#endif
        
        _compress(asset: asset,
                  fileType: config.fileType,
                  videoTrack,
                  videoSettings,
                  audioTrack,
                  audioSettings,
                  targetFPS: config.fps,
                  outputPath: _outputPath,
                  completion: completion)
    }
    
    /// Remove all cached compressed videos
    public func removeAllCompressedVideo() {
        var candidates = [Int]()
        for index in 0..<compressVideoPaths.count {
            do {
                try FileManager.default.removeItem(at: compressVideoPaths[index])
                candidates.append(index)
            } catch {
                print("❌ remove compressed item error: \(error)")
            }
        }
        
        for candidate in candidates.reversed() {
            compressVideoPaths.remove(at: candidate)
        }
    }
    
    // MARK: - Private methods
    private func _compress(asset: AVAsset,
                           fileType: AVFileType,
                           _ videoTrack: AVAssetTrack,
                           _ videoSettings: [String: Any],
                           _ audioTrack: AVAssetTrack?,
                           _ audioSettings: [String: Any]?,
                           targetFPS: Float,
                           outputPath: URL,
                           completion: @escaping (Result<URL, Error>) -> Void) {
        // video
        let videoOutput = AVAssetReaderTrackOutput.init(track: videoTrack,
                                                        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                                                            kCVPixelFormatType_32BGRA])
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = videoTrack.preferredTransform // fix output video orientation
        do {
            guard FileManager.default.isValidDirectory(atPath: outputPath) else {
                completion(.failure(VideoCompressorError.outputPathNotValid(outputPath)))
                return
            }
            
            var outputPath = outputPath
            let videoName = UUID().uuidString + ".\(fileType.fileExtension)"
            outputPath.appendPathComponent("\(videoName)")
            
            // store urls for deleting
            compressVideoPaths.append(outputPath)
            
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(url: outputPath, fileType: fileType)
            self.reader = reader
            self.writer = writer
            
            // video output
            if reader.canAdd(videoOutput) {
                reader.add(videoOutput)
                videoOutput.alwaysCopiesSampleData = false
            }
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
            }
            
            // audio output
            var audioInput: AVAssetWriterInput?
            var audioOutput: AVAssetReaderTrackOutput?
            if let audioTrack = audioTrack, let audioSettings = audioSettings {
                // Specify the number of audio channels we want when decompressing the audio from the asset to avoid error when handling audio data.
                // It really matters when the audio has more than 2 channels, e.g: 'http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'
                audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
                                                                                   AVNumberOfChannelsKey: 2])
                let adInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput = adInput
                if reader.canAdd(audioOutput!) {
                    reader.add(audioOutput!)
                }
                if writer.canAdd(adInput) {
                    writer.add(adInput)
                }
            }
            
#if DEBUG
            let startTime = Date()
#endif
            // start compressing
            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: CMTime.zero)
            
            // output video
            group.enter()
            
            let reduceFPS = targetFPS < videoTrack.nominalFrameRate
            
            let frameIndexArr = videoFrameReducer.reduce(originalFPS: videoTrack.nominalFrameRate,
                                                         to: targetFPS,
                                                         with: Float(videoTrack.asset?.duration.seconds ?? 0.0))
            
            outputVideoDataByReducingFPS(videoInput: videoInput,
                                         videoOutput: videoOutput,
                                         frameIndexArr: reduceFPS ? frameIndexArr : []) {
                self.group.leave()
            }
            
            
            // output audio
            if let realAudioInput = audioInput, let realAudioOutput = audioOutput {
                group.enter()
                // todo: drop audio sample buffer
                outputAudioData(realAudioInput, audioOutput: realAudioOutput, frameIndexArr: []) {
                    self.group.leave()
                }
            }
            
            // completion
            group.notify(queue: .main) {
                switch writer.status {
                case .writing, .completed:
                    writer.finishWriting {
#if DEBUG
                        let endTime = Date()
                        let elapse = endTime.timeIntervalSince(startTime)
                        print("******** Compression finished ✅**********")
                        print("Compressed video:")
                        print("time: \(elapse)")
                        print("size: \(outputPath.sizePerMB())M")
                        print("path: \(outputPath)")
                        print("******************************************")
#endif
                        DispatchQueue.main.sync {
                            completion(.success(outputPath))
                        }
                    }
                default:
                    completion(.failure(writer.error!))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
        
    }
    
    private func createVideoSettingsWithBitrate(_ bitrate: Float, maxKeyFrameInterval: Int, size: CGSize) -> [String: Any] {
        return [AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
               AVVideoHeightKey: size.height,
          AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                 AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                             AVVideoMaxKeyFrameIntervalKey: maxKeyFrameInterval
                                 ]
        ]
    }
    
    private func createAudioSettingsWithAudioTrack(_ audioTrack: AVAssetTrack, bitrate: Float, sampleRate: Int) -> [String: Any] {
#if DEBUG
        if let audioFormatDescs = audioTrack.formatDescriptions as? [CMFormatDescription], let formatDescription = audioFormatDescs.first {
            print("🔊 Audio")
            print("ORINGIAL:")
            print("bitrate: \(audioTrack.estimatedDataRate)")
            if let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                print("sampleRate: \(streamBasicDescription.pointee.mSampleRate)")
                print("channels: \(streamBasicDescription.pointee.mChannelsPerFrame)")
                print("formatID: \(streamBasicDescription.pointee.mFormatID)")
            }
            
            print("TARGET:")
            print("bitrate: \(bitrate)")
            print("sampleRate: \(sampleRate)")
//            print("channels: \(2)")
            print("formatID: \(kAudioFormatMPEG4AAC)")
        }
#endif
        
        var audioChannelLayout = AudioChannelLayout()
        memset(&audioChannelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
        audioChannelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: bitrate,
            AVNumberOfChannelsKey: 2,
            AVChannelLayoutKey: Data(bytes: &audioChannelLayout, count: MemoryLayout<AudioChannelLayout>.size)
        ]
    }
    
    private func outputVideoDataByReducingFPS(videoInput: AVAssetWriterInput,
                                              videoOutput: AVAssetReaderTrackOutput,
                                              frameIndexArr: [Int],
                                              completion: @escaping(() -> Void)) {
        var counter = 0
        var index = 0
        
        videoInput.requestMediaDataWhenReady(on: videoCompressQueue) {
            while videoInput.isReadyForMoreMediaData {
                if let buffer = videoOutput.copyNextSampleBuffer() {
                    if frameIndexArr.isEmpty {
                        videoInput.append(buffer)
                    } else { // reduce FPS
                        // append first frame
                        if index < frameIndexArr.count {
                            let frameIndex = frameIndexArr[index]
                            if counter == frameIndex {
                                index += 1
                                videoInput.append(buffer)
                            }
                            counter += 1
                        } else {
                            // Drop this frame
                            CMSampleBufferInvalidate(buffer)
                        }
                    }
                    
                } else {
                    videoInput.markAsFinished()
                    completion()
                    break
                }
            }
        }
    }
    
    private func outputAudioData(_ audioInput: AVAssetWriterInput,
                                 audioOutput: AVAssetReaderTrackOutput,
                                 frameIndexArr: [Int],
                                 completion:  @escaping(() -> Void)) {
        
        var counter = 0
        var index = 0
        
        audioInput.requestMediaDataWhenReady(on: audioCompressQueue) {
            while audioInput.isReadyForMoreMediaData {
                if let buffer = audioOutput.copyNextSampleBuffer() {
                    
                    if frameIndexArr.isEmpty {
                        audioInput.append(buffer)
                        counter += 1
                    } else {
                        // append first frame
                        if index < frameIndexArr.count {
                            let frameIndex = frameIndexArr[index]
                            if counter == frameIndex {
                                index += 1
                                audioInput.append(buffer)
                            }
                            counter += 1
                        } else {
                            // Drop this frame
                            CMSampleBufferInvalidate(buffer)
                        }
                    }
                    
                } else {
                    audioInput.markAsFinished()
                    completion()
                    break
                }
            }
        }
    }
    
    // MARK: - Calculation
    func getVideoBitrateWithQuality(_ quality: VideoQuality, originalBitrate: Float) -> Float {
        var targetBitrate = Float(quality.value.bitrate)
        if originalBitrate < targetBitrate {
            switch quality {
            case .lowQuality:
                targetBitrate = originalBitrate/8
                targetBitrate = max(targetBitrate, Float(Self.minimumVideoBitrate))
            case .mediumQuality:
                targetBitrate = originalBitrate/4
                targetBitrate = max(targetBitrate, Float(Self.minimumVideoBitrate))
            case .highQuality:
                targetBitrate = originalBitrate/2
                targetBitrate = max(targetBitrate, Float(Self.minimumVideoBitrate))
            case .custom(_, _, _):
                break
            }
        }
        return targetBitrate
    }
    
    func calculateSizeWithQuality(_ quality: VideoQuality, originalSize: CGSize) -> CGSize {
        let originalWidth = originalSize.width
        let originalHeight = originalSize.height
        let isRotated = originalHeight > originalWidth // videos captured by mobile phone have rotated size.
        
        var threshold: CGFloat = -1
        
        switch quality {
        case .lowQuality:
            threshold = 224
        case .mediumQuality:
            threshold = 480
        case .highQuality:
            threshold = 1080
        case .custom(_, _, let scale):
            return scale
        }
        
        var targetWidth: CGFloat = originalWidth
        var targetHeight: CGFloat = originalHeight
        if !isRotated {
            if originalHeight > threshold {
                targetHeight = threshold
                targetWidth = threshold * originalWidth / originalHeight
            }
        } else {
            if originalWidth > threshold {
                targetWidth = threshold
                targetHeight = threshold * originalHeight / originalWidth
            }
        }
        return CGSize(width: Int(targetWidth), height: Int(targetHeight))
    }
    
    func calculateSizeWithScale(_ scale: CGSize?, originalSize: CGSize) -> CGSize {
        guard let scale = scale else {
            return originalSize
        }
        if scale.width == -1 && scale.height == -1 {
            return originalSize
        } else if scale.width != -1 && scale.height != -1 {
            return scale
        } else if scale.width == -1 {
            let targetWidth = Int(scale.height * originalSize.width / originalSize.height)
            return CGSize(width: CGFloat(targetWidth), height: scale.height)
        } else {
            let targetHeight = Int(scale.width * originalSize.height / originalSize.width)
            return CGSize(width: scale.width, height: CGFloat(targetHeight))
        }
    }
    
    /// Randomly drop some indexes to get final frames indexes
    ///
    /// 1. Calculate original frames and target frames
    /// 2. Divide the range (0, `originalFrames`) into `targetFrames` parts equaly, eg., divide range 0..<9 into 3 parts: 0..<3, 3..<6. 6..<9
    /// 3.
    ///
    /// - Parameters:
    ///   - originFPS: original video fps
    ///   - targetFPS: target video fps
    /// - Returns: frame indexes
    func getFrameIndexesWith(originalFPS: Float, targetFPS: Float, duration: Float) -> [Int] {
        assert(originalFPS > 0)
        assert(targetFPS > 0)
        let originalFrames = Int(originalFPS * duration)
        let targetFrames = Int(duration * targetFPS)
        
        //
        var rangeArr = Array(repeating: 0, count: targetFrames)
        for i in 0..<targetFrames {
            rangeArr[i] = Int(ceil(Double(originalFrames) * Double(i+1) / Double(targetFrames)))
        }
        
        var randomFrames = Array(repeating: 0, count: rangeArr.count)
        
        guard !randomFrames.isEmpty else {
            return []
        }
        
        // first frame
        // avoid droping the first frame
        guard randomFrames.count > 1 else {
            return randomFrames
        }
        
        for index in 1..<rangeArr.count {
            let pre = rangeArr[index-1]
            let res = Int.random(in: pre..<rangeArr[index])
            randomFrames[index] = res
        }
        return randomFrames
    }
    
    private func videoCodecType(for videoTrack: AVAssetTrack) -> String {
        let res = videoTrack.formatDescriptions
            .map { CMFormatDescriptionGetMediaSubType($0 as! CMFormatDescription).toString() }
        return res.first ?? "unknown codec type"
    }
    
    private func isKeyFrame(sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) else {
            return false
        }
        
        let attachmentCount = CFArrayGetCount(attachmentArray)
        if attachmentCount == 0 {
            return true // Assume keyframe if no attachments are present
        }
        
        let attachment = unsafeBitCast(
            CFArrayGetValueAtIndex(attachmentArray, 0),
            to: CFDictionary.self
        )
        
        if let dependsOnOthers = CFDictionaryGetValue(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_DependsOnOthers).toOpaque()) {
            let value = Unmanaged<CFBoolean>.fromOpaque(dependsOnOthers).takeUnretainedValue()
            return !CFBooleanGetValue(value)
        } else {
            return true // Assume keyframe if attachment is not present
        }
    }
}
