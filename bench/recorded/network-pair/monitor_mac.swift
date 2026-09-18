// Read-only macOS thermal pressure and host CPU counters, sampled every 2 s.
// Thermal pressure is an OS classification, not a temperature measurement.
import Foundation
import Darwin

let seconds = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 1800
for _ in 0..<(seconds / 2) {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    var row: [String: Any] = [
        "unix_seconds": Date().timeIntervalSince1970,
        "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
        "thermal_legend": "0 nominal, 1 fair, 2 serious, 3 critical"
    ]
    if status == KERN_SUCCESS {
        row["cpu_ticks"] = ["user": info.cpu_ticks.0, "system": info.cpu_ticks.1,
                            "idle": info.cpu_ticks.2, "nice": info.cpu_ticks.3]
    }
    let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    fflush(stdout)
    sleep(2)
}
