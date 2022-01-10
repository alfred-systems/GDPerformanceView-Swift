//
// Copyright © 2017 Gavrilov Daniil
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import QuartzCore
import UIKit

// MARK: Class Definition

/// Performance calculator. Uses CADisplayLink to count FPS. Also counts CPU and memory usage.
internal class PerformanceCalculator {
    
    // MARK: Structs
    
    private struct Constants {
        static let accumulationTimeInSeconds = 1.0
    }
    
    // MARK: Internal Properties
    
    internal var onReport: ((_ performanceReport: PerformanceReport) -> ())?
    
    internal var onReportV2: ((_ performanceReport: PerformanceReportV2) -> ())?
    
    // MARK: Private Properties
    
    private var displayLink: CADisplayLink!
    private let linkedFramesList = LinkedFramesList()
    private var startTimestamp: TimeInterval?
    private var previousGetInfoTimestamp: TimeInterval?
    private var previousLogInfoTimestamp: TimeInterval?
    private var accumulatedInformationIsEnough = false
    
    private var reportCount = 0
    private(set) var cpuAvgUsage: Double = 0
    private(set) var memoryAvgUsage: UInt64 = 0
    
    private var lastCpuReport: CpuReport?
    private var lastMemoryReport: MemoryReport?
    
    lazy private var batteryLogger: FileLogger = {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let documentsURL = URL(fileURLWithPath: documents)
        let fileURL = documentsURL.appendingPathComponent("battery.log")
        return FileLogger(with: fileURL)
    }()
    
    lazy private var thermalLogger: FileLogger = {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let documentsURL = URL(fileURLWithPath: documents)
        let fileURL = documentsURL.appendingPathComponent("thermal.log")
        return FileLogger(with: fileURL)
    }()
    
    // MARK: Init Methods & Superclass Overriders
    
    required internal init() {
        self.configureDisplayLink()
    }
}

// MARK: Public Methods

internal extension PerformanceCalculator {
    /// Starts performance monitoring.
    func start() {
        self.startTimestamp = Date().timeIntervalSince1970
        self.displayLink?.isPaused = false
    }
    
    /// Pauses performance monitoring.
    func pause() {
        self.displayLink?.isPaused = true
        self.startTimestamp = nil
        self.accumulatedInformationIsEnough = false
    }
}

// MARK: Timer Actions

private extension PerformanceCalculator {
    @objc func displayLinkAction(displayLink: CADisplayLink) {
        self.linkedFramesList.append(frameWithTimestamp: displayLink.timestamp)
        self.takePerformanceEvidence()
    }
}

// MARK: Monitoring

private extension PerformanceCalculator {
    func takePerformanceEvidence() {
        if self.accumulatedInformationIsEnough, Date().timeIntervalSince1970 - (previousLogInfoTimestamp ?? 0.0) >= 60.0 {
            previousLogInfoTimestamp = Date().timeIntervalSince1970
            batteryLogger.log(String(Int32(UIDevice.current.batteryLevel * 100)))
            if #available(iOS 11.0, *) {
                thermalLogger.log(String(ProcessInfo.processInfo.thermalState.rawValue))
            }
        }
        
        if self.accumulatedInformationIsEnough, Date().timeIntervalSince1970 - (previousGetInfoTimestamp ?? 0.0) >= Constants.accumulationTimeInSeconds {
            let cpuUsage = self.cpuUsage()
            let fps = self.linkedFramesList.count
            let memoryUsage = self.memoryUsage()
            self.report(cpuUsage: cpuUsage, fps: fps, memoryUsage: memoryUsage)
            previousGetInfoTimestamp = Date().timeIntervalSince1970

            let cpuReport = genCpuReport()
            let memReport = genMemoryReport()
            lastCpuReport = cpuReport
            lastMemoryReport = memReport
            reportCount += 1
            self.reportV2(cpuReport: cpuReport, fps: fps, memoryReport: memReport)
        } else if let start = self.startTimestamp, Date().timeIntervalSince1970 - start >= Constants.accumulationTimeInSeconds {
            self.accumulatedInformationIsEnough = true
        }
    }
    
    func genCpuReport() -> CpuReport {
        let cpuUsage = self.cpuUsage()
        let max = max(lastCpuReport?.max ?? 0, cpuUsage)
        let min = min(lastCpuReport?.min ?? Double.infinity, cpuUsage)
        let avg = ((lastCpuReport?.average ?? 0) * Double(reportCount) + cpuUsage) / Double(reportCount + 1)
        
        return CpuReport(usage: cpuUsage, average: avg, max: max, min: min)
    }
    
    func genMemoryReport() -> MemoryReport {
        let memoryUsage = self.memoryUsage()
        let max = max(lastMemoryReport?.max ?? 0, Double(memoryUsage.used))
        let min = min(lastMemoryReport?.min ?? Double.infinity, Double(memoryUsage.used))
        let avg = ((lastMemoryReport?.average ?? 0) * Double(reportCount) + Double(memoryUsage.used)) / Double(reportCount + 1)
        
        return MemoryReport(usage: memoryUsage, average: avg, max: max, min: min)
    }
    
    func cpuUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else {
                    break
                }
                
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                }
            }
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        return totalUsageOfCPU
    }
    
    func memoryUsage() -> MemoryUsage {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            used = UInt64(taskInfo.phys_footprint)
        }
        
        let total = ProcessInfo.processInfo.physicalMemory
        return (used, total)
    }
}

// MARK: Configurations

private extension PerformanceCalculator {
    func configureDisplayLink() {
        self.displayLink = CADisplayLink(target: self, selector: #selector(PerformanceCalculator.displayLinkAction(displayLink:)))
        self.displayLink.isPaused = true
        self.displayLink?.add(to: .current, forMode: .common)
    }
}

// MARK: Support Methods

private extension PerformanceCalculator {
    func report(cpuUsage: Double, fps: Int, memoryUsage: MemoryUsage) {
        let performanceReport = (cpuUsage: cpuUsage, fps: fps, memoryUsage: memoryUsage)
        self.onReport?(performanceReport)
    }
    
    func reportV2(cpuReport: CpuReport, fps: Int, memoryReport: MemoryReport) {
        if #available(iOS 11.0, *) {
            let performanceReport = (cpuReport: cpuReport, fps: fps, memoryReport: memoryReport, thermalReport: ThermalReport(state: ProcessInfo.processInfo.thermalState.toState()))
            self.onReportV2?(performanceReport)
        } else {
            let performanceReport = (cpuReport: cpuReport, fps: fps, memoryReport: memoryReport, thermalReport: ThermalReport(state: .unsupported))
            self.onReportV2?(performanceReport)
        }
    }
}

@available(iOS 11.0, *)
private extension ProcessInfo.ThermalState {
    func toState() -> ThermalReport.state {
        switch self {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        }
    }
}
