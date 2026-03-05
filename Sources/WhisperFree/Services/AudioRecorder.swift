import AVFoundation
import Combine

final class AudioRecorder: ObservableObject {
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 30)
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?
    @Published var isTooQuiet = false
    @Published var isTooNoisy = false

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var timer: Timer?
    private var startTime: Date?
    private let levelHistoryCount = 30
    private var recentLevels: [Float] = []

    var currentRecordingURL: URL? { recordingURL }

    func startRecording() {
        error = nil
        isTooQuiet = false
        isTooNoisy = false
        recentLevels.removeAll()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("whisperkiller_\(UUID().uuidString).wav")
        recordingURL = url

        // Target format: 16kHz mono PCM (optimal for Whisper)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            self.error = "Failed to create audio format"
            return
        }

        guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
            self.error = "Failed to create audio converter"
            return
        }

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
        } catch {
            self.error = "Failed to create audio file: \(error.localizedDescription)"
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Calculate level for visualization
            let level = self.calculateLevel(buffer: buffer)
            
            DispatchQueue.main.async {
                self.audioLevels.append(level)
                if self.audioLevels.count > self.levelHistoryCount {
                    self.audioLevels.removeFirst()
                }
                
                // Quality alerts logic (sliding window)
                self.recentLevels.append(level)
                if self.recentLevels.count > 20 { self.recentLevels.removeFirst() }
                
                if self.recentLevels.count >= 10 {
                    let avg = self.recentLevels.reduce(0, +) / Float(self.recentLevels.count)
                    // Simple thresholds based on the amplified level
                    self.isTooQuiet = avg < 0.02
                    self.isTooNoisy = avg > 0.95
                }
            }

            // Convert and write to file
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / recordingFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData, let file = self.audioFile {
                try? file.write(from: convertedBuffer)
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            startTime = Date()
            isRecording = true

            // Update duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil
        
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        
        audioEngine = nil
        audioFile = nil
        isRecording = false

        let duration = recordingDuration
        recordingDuration = 0
        audioLevels = Array(repeating: 0, count: levelHistoryCount)

        // Return nil if recording was too short (< 0.3s)
        guard duration >= 0.3 else {
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        }

        return recordingURL
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        
        var sumSquares: Float = 0
        for i in 0..<frames {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        
        let rms = sqrt(sumSquares / Float(max(frames, 1)))
        
        // Noise floor subtraction and strong amplification (standard professional approach)
        let adjustedRms = max(0, rms - 0.001)
        return min(adjustedRms * 45.0, 1.0)
    }
}
