import AVFoundation
import Combine
import CoreAudio

final class AudioRecorder: ObservableObject {
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 30)
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?
    @Published var isTooQuiet = false
    @Published var isTooNoisy = false
    @Published var isMicrophoneDenied = false

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var timer: Timer?
    private var startTime: Date?
    private let levelHistoryCount = 30
    private var recentLevels: [Float] = []
    private var smoothedDisplayLevel: Float = 0
    private var estimatedNoiseFloorDb: Float = -55
    
    // Lightweight monitor mode (for Settings live meter)
    private var monitorEngine: AVAudioEngine?
    @Published var isMonitoring = false

    var currentRecordingURL: URL? { recordingURL }

    func startRecording(inputDeviceID: String? = nil) {
        // Stop monitor mode if active (avoid two engines on same mic)
        stopMonitoring()
        
        error = nil
        isTooQuiet = false
        isTooNoisy = false
        isMicrophoneDenied = false
        recentLevels.removeAll()
        resetLevelTracking()
        
        // 1. Check Microphone Permissions
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            proceedWithRecording(inputDeviceID: inputDeviceID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.proceedWithRecording(inputDeviceID: inputDeviceID)
                    } else {
                        self?.handlePermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            handlePermissionDenied()
        @unknown default:
            handlePermissionDenied()
        }
    }

    private func handlePermissionDenied() {
        self.isMicrophoneDenied = true
        self.error = "Microphone access denied. Please enable it in System Settings → Privacy & Security."
    }

    private func proceedWithRecording(inputDeviceID: String?) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // If a specific device is selected, try to set it
        if let deviceID = inputDeviceID {
            if let coreAudioID = findDeviceID(uniqueID: deviceID) {
                var devID = coreAudioID
                let inputNode = engine.inputNode
                if let audioUnit = inputNode.audioUnit {
                    let status = AudioUnitSetProperty(
                        audioUnit,
                        kAudioOutputUnitProperty_CurrentDevice,
                        kAudioUnitScope_Global,
                        0,
                        &devID,
                        UInt32(MemoryLayout<AudioDeviceID>.size)
                    )
                    if status != noErr {
                        print("⚠️ Error setting input device: \(status)")
                    } else {
                        print("✅ Successfully set input device to \(deviceID) (ID: \(coreAudioID))")
                    }
                }
            }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("whisper_debug: Input Node Format - Input: \(inputFormat), Output: \(recordingFormat)")

        if recordingFormat.sampleRate == 0 {
            print("❌ Error: Input node has invalid sample rate (0)")
            self.error = "Hardware busy or unavailable. Try restarting the app."
            return
        }

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("whisperkiller_\(UUID().uuidString).wav")
        recordingURL = url

        // Processing format: 16kHz mono float32 (for real-time buffer conversion)
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
            print("❌ Error: Failed to create converter from \(recordingFormat) to \(targetFormat)")
            self.error = "Audio format mismatch: \(Int(recordingFormat.sampleRate))Hz to 16kHz"
            return
        }

        // File format: 16kHz mono 16-bit integer PCM (required by whisper-cli)
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: fileSettings)
            print("whisper_debug: Audio file created at \(url.path)")
        } catch {
            self.error = "Failed to create audio file: \(error.localizedDescription)"
            return
        }

        var framesCaptured: Int64 = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            framesCaptured += Int64(buffer.frameLength)
            if framesCaptured % 100 == 0 {
                print("whisper_debug: Captured \(framesCaptured) frames so far...")
            }

            // Calculate level for visualization
            let level = self.calculateLevel(buffer: buffer)
            
            // Deep diagnostics: Peak detection
            let channelData = buffer.floatChannelData?[0]
            let frames = Int(buffer.frameLength)
            var maxPeak: Float = 0
            for i in 0..<frames {
                maxPeak = max(maxPeak, abs(channelData?[i] ?? 0))
            }

            if framesCaptured % 100 == 0 {
                print("whisper_debug: Frames: \(framesCaptured), Peak: \(maxPeak), Level: \(level)")
                if maxPeak > 0.0001 {
                    print("whisper_debug: 🔊 SIGNAL DETECTED (via Peak)")
                }
            }
            
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
                    self.isTooQuiet = avg < 0.02
                    self.isTooNoisy = avg > 0.99
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
                do {
                    try file.write(from: convertedBuffer)
                } catch {
                    print("❌ Error writing to audio file: \(error)")
                }
            } else if status == .error {
                print("❌ Conversion error: \(conversionError?.localizedDescription ?? "Unknown")")
            }
        }

        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
            startTime = Date()
            isRecording = true
            print("whisper_debug: Audio engine started successfully. Input device enabled.")

            // Update duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            print("whisper_debug: Failed to start audio engine: \(error)")
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() -> (URL?, TimeInterval) {
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
        isTooQuiet = false
        isTooNoisy = false
        recentLevels.removeAll()

        // Return nil if recording was too short (< 0.3s)
        guard duration >= 0.3 else {
            print("whisper_debug: Recording too short (\(duration)s)")
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            return (nil, 0)
        }

        if let url = recordingURL {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int64 ?? 0
            print("whisper_debug: Recording stopped. File size: \(size) bytes, duration: \(duration)s")
        }

        return (recordingURL, duration)
    }

    // MARK: - Monitor Mode (lightweight, no file writing)
    
    func startMonitoring() {
        guard !isMonitoring && !isRecording else { return }
        
        // Ensure clean state
        stopMonitoring()
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            print("whisper_debug: Cannot monitor - mic not authorized (status: \(status.rawValue))")
            return
        }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        guard format.sampleRate > 0 else {
            print("whisper_debug: Cannot monitor - invalid sample rate")
            return
        }
        
        print("whisper_debug: Starting monitor mode. Format: \(format)")
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateLevel(buffer: buffer)
            
            DispatchQueue.main.async {
                self.audioLevels.append(level)
                if self.audioLevels.count > self.levelHistoryCount {
                    self.audioLevels.removeFirst()
                }
                
                self.recentLevels.append(level)
                if self.recentLevels.count > 20 { self.recentLevels.removeFirst() }
                
                if self.recentLevels.count >= 10 {
                    let avg = self.recentLevels.reduce(0, +) / Float(self.recentLevels.count)
                    self.isTooQuiet = avg < 0.02
                    self.isTooNoisy = avg > 0.95
                }
            }
        }
        
        do {
            engine.prepare()
            try engine.start()
            
            DispatchQueue.main.async {
                self.monitorEngine = engine
                self.isMonitoring = true
                self.audioLevels = Array(repeating: 0, count: self.levelHistoryCount)
                self.recentLevels.removeAll()
                self.isTooQuiet = false
                self.isTooNoisy = false
                self.resetLevelTracking()
                print("whisper_debug: Monitor mode started successfully")
            }
        } catch {
            print("whisper_debug: Failed to start monitor: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }
    
    func stopMonitoring() {
        if let engine = monitorEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            monitorEngine = nil
        }
        
        if isMonitoring {
            DispatchQueue.main.async {
                self.isMonitoring = false
                self.audioLevels = Array(repeating: 0, count: self.levelHistoryCount)
                self.recentLevels.removeAll()
                self.isTooQuiet = false
                self.isTooNoisy = false
                self.resetLevelTracking()
                print("whisper_debug: Monitor mode stopped")
            }
        }
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
        guard frames > 0 else { return 0 }
        
        var sumSquares: Float = 0
        for i in 0..<frames {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        
        let rms = sqrt(sumSquares / Float(frames))
        let safeRms = max(rms, 1e-7)
        let levelDb = 20 * log10(safeRms)

        // Update the estimated noise floor only near the quiet end so speech does not
        // drag the baseline upward and compress the meter into saturation.
        let noiseTrackingThreshold = estimatedNoiseFloorDb + 8
        if levelDb < noiseTrackingThreshold {
            estimatedNoiseFloorDb = min(max((estimatedNoiseFloorDb * 0.92) + (levelDb * 0.08), -70), -38)
        }

        let gateDb = estimatedNoiseFloorDb + 6
        let speechCeilingDb: Float = -12
        let normalized = max(0, min((levelDb - gateDb) / (speechCeilingDb - gateDb), 1))
        let shapedLevel = sqrt(normalized)

        let smoothing: Float = shapedLevel > smoothedDisplayLevel ? 0.35 : 0.18
        smoothedDisplayLevel += (shapedLevel - smoothedDisplayLevel) * smoothing

        if smoothedDisplayLevel < 0.015 {
            smoothedDisplayLevel = 0
        }

        return smoothedDisplayLevel
    }

    private func resetLevelTracking() {
        smoothedDisplayLevel = 0
        estimatedNoiseFloorDb = -55
    }

    private func findDeviceID(uniqueID: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        for id in deviceIDs {
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &namePropertyAddress, 0, nil, &uidSize, &uid)
            
            if let uidString = uid?.takeRetainedValue() as String?, uidString == uniqueID {
                return id
            }
        }
        return nil
    }
    
    deinit {
        _ = stopRecording()
        stopMonitoring()
    }
}
