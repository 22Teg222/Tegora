import Darwin
import Foundation

/// Read-only memory metrics from the kernel, used by Smart Care's overview.
enum MemoryService {
    static func snapshot() -> MemorySnapshot? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Int64(pageSize)

        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let purgeable = Int64(stats.purgeable_count) * page
        let external = Int64(stats.external_page_count) * page
        let internalPages = Int64(stats.internal_page_count) * page
        let app = max(internalPages - purgeable, 0)

        // Same breakdown Activity Monitor uses: App Memory + Wired + Compressed.
        let used = min(app + wired + compressed, total)
        return MemorySnapshot(total: total, used: used, available: max(total - used, 0),
                              app: app, wired: wired, compressed: compressed, cached: external + purgeable)
    }
}
