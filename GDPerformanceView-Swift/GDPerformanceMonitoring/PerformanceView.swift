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

import UIKit

// MARK: Class Definition

/// Performance view. Displays performance information above status bar. Appearance and output can be changed via properties.
internal class PerformanceView: UIWindow, PerformanceViewConfigurator {
    
    // MARK: Structs
    
    private struct Constants {
        static let prefferedHeight: CGFloat = 20.0
        static let borderWidth: CGFloat = 1.0
        static let cornerRadius: CGFloat = 5.0
        static let pointSize: CGFloat = 8.0
        static let defaultStatusBarHeight: CGFloat = 20.0
        static let safeAreaInsetDifference: CGFloat = 11.0
    }
    
    // MARK: Public Properties
    
    /// Allows to change the format of the displayed information.
    public var options = PerformanceMonitor.DisplayOptions.default {
        didSet {
            self.configureStaticInformation()
        }
    }
    
    public var userInfo = PerformanceMonitor.UserInfo.none {
        didSet {
            self.configureUserInformation()
        }
    }
    
    /// Allows to change the appearance of the displayed information.
    public var style = PerformanceMonitor.Style.dark {
        didSet {
            self.configureView(withStyle: self.style)
        }
    }
    
    /// Allows to add gesture recognizers to the view.
    public var interactors: [UIGestureRecognizer]? {
        didSet {
            self.configureView(withInteractors: self.interactors)
        }
    }
    
    // MARK: Private Properties
    
    private var memoryTuple = (min: Double.infinity, max: 0.0)
    private var cpuTuple = (min: Double.infinity, max: 0.0)
    private let monitoringTextLabel = MarginLabel()
    private var staticInformation: String?
    private var userInformation: String?
    private lazy var panGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        addGestureRecognizer(gesture)
        return gesture
    }()
    private var dragged = false
    
    // MARK: Init Methods & Superclass Overriders
    
    required internal init() {
        super.init(frame: PerformanceView.windowFrame(withPrefferedHeight: Constants.prefferedHeight))
        if #available(iOS 13, *) {
            self.windowScene = PerformanceView.keyWindowScene()
        }
        
        self.configureWindow()
        self.configureMonitoringTextLabel()
        self.subscribeToNotifications()
        
        interactors = [panGesture]
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.layoutWindow()
    }
    
    override func becomeKey() {
        self.isHidden = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.showViewAboveStatusBarIfNeeded()
        }
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let interactors = self.interactors, interactors.count > 0 else {
            return false
        }
        return super.point(inside: point, with: event)
    }
    
    
    @objc private func dragged(_ sender:UIPanGestureRecognizer){
        dragged = true
        let translation = sender.translation(in: self)
        self.center = CGPoint(x: self.center.x + translation.x, y: self.center.y + translation.y)
        sender.setTranslation(CGPoint.zero, in: self)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: Public Methods

internal extension PerformanceView {
    /// Hides monitoring view.
    func hide() {
        self.monitoringTextLabel.isHidden = true
    }
    
    /// Shows monitoring view.
    func show() {
        self.monitoringTextLabel.isHidden = false
    }
    
    func update(withPerformanceReport report: PerformanceReportV2) {
        var monitoringTexts: [String] = []
        if self.options.contains(.performance) {
            monitoringTexts.append("------- CPU -------")
            let performance = String(format: "Current: %.1f%%", report.cpuReport.usage)
            monitoringTexts.append(performance)
            
            monitoringTexts.append(String(format: "Max: %.1f%%", report.cpuReport.max))
            monitoringTexts.append(String(format: "Min: %.1f%%", report.cpuReport.min))
            monitoringTexts.append(String(format: "Avg: %.1f%%", report.cpuReport.average))
        }
        
        if self.options.contains(.memory) {
            monitoringTexts.append("----- Memory ------")
            let bytesInMegabyte = 1024.0 * 1024.0
            let usedMemory = Double(report.memoryReport.usage.used) / bytesInMegabyte
            let totalMemory = Double(report.memoryReport.usage.total) / bytesInMegabyte
            let memory = String(format: "%.1f of %.0f MB used", usedMemory, totalMemory)
            monitoringTexts.append(memory)
            
            monitoringTexts.append(String(format: "Max: %.1f MB", report.memoryReport.max / bytesInMegabyte))
            monitoringTexts.append(String(format: "Min: %.1f MB", report.memoryReport.min / bytesInMegabyte))
            monitoringTexts.append(String(format: "Avg: %.1f MB", report.memoryReport.average / bytesInMegabyte))
        }
        
        monitoringTexts.append("----- Thermal -----")
        monitoringTexts.append(report.thermalReport.state.toString())
        
        if let staticInformation = self.staticInformation {
            monitoringTexts.append("-------------------")
            monitoringTexts.append(staticInformation)
        }
        
        if let userInformation = self.userInformation {
            monitoringTexts.append("-------------------")
            monitoringTexts.append(userInformation)
        }
        
        monitoringTexts.append("-------------------")
        self.monitoringTextLabel.font = UIFont(name: "HelveticaNeue-Bold", size: 13)
        self.monitoringTextLabel.text = (monitoringTexts.count > 0 ? monitoringTexts.joined(separator: "\n") : nil)
        self.showViewAboveStatusBarIfNeeded()
        self.layoutMonitoringLabel()
    }
    
    /// Updates monitoring label with performance report.
    ///
    /// - Parameter report: Performance report.
    func update(withPerformanceReport report: PerformanceReport) {
        var monitoringTexts: [String] = []
        if self.options.contains(.performance) {
            monitoringTexts.append("------- CPU -------")
            let performance = String(format: "Current: %.1f%%", report.cpuUsage)
            monitoringTexts.append(performance)
            
            cpuTuple.min = min(cpuTuple.min, report.cpuUsage)
            cpuTuple.max = max(cpuTuple.max, report.cpuUsage)
            monitoringTexts.append(String(format: "Max: %.1f%%", cpuTuple.max))
            monitoringTexts.append(String(format: "Min: %.1f%%", cpuTuple.min))
        }
        
        if self.options.contains(.memory) {
            monitoringTexts.append("----- Memory ------")
            let bytesInMegabyte = 1024.0 * 1024.0
            let usedMemory = Double(report.memoryUsage.used) / bytesInMegabyte
            let totalMemory = Double(report.memoryUsage.total) / bytesInMegabyte
            let memory = String(format: "%.1f of %.0f MB used", usedMemory, totalMemory)
            monitoringTexts.append(memory)
            
            memoryTuple.min = min(memoryTuple.min, usedMemory)
            memoryTuple.max = max(memoryTuple.max, usedMemory)
            
            let maxMemoryString = String(format: "Max: %.1f MB", memoryTuple.max)
            let minMemoryString = String(format: "Min: %.1f MB", memoryTuple.min)
            monitoringTexts.append(maxMemoryString)
            monitoringTexts.append(minMemoryString)
        }
        
        if let staticInformation = self.staticInformation {
            monitoringTexts.append("-------------------")
            monitoringTexts.append(staticInformation)
        }
        
        if let userInformation = self.userInformation {
            monitoringTexts.append("-------------------")
            monitoringTexts.append(userInformation)
        }
        monitoringTexts.append("-------------------")
        
        self.monitoringTextLabel.font = UIFont(name: "HelveticaNeue-Bold", size: 13)
        self.monitoringTextLabel.text = (monitoringTexts.count > 0 ? monitoringTexts.joined(separator: "\n") : nil)
        self.showViewAboveStatusBarIfNeeded()
        self.layoutMonitoringLabel()
    }
}

// MARK: Notifications & Observers

private extension PerformanceView {
    func applicationWillChangeStatusBarFrame(notification: Notification) {
        self.layoutWindow()
    }
}

// MARK: Configurations

private extension PerformanceView {
    func configureWindow() {
        self.rootViewController = WindowViewController()
        self.windowLevel = UIWindow.Level.statusBar + 1.0
        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.isHidden = true
    }
    
    func configureMonitoringTextLabel() {
        self.monitoringTextLabel.textAlignment = NSTextAlignment.center
        self.monitoringTextLabel.numberOfLines = 0
        self.monitoringTextLabel.clipsToBounds = true
        self.addSubview(self.monitoringTextLabel)
    }
    
    func configureStaticInformation() {
        var staticInformations: [String] = []
        if self.options.contains(.application) {
            let applicationVersion = self.applicationVersion()
            staticInformations.append(applicationVersion)
        }
        if self.options.contains(.device) {
            let deviceModel = self.deviceModel()
            staticInformations.append(deviceModel)
        }
        if self.options.contains(.system) {
            let systemVersion = self.systemVersion()
            staticInformations.append(systemVersion)
        }
        
        self.staticInformation = (staticInformations.count > 0 ? staticInformations.joined(separator: ", ") : nil)
    }
    
    func configureUserInformation() {
        var staticInformation: String?
        switch self.userInfo {
        case .none:
            break
        case .custom(let string):
            staticInformation = string
        }
        
        self.userInformation = staticInformation
    }
    
    func subscribeToNotifications() {
        NotificationCenter.default.addObserver(forName: UIApplication.willChangeStatusBarFrameNotification, object: nil, queue: .main) { [weak self] (notification) in
            self?.applicationWillChangeStatusBarFrame(notification: notification)
        }
    }
    
    func configureView(withStyle style: PerformanceMonitor.Style) {
        switch style {
        case .dark:
            self.monitoringTextLabel.backgroundColor = .black
            self.monitoringTextLabel.layer.borderColor = UIColor.white.cgColor
            self.monitoringTextLabel.layer.borderWidth = Constants.borderWidth
            self.monitoringTextLabel.layer.cornerRadius = Constants.cornerRadius
            self.monitoringTextLabel.textColor = .white
            self.monitoringTextLabel.font = UIFont.systemFont(ofSize: Constants.pointSize)
        case .light:
            self.monitoringTextLabel.backgroundColor = .white
            self.monitoringTextLabel.layer.borderColor = UIColor.black.cgColor
            self.monitoringTextLabel.layer.borderWidth = Constants.borderWidth
            self.monitoringTextLabel.layer.cornerRadius = Constants.cornerRadius
            self.monitoringTextLabel.textColor = .black
            self.monitoringTextLabel.font = UIFont.systemFont(ofSize: Constants.pointSize)
        case .custom(let backgroundColor, let borderColor, let borderWidth, let cornerRadius, let textColor, let font):
            self.monitoringTextLabel.backgroundColor = backgroundColor
            self.monitoringTextLabel.layer.borderColor = borderColor.cgColor
            self.monitoringTextLabel.layer.borderWidth = borderWidth
            self.monitoringTextLabel.layer.cornerRadius = cornerRadius
            self.monitoringTextLabel.textColor = textColor
            self.monitoringTextLabel.font = font
        }
    }
    
    func configureView(withInteractors interactors: [UIGestureRecognizer]?) {
        if let recognizers = self.gestureRecognizers {
            for recognizer in recognizers {
                self.removeGestureRecognizer(recognizer)
            }
        }
        
        if let recognizers = interactors {
            for recognizer in recognizers {
                self.addGestureRecognizer(recognizer)
            }
        }
    }
}

// MARK: Layout View

private extension PerformanceView {
    func layoutWindow() {
        if !dragged {
            self.frame = PerformanceView.windowFrame(withPrefferedHeight: self.monitoringTextLabel.bounds.height)
        }
        self.layoutMonitoringLabel()
    }
    
    func layoutMonitoringLabel() {
        let windowWidth = self.bounds.width
        let windowHeight = self.bounds.height
        let labelSize = self.monitoringTextLabel.sizeThatFits(CGSize(width: windowWidth, height: CGFloat.greatestFiniteMagnitude))
        
        if windowHeight != labelSize.height {
            self.frame = PerformanceView.windowFrame(withPrefferedHeight: self.monitoringTextLabel.bounds.height)
        }
        
        self.monitoringTextLabel.frame = CGRect(x: (windowWidth - labelSize.width) / 2.0, y: (windowHeight - labelSize.height) / 2.0, width: labelSize.width, height: labelSize.height)
    }
}

// MARK: Support Methods

private extension PerformanceView {
    func showViewAboveStatusBarIfNeeded() {
        guard UIApplication.shared.applicationState == UIApplication.State.active, self.canBeVisible(), self.isHidden else {
            return
        }
        self.isHidden = false
    }
    
    func applicationVersion() -> String {
        var applicationVersion = "<null>"
        var applicationBuildNumber = "<null>"
        if let infoDictionary = Bundle.main.infoDictionary {
            if let versionNumber = infoDictionary["CFBundleShortVersionString"] as? String {
                applicationVersion = versionNumber
            }
            if let buildNumber = infoDictionary["CFBundleVersion"] as? String {
                applicationBuildNumber = buildNumber
            }
        }
        return "app v\(applicationVersion) (\(applicationBuildNumber))"
    }
    
    func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let model = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else {
                return identifier
            }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return model
    }
    
    func systemVersion() -> String {
        let systemName = UIDevice.current.systemName
        let systemVersion = UIDevice.current.systemVersion
        return "\(systemName) v\(systemVersion)"
    }
    
    func canBeVisible() -> Bool {
        if let window = PerformanceView.keyWindow(), window.isKeyWindow, !window.isHidden {
            return true
        }
        return false
    }
}

// MARK: Class Methods

private extension PerformanceView {
    class func windowFrame(withPrefferedHeight height: CGFloat) -> CGRect {
        guard let window = PerformanceView.keyWindow() else {
            return .zero
        }
        
        return CGRect(x: 0.0, y: 100.0, width: window.bounds.width, height: height)
    }

    class func keyWindow() -> UIWindow? {
        if #available(iOS 13, *) {
            return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        } else {
            return UIApplication.shared.keyWindow
        }
    }
    
    @available(iOS 13, *)
    class func keyWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first as? UIWindowScene
    }
}

private extension ThermalReport.state {
    func toString() -> String {
        switch self {
        case .unsupported:
            return "Unsupported"
        case .nominal:
            return "Normal"
        case .fair:
            return "Slightly elevated"
        case .serious:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}
