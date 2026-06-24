import AppKit
import FlutterMacOS
import NetworkExtension
import SystemExtensions

public class VpnServicePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let channel: FlutterMethodChannel
  private let stateChannel: FlutterEventChannel
  private var stateSink: FlutterEventSink?
  private let handler = VpnServiceHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let channel = FlutterMethodChannel(name: "vpn_service", binaryMessenger: messenger)
    let stateChannel = FlutterEventChannel(
      name: "vpn_service_plugin_states",
      binaryMessenger: messenger
    )
    let instance = VpnServicePlugin(channel: channel, stateChannel: stateChannel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    stateChannel.setStreamHandler(instance)
  }

  init(channel: FlutterMethodChannel, stateChannel: FlutterEventChannel) {
    self.channel = channel
    self.stateChannel = stateChannel
    super.init()
    handler.onStateChanged = { [weak self] state in
      self?.emitState(state)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSystemVersion":
      result(ProcessInfo.processInfo.operatingSystemVersionString)
    case "getABIs":
      result("[\"macos\"]")
    case "getAppGroupDirectory":
      guard let args = call.arguments as? [String: Any],
            let groupId = args["groupId"] as? String,
            !groupId.isEmpty else {
        result("")
        return
      }
      result(appGroupDirectory(groupId: groupId))
    case "prepareConfig":
      do {
        try handler.prepare(arguments: call.arguments as? [String: Any])
        result(nil)
      } catch {
        result(FlutterError(code: "prepareConfig", message: error.localizedDescription, details: nil))
      }
    case "installService":
      handler.installService { result(errorResult($0)) }
    case "uninstallService":
      handler.uninstallService { result(errorResult($0)) }
    case "currentState":
      handler.currentState { result($0.rawValue) }
    case "start":
      let timeout = timeout(from: call.arguments)
      handler.start(timeout: timeout) { result(waitResult($0)) }
    case "restart":
      let timeout = timeout(from: call.arguments)
      handler.restart(timeout: timeout) { result(waitResult($0)) }
    case "stop":
      handler.stop()
      result(nil)
    case "setAlwaysOn":
      result(nil)
    case "setSystemProxy", "cleanSystemProxy":
      result(nil)
    case "getSystemProxyEnable":
      result(false)
    case "isRunAsAdmin":
      result(false)
    case "isServiceAuthorized":
      result(true)
    case "authorizeService":
      result(nil)
    case "hideDockIcon":
      if let args = call.arguments as? [String: Any], args["hide"] as? Bool == true {
        NSApp.setActivationPolicy(.accessory)
      } else {
        NSApp.setActivationPolicy(.regular)
      }
      result(nil)
    case "getProcessList":
      result(nil)
    case "getProcessIcon":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stateSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stateSink = nil
    return nil
  }

  private func emitState(_ state: VpnServiceState) {
    let event: [String: Any] = [
      "state": state.rawValue,
      "params": [:] as [String: String],
    ]
    stateSink?(event)
    channel.invokeMethod("stateChanged", arguments: event)
  }

  private func appGroupDirectory(groupId: String) -> String {
    if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) {
      return url.path
    }
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    let fallback = appSupport?
      .appendingPathComponent("Karing", isDirectory: true)
      .path ?? NSTemporaryDirectory()
    try? FileManager.default.createDirectory(
      atPath: fallback,
      withIntermediateDirectories: true,
      attributes: nil
    )
    return fallback
  }
}

private enum VpnServiceState: String {
  case invalid
  case disconnected
  case connecting
  case connected
  case reasserting
  case disconnecting
}

private enum VpnServiceWaitType: String {
  case done
  case error
  case timeout
}

private struct VpnServiceWaitResult {
  let type: VpnServiceWaitType
  let message: String?

  static func done() -> VpnServiceWaitResult {
    VpnServiceWaitResult(type: .done, message: nil)
  }

  static func error(_ message: String) -> VpnServiceWaitResult {
    VpnServiceWaitResult(type: .error, message: message)
  }

  static func timeout(_ message: String) -> VpnServiceWaitResult {
    VpnServiceWaitResult(type: .timeout, message: message)
  }
}

private func waitResult(_ value: VpnServiceWaitResult) -> [String: Any] {
  var result: [String: Any] = ["type": value.type.rawValue]
  if let message = value.message, !message.isEmpty {
    result["err"] = ["message": message, "is_close_error": false]
  }
  return result
}

private func errorResult(_ message: String?) -> [String: Any]? {
  guard let message, !message.isEmpty else {
    return nil
  }
  return ["message": message, "is_close_error": false]
}

private func timeout(from arguments: Any?) -> TimeInterval {
  let args = arguments as? [String: Any]
  if let millis = args?["timeoutMillis"] as? NSNumber {
    return max(1, millis.doubleValue / 1000.0)
  }
  return 20
}

private final class VpnServiceConfig {
  let raw: [String: Any]
  let controlPort: Int
  let baseDir: String
  let corePath: String
  let errPath: String
  let logPath: String
  let secret: String

  init(raw: [String: Any]) {
    self.raw = raw
    controlPort = (raw["control_port"] as? NSNumber)?.intValue ?? 0
    baseDir = raw["base_dir"] as? String ?? ""
    corePath = raw["core_path"] as? String ?? ""
    errPath = raw["err_path"] as? String ?? ""
    logPath = raw["log_path"] as? String ?? ""
    secret = raw["secret"] as? String ?? ""
  }

  func validate(configFilePath: String, requireCore: Bool) throws {
    if requireCore {
      try requireReadableFile(corePath, label: "core config")
    }
    try requireReadableFile(configFilePath, label: "runtime config")
    if !baseDir.isEmpty {
      var isDirectory: ObjCBool = false
      if !FileManager.default.fileExists(atPath: baseDir, isDirectory: &isDirectory) {
        try FileManager.default.createDirectory(
          atPath: baseDir,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }
      if !FileManager.default.fileExists(atPath: baseDir, isDirectory: &isDirectory) || !isDirectory.boolValue {
        throw VpnServiceError.message("base directory is not a directory: \(baseDir)")
      }
      let probe = URL(fileURLWithPath: baseDir).appendingPathComponent(".vpn_service_write_test")
      do {
        try "ok".write(to: probe, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: probe)
      } catch {
        throw VpnServiceError.message("base directory is not writable: \(baseDir): \(error.localizedDescription)")
      }
    }
    try ensureParentDirectory(path: errPath, label: "error file")
    try ensureParentDirectory(path: logPath, label: "log file")
  }

  private func requireReadableFile(_ path: String, label: String) throws {
    if path.isEmpty {
      throw VpnServiceError.message("\(label) path is empty")
    }
    guard FileManager.default.fileExists(atPath: path) else {
      throw VpnServiceError.message("\(label) not found: \(path)")
    }
    guard FileManager.default.isReadableFile(atPath: path) else {
      throw VpnServiceError.message("\(label) is not readable: \(path)")
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
    if size == 0 {
      throw VpnServiceError.message("\(label) is empty: \(path)")
    }
  }

  private func ensureParentDirectory(path: String, label: String) throws {
    if path.isEmpty {
      return
    }
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    if !FileManager.default.fileExists(atPath: parent) {
      do {
        try FileManager.default.createDirectory(
          atPath: parent,
          withIntermediateDirectories: true,
          attributes: nil
        )
      } catch {
        throw VpnServiceError.message(
          "\(label) parent directory not created: \(parent): \(error.localizedDescription)"
        )
      }
    }
  }
}

private enum VpnServiceError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let value):
      return value
    }
  }
}

private final class VpnServiceHandler {
  private var config: VpnServiceConfig?
  private var tunnelServicePath = ""
  private var configFilePath = ""
  private var systemExtension = true
  private var bundleIdentifier = ""
  private var uiServerAddress = "Karing"
  private var uiLocalizedDescription = "Karing"
  private var excludePorts: [Int] = []
  private var manager: NETunnelProviderManager?
  private var lastState = VpnServiceState.disconnected
  var onStateChanged: ((VpnServiceState) -> Void)?

  func prepare(arguments: [String: Any]?) throws {
    guard let arguments else {
      throw VpnServiceError.message("missing prepareConfig arguments")
    }
    guard let configJson = arguments["config"] as? [String: Any] else {
      throw VpnServiceError.message("missing service config")
    }
    let nextConfig = VpnServiceConfig(raw: configJson)
    let nextConfigFilePath = arguments["configFilePath"] as? String ?? ""
    try nextConfig.validate(configFilePath: nextConfigFilePath, requireCore: false)
    config = nextConfig
    tunnelServicePath = arguments["tunnelServicePath"] as? String ?? ""
    configFilePath = nextConfigFilePath
    systemExtension = arguments["systemExtension"] as? Bool ?? true
    bundleIdentifier = arguments["bundleIdentifier"] as? String ?? ""
    uiServerAddress = arguments["uiServerAddress"] as? String ?? "Karing"
    uiLocalizedDescription = arguments["uiLocalizedDescription"] as? String ?? "Karing"
    excludePorts = (arguments["excludePorts"] as? [Int]) ?? []
  }

  func installService(completion: @escaping (String?) -> Void) {
    guard systemExtension else {
      completion(nil)
      return
    }
    guard !bundleIdentifier.isEmpty else {
      completion("bundleIdentifier is empty")
      return
    }
    SystemExtension.install(bundleIdentifier: bundleIdentifier) { error in
      if let error {
        completion("install systemextension failed: \(error.localizedDescription)")
      } else {
        completion(nil)
      }
    }
  }

  func uninstallService(completion: @escaping (String?) -> Void) {
    guard systemExtension, !bundleIdentifier.isEmpty else {
      completion(nil)
      return
    }
    SystemExtension.uninstall(bundleIdentifier: bundleIdentifier) { error in
      if let error {
        completion("uninstall systemextension failed: \(error.localizedDescription)")
      } else {
        completion(nil)
      }
    }
  }

  func currentState(completion: @escaping (VpnServiceState) -> Void) {
    loadManager { [weak self] manager, _ in
      guard let self else {
        completion(.disconnected)
        return
      }
      let state = self.mapStatus(manager?.connection.status)
      self.lastState = state
      completion(state)
    }
  }

  func start(timeout: TimeInterval, completion: @escaping (VpnServiceWaitResult) -> Void) {
    do {
      guard let config else {
        completion(.error("service config is not ready"))
        return
      }
      try config.validate(configFilePath: configFilePath, requireCore: true)
    } catch {
      completion(.error(error.localizedDescription))
      return
    }
    emit(.connecting)
    ensureSystemExtensionInstalled { [weak self] installError in
      guard let self else {
        completion(.error("vpn handler released"))
        return
      }
      if let installError {
        self.emit(.disconnected)
        completion(.error(installError))
        return
      }
      self.startPreparedTunnel(timeout: timeout, completion: completion)
    }
  }

  private func ensureSystemExtensionInstalled(completion: @escaping (String?) -> Void) {
    guard systemExtension else {
      completion(nil)
      return
    }
    guard !bundleIdentifier.isEmpty else {
      completion("bundleIdentifier is empty")
      return
    }
    SystemExtension.install(bundleIdentifier: bundleIdentifier) { error in
      if let error {
        completion("install systemextension failed: \(error.localizedDescription)")
      } else {
        completion(nil)
      }
    }
  }

  private func startPreparedTunnel(
    timeout: TimeInterval,
    completion: @escaping (VpnServiceWaitResult) -> Void
  ) {
    loadManager { [weak self] manager, error in
      guard let self else {
        completion(.error("vpn handler released"))
        return
      }
      if let error {
        self.emit(.disconnected)
        completion(.error(error.localizedDescription))
        return
      }
      guard let manager else {
        self.emit(.disconnected)
        completion(.error("NETunnelProviderManager not created"))
        return
      }
      self.manager = manager
      self.configure(manager)
      manager.saveToPreferences { saveError in
        if let saveError {
          self.emit(.disconnected)
          completion(.error("save vpn preferences failed: \(saveError.localizedDescription)"))
          return
        }
        manager.loadFromPreferences { loadError in
          if let loadError {
            self.emit(.disconnected)
            completion(.error("load vpn preferences failed: \(loadError.localizedDescription)"))
            return
          }
          do {
            try manager.connection.startVPNTunnel(options: self.startOptions())
          } catch {
            self.emit(.disconnected)
            completion(.error("start vpn failed: \(error.localizedDescription)"))
            return
          }
          self.waitUntilReady(manager: manager, timeout: timeout, completion: completion)
        }
      }
    }
  }

  func restart(timeout: TimeInterval, completion: @escaping (VpnServiceWaitResult) -> Void) {
    stop()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.start(timeout: timeout, completion: completion)
    }
  }

  func stop() {
    manager?.connection.stopVPNTunnel()
    emit(.disconnected)
  }

  private func loadManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      if let error {
        completion(nil, error)
        return
      }
      guard let self else {
        completion(nil, VpnServiceError.message("vpn handler released"))
        return
      }
      if let existing = managers?.first(where: { manager in
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
          return false
        }
        return proto.providerBundleIdentifier == self.bundleIdentifier ||
          proto.serverAddress == self.uiServerAddress
      }) {
        completion(existing, nil)
        return
      }
      completion(NETunnelProviderManager(), nil)
    }
  }

  private func configure(_ manager: NETunnelProviderManager) {
    let proto = NETunnelProviderProtocol()
    proto.providerBundleIdentifier = bundleIdentifier
    proto.serverAddress = uiServerAddress
    proto.providerConfiguration = providerConfiguration()
    manager.localizedDescription = uiLocalizedDescription
    manager.protocolConfiguration = proto
    manager.isEnabled = true
    manager.isOnDemandEnabled = false
  }

  private func providerConfiguration() -> [String: Any] {
    var provider: [String: Any] = [
      "configFilePath": configFilePath,
      "systemExtension": systemExtension,
      "bundleIdentifier": bundleIdentifier,
      "uiServerAddress": uiServerAddress,
      "uiLocalizedDescription": uiLocalizedDescription,
      "excludePorts": excludePorts,
    ]
    if !tunnelServicePath.isEmpty {
      provider["tunnelServicePath"] = tunnelServicePath
    }
    if let config {
      for (key, value) in config.raw {
        provider[key] = value
      }
      provider["config"] = config.raw
    }
    return provider
  }

  private func startOptions() -> [String: NSObject] {
    [
      "configFilePath": configFilePath as NSString,
      "corePath": (config?.corePath ?? "") as NSString,
      "baseDir": (config?.baseDir ?? "") as NSString,
    ]
  }

  private func waitUntilReady(
    manager: NETunnelProviderManager,
    timeout: TimeInterval,
    completion: @escaping (VpnServiceWaitResult) -> Void
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    func poll() {
      let state = mapStatus(manager.connection.status)
      emit(state)
      if state == .connected {
        completion(.done())
        return
      }
      if state == .disconnected || state == .invalid {
        completion(.error("startVPNTunnel status: \(manager.connection.status.rawValue)"))
        return
      }
      if Date() >= deadline {
        completion(.timeout("startVPNTunnel timeout"))
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: poll)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: poll)
  }

  private func mapStatus(_ status: NEVPNStatus?) -> VpnServiceState {
    switch status {
    case .connected:
      return .connected
    case .connecting:
      return .connecting
    case .disconnecting:
      return .disconnecting
    case .reasserting:
      return .reasserting
    case .disconnected, .none:
      return .disconnected
    case .invalid:
      return .invalid
    @unknown default:
      return lastState
    }
  }

  private func emit(_ state: VpnServiceState) {
    if lastState == state {
      return
    }
    lastState = state
    DispatchQueue.main.async {
      self.onStateChanged?(state)
    }
  }
}

private final class SystemExtension: NSObject, OSSystemExtensionRequestDelegate {
  private static var activeRequests: [SystemExtension] = []
  private var completion: ((Error?) -> Void)?

  static func install(bundleIdentifier: String, completion: @escaping (Error?) -> Void) {
    let delegate = SystemExtension()
    delegate.submit(bundleIdentifier: bundleIdentifier, uninstall: false, completion: completion)
  }

  static func uninstall(bundleIdentifier: String, completion: @escaping (Error?) -> Void) {
    let delegate = SystemExtension()
    delegate.submit(bundleIdentifier: bundleIdentifier, uninstall: true, completion: completion)
  }

  private func submit(
    bundleIdentifier: String,
    uninstall: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    self.completion = completion
    Self.activeRequests.append(self)
    let request = uninstall
      ? OSSystemExtensionRequest.deactivationRequest(
          forExtensionWithIdentifier: bundleIdentifier,
          queue: .main
        )
      : OSSystemExtensionRequest.activationRequest(
          forExtensionWithIdentifier: bundleIdentifier,
          queue: .main
        )
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    completion?(nil)
    finish()
  }

  func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    completion?(error)
    finish()
  }

  func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
  }

  func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension replacement: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    .replace
  }

  private func finish() {
    completion = nil
    Self.activeRequests.removeAll { $0 === self }
  }
}
