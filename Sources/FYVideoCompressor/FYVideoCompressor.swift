import Foundation
import AVFoundation
// sample video https://download.blender.org/demo/movies/BBB/

public class FYVideoCompressor {
    public enum VideoCompressorError: Error, LocalizedError {
        case noVideo
        case compressedFailed(_ error: Error)

        public var errorDescription: String? {
            switch self {
            case .noVideo:
                return "No video"
            case .compressedFailed(let error):
                return error.localizedDescription
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
        case mediumQuality //
        
        /// Scale video size proportionally, not large than 1080p and
        /// reduce fps and bit rate if need.
        case highQuality

        /// reduce fps and bit rate if need.
        /// Scale video size with specified `scale`
        case custom(fps: Float = 24, bitrate: Int = 1000_000, scale: CGSize)

        /// fps and bitrate.
        /// Considering that the video size taken by mobile phones is reversed, we don't hard code scale value.
        var value: (fps: Float, bitrate: Int) {
            switch self {
            case .lowQuality:
                return (24, 1000_000)
            case .mediumQuality:
                return (30, 4000_000)
            case .highQuality:
                return (30, 8000_000)
            case .custom(fps: let fps, bitrate: let bitrate, _):
                return (fps, bitrate)
            }
        }
                
    }
    
    // Compression Encode Parameters
    public struct CompressionConfig {
        // video
        let videoBitrate: Int // bitrate use 1000 for 1kbps.https://en.wikipedia.org/wiki/Bit_rate
        
        let videomaxKeyFrameInterval: Int // A key to access the maximum interval between keyframes. 1 means key frames only, H.264 only
        
        let fps: Float // If video's fps less than this value, this value will be ignored.
        
        // audio
        let audioSampleRate: Int
        
        let audioBitrate: Int

        let fileType: AVFileType
        
        /// Scale (resize) the input video
        /// 1. If you need to simply resize your video to a specific size (e.g 320×240), you can use the scale: CGSize(width: 320, height: 240)
        /// 2. If you want to keep the aspect ratio, you need to specify only one component, either width or height, and set the other component to -1
        ///    e.g CGSize(width: 320, height: -1)
        let scale: CGSize?

        /// size: nil
        /// videoBitrate: 1Mbps
        /// videomaxKeyFrameInterval: 10
        /// audioSampleRate: 44100
        /// audioBitrate: 128_000
        /// fileType: mp4
        public static let `default` = CompressionConfig(
            videoBitrate: 1000_000,
            videomaxKeyFrameInterval: 10,
            fps: 24,
            audioSampleRate: 44100,
            audioBitrate: 128_000,
            fileType: .mp4,
            scale: nil
        )
    }
    
    private let group = DispatchGroup()
    private let videoCompressQueue = DispatchQueue.init(label: "com.video.compress_queue")
    private lazy var audioCompressQueue = DispatchQueue.init(label: "com.audio.compress_queue")
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    
    static public let shared: FYVideoCompressor = FYVideoCompressor()
    
    private init() {
    }
    
    static public var minimumVideoBitrate = 1000 * 400 // youtube suggests 1Mbps for 24 frame rate 360p video, 1Mbps = 1000_000bps
        
    public func compressVideo(_ url: URL, quality: VideoQuality = .mediumQuality, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVAsset(url: url)
        // setup
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(VideoCompressorError.noVideo))
            return
        }
        // --- Video ---
        // video bit rate
        let targetVideoBitRate = quality.value.bitrate

        // scale size
        let scaleSize = calculateSizeWith(originalSize: videoTrack.naturalSize, quality: quality)

        let videoSettings = createVideoSettingsWithBitrate(targetVideoBitRate,
                                                           maxKeyFrameInterval: 10,
                                                           size: scaleSize)
        var audioTrack: AVAssetTrack?
        var audioSettings: [String: Any]?
        if let adTrack = asset.tracks(withMediaType: .audio).first {
            // --- Audio ---
            audioTrack = adTrack
            let audioBitrate: Int
            let audioSampleRate: Int
            
            audioBitrate = quality == .lowQuality ? 96_000 : 128_000 // 96_000
            audioSampleRate = 44100
            audioSettings = createAudioSettingsWithAudioTrack(adTrack, bitrate: audioBitrate, sampleRate: audioSampleRate)
        }
#if DEBUG
        print("Original video size: \(url.sizePerMB())M")
        print("########## Video ##########")
        print("ORIGINAL:")
        print("bitrate: \(videoTrack.estimatedDataRate) b/s")

        print("size: \(videoTrack.naturalSize)")

        print("TARGET:")
        print("video bitrate: \(targetVideoBitRate) b/s")
        print("size: (\(scaleSize))")
#endif
        _compress(asset: asset, fileType: .mp4, videoTrack, videoSettings, audioTrack, audioSettings, targetFPS: quality.value.fps, completion: completion)
    }

    public func compressVideo(_ url: URL, config: CompressionConfig = .default, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVAsset(url: url)
        // setup
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(VideoCompressorError.noVideo))
            return
        }

        let targetSize = config.scale ?? videoTrack.naturalSize
        let videoSettings = createVideoSettingsWithBitrate(config.videoBitrate,
                                                           maxKeyFrameInterval: config.videomaxKeyFrameInterval,
                                                           size: targetSize)

        var audioTrack: AVAssetTrack?
        var audioSettings: [String: Any]?

        if let adTrack = asset.tracks(withMediaType: .audio).first {
            audioTrack = adTrack
            audioSettings = createAudioSettingsWithAudioTrack(adTrack, bitrate: config.audioBitrate, sampleRate: config.audioSampleRate)
        }

        _compress(asset: asset, fileType: config.fileType, videoTrack, videoSettings, audioTrack, audioSettings, targetFPS: config.fps, completion: completion)
    }
    
    
    ///  Your app should remove files from this directory when they are no longer needed;
    ///  however, the system may purge this directory when your app is not running.
    /// - Parameter path: path to remove
    public static func removeCompressedTempFile(at path: URL) {
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
        }
    }
    
    // MARK: - Private methods
    private func _compress(asset: AVAsset, fileType: AVFileType, _ videoTrack: AVAssetTrack, _ videoSettings: [String: Any], _ audioTrack: AVAssetTrack?, _ audioSettings: [String: Any]?, targetFPS: Float, completion: @escaping (Result<URL, Error>) -> Void) {
        // video
        let videoOutput = AVAssetReaderTrackOutput.init(track: videoTrack,
                                                        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                                                                                kCVPixelFormatType_32BGRA])
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = videoTrack.preferredTransform // fix output video orientation
        do {
            var outputURL = try FileManager.tempDirectory(with: "CompressedVideo")
            let videoName = UUID().uuidString + ".\(fileType.fileExtension)"
            outputURL.appendPathComponent("\(videoName)")

            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter.init(url: outputURL, fileType: fileType)
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
            if reduceFPS {
                outputVideoDataByReducingFPS(originFPS: videoTrack.nominalFrameRate,
                                             targetFPS: targetFPS,
                                             videoInput: videoInput,
                                             videoOutput: videoOutput,
                                             duration: videoTrack.asset!.duration) {
                    self.group.leave()
                }
            } else {
                outputVideoData(videoInput, videoOutput: videoOutput) {
                    self.group.leave()
                }
            }

            // output audio
            if let realAudioInput = audioInput, let realAudioOutput = audioOutput {
                group.enter()
                realAudioInput.requestMediaDataWhenReady(on: audioCompressQueue) {
                    while realAudioInput.isReadyForMoreMediaData {
                        if let buffer = realAudioOutput.copyNextSampleBuffer() {
                            realAudioInput.append(buffer)
                        } else {
                            //                            print("finish audio appending")
                            realAudioInput.markAsFinished()
                            self.group.leave()
                            break
                        }
                    }
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
                        print("compression time: \(elapse)")
                        print("compressed video size: \(outputURL.sizePerMB())M")
#endif
                        DispatchQueue.main.sync {
                            completion(.success(outputURL))
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
    
    private func createVideoSettingsWithBitrate(_ bitrate: Int, maxKeyFrameInterval: Int, size: CGSize) -> [String: Any] {
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

    private func createAudioSettingsWithAudioTrack(_ audioTrack: AVAssetTrack, bitrate: Int, sampleRate: Int) -> [String: Any] {
#if DEBUG
        if let audioFormatDescs = audioTrack.formatDescriptions as? [CMFormatDescription], let formatDescription = audioFormatDescs.first {
            print("########## Audio ##########")
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
            print("channels: \(2)")
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

    private func outputVideoDataByReducingFPS(originFPS: Float,
                                              targetFPS: Float,
                                              videoInput: AVAssetWriterInput,
                                              videoOutput: AVAssetReaderTrackOutput,
                                              duration: CMTime,
                                              completion: @escaping(() -> Void)) {
        let randomFrames = getFrameIndexesWith(originalFPS: originFPS, targetFPS: targetFPS, duration: Float(duration.seconds))
        var counter = 0
        var index = 0
        
        videoInput.requestMediaDataWhenReady(on: videoCompressQueue) {
            while videoInput.isReadyForMoreMediaData {
                if let buffer = videoOutput.copyNextSampleBuffer() {
                    // append first frame
                    let frameIndex = randomFrames[index]
                    
                    if counter == frameIndex {
                        index += 1
                        let timingInfo = UnsafeMutablePointer<CMSampleTimingInfo>.allocate(capacity: 1)
                        let newSample = UnsafeMutablePointer<CMSampleBuffer?>.allocate(capacity: 1)

                        // Should check call succeeded
                        CMSampleBufferGetSampleTimingInfo(buffer, at: 0, timingInfoOut: timingInfo)
                        
                        // timingInfo.pointee.duration is 0
                        timingInfo.pointee.duration = CMTimeMultiplyByFloat64(timingInfo.pointee.duration, multiplier: Float64(originFPS/targetFPS))

                        // Again, should check call succeeded
                        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: 1, sampleTimingArray: timingInfo, sampleBufferOut: newSample)
                        videoInput.append(newSample.pointee!)
                        // deinit
                        newSample.deinitialize(count: 1)
                        newSample.deallocate()
                        timingInfo.deinitialize(count: 1)
                        timingInfo.deallocate()
                    }
                    counter += 1
                } else {
                    print("counter: \(counter)")
                    videoInput.markAsFinished()
                    completion()
                    break
                }
            }
        }
    }

    func outputVideoData(_ videoInput: AVAssetWriterInput,
                         videoOutput: AVAssetReaderTrackOutput,
                         completion: @escaping(() -> Void)) {
        // Loop Video Frames
        videoInput.requestMediaDataWhenReady(on: videoCompressQueue) {
            while videoInput.isReadyForMoreMediaData {
                if let vBuffer = videoOutput.copyNextSampleBuffer(), CMSampleBufferDataIsReady(vBuffer) {
                    videoInput.append(vBuffer)
                } else {
                    videoInput.markAsFinished()
                    completion()
                    break
                }
            }
        }
    }

    // MARK: - Helper
    private func calculateSizeWith(originalSize: CGSize, quality: VideoQuality) -> CGSize {
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
        return CGSize(width: targetWidth, height: targetHeight)
    }
    
    /// Randomly drop some indexes to get final frames indexes
    ///
    /// 1. Calculate original frames and target frames
    /// 2. Divide the range (0, `originalFrames`) into `targetFrames` parts equaly, eg., divide range 0..9 into 3 parts, [0, 3, 6, 9].
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
        let targetFrames = Int(ceil(Float(originalFrames) * targetFPS / originalFPS))
        #if DEBUG
        print("originFrames: \(originalFrames)")
        print("targetFrames: \(targetFrames)")
        #endif
                
        //
        var rangeArr = Array(repeating: 0, count: targetFrames)
        for i in 0..<targetFrames {
            rangeArr[i] = Int(ceil(Double(originalFrames) * Double(i+1) / Double(targetFrames)))
        }
        
        #if DEBUG
        print("range arr: \(rangeArr)")
        print("range arr count: \(rangeArr.count)")
        #endif
        
        var randomFrames = Array(repeating: 0, count: rangeArr.count)
        for index in 0..<rangeArr.count {
            if index == 0 {
                randomFrames[index] = Int.random(in: 0..<rangeArr[index])
            } else {
                let pre = rangeArr[index-1]
                let res = Int.random(in: pre..<rangeArr[index])
                randomFrames[index] = res
            }
        }
        
        #if DEBUG
        print("randomFrames: \(randomFrames)")
        print("randomFrames count: \(randomFrames.count)")
        #endif
        return randomFrames
    }
}