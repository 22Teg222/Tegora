import Foundation
import SwiftUI

@MainActor
final class SmartCareModel: ObservableObject {
    @Published var phase: ScanPhase = .idle
    @Published var progress = 0.0
    @Published var report: SmartCareReport?
    @Published var disk: DiskInfo? = StorageService.startupDisk()
    @Published var memory: MemorySnapshot? = MemoryService.snapshot()
    @Published var lastCleanReport: OperationReport?

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool { if case .running = phase { return true } else { return false } }

    func refreshLive() {
        disk = StorageService.startupDisk()
        memory = MemoryService.snapshot()
    }

    func startScan() {
        guard !isScanning else { return }
        phase = .running("Starting…")
        progress = 0
        report = nil
        lastCleanReport = nil
        scanTask = Task {
            let result = await ScanService.runSmartScan { [weak self] label, fraction in
                Task { @MainActor in
                    self?.phase = .running(label)
                    self?.progress = fraction
                }
            }
            guard !Task.isCancelled else { return }
            report = result
            disk = result.disk ?? disk
            memory = result.memory ?? memory
            phase = .finished
            progress = 1
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        phase = .idle
        progress = 0
    }

    /// Removes the reviewed results, then rescans so the numbers on screen are real.
    func clean(_ items: [FoundItem], category: CleanupCategory) -> OperationReport {
        CleanupService.remove(items, category: category)
    }
}
