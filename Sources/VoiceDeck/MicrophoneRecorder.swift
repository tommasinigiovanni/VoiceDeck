import AVFoundation
import Combine
import TranscribeCore

@MainActor
final class MicrophoneRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var level: Double = 0
    var onFailure: ((String) -> Void)?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start(in directory: URL) async throws {
        guard !isRecording, !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else {
            throw TranscribeError.message("Consenti l’accesso al microfono in Impostazioni di Sistema → Privacy e sicurezza → Microfono → VoiceDeck.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = directory.appendingPathComponent("Registrazione \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).m4a")
        let next = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        next.delegate = self; next.isMeteringEnabled = true
        guard next.prepareToRecord(), next.record() else {
            try? FileManager.default.removeItem(at: url)
            throw TranscribeError.message("Impossibile avviare il microfono. Controlla il dispositivo di ingresso del Mac.")
        }
        recorder = next; elapsed = 0; level = 0; isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters(); self.elapsed = recorder.currentTime
                self.level = max(0, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 40)))
            }
        }
    }

    func stop() -> URL? {
        guard let recorder, isRecording else { return nil }
        let url = recorder.url
        timer?.invalidate(); timer = nil; isRecording = false; level = 0
        recorder.stop(); self.recorder = nil
        return url
    }

    func discard() {
        if let url = stop() { try? FileManager.default.removeItem(at: url) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "Errore di registrazione del microfono."
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.isRecording, self.recorder?.url == url else { return }
            _ = self.stop(); self.onFailure?(message)
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.isRecording, self.recorder?.url == url else { return }
            _ = self.stop()
            self.onFailure?(flag ? "La registrazione si è fermata. Il file audio è conservato nell’archivio Registrazioni." : "Registrazione interrotta dal dispositivo. Controlla il microfono e il file nell’archivio Registrazioni.")
        }
    }
}
