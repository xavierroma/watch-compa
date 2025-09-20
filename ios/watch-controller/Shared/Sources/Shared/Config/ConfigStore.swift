import Foundation
import Combine

public protocol ConfigStoreProtocol: AnyObject {
    var configDidChange: AnyPublisher<AppConfig, Never> { get }
    func currentConfig() -> AppConfig
    func save(_ config: AppConfig) async
    func ensureDefaults() async
}

@MainActor
public final class AppGroupConfigStore: ObservableObject, ConfigStoreProtocol {
    private let suiteName: String
    private let key = "AppConfig"
    private let subject: CurrentValueSubject<AppConfig, Never>

    // Ensure downstream delivery happens on the main run loop
    public var configDidChange: AnyPublisher<AppConfig, Never> {
        subject
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    public init(appGroupID: String) {
        self.suiteName = appGroupID
        // Start with defaults; load() will push saved value if present
        self.subject = CurrentValueSubject<AppConfig, Never>(AppConfig.defaultConfig())
        Task { await load() }
    }

    public func currentConfig() -> AppConfig {
        subject.value
    }

    public func save(_ config: AppConfig) async {
        if let defaults = UserDefaults(suiteName: self.suiteName),
           let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: self.key)
        }
        self.subject.send(config)
    }

    public func ensureDefaults() async {
        let cfg = currentConfig()
        await save(cfg)
    }

    private func load() async {
        var config = AppConfig.defaultConfig()
        if let defaults = UserDefaults(suiteName: self.suiteName),
           let data = defaults.data(forKey: self.key),
           let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = saved
        } else {
            // Persist defaults if not present
            if let defaults = UserDefaults(suiteName: self.suiteName),
               let data = try? JSONEncoder().encode(config) {
                defaults.set(data, forKey: self.key)
            }
        }
        self.subject.send(config)
    }
}
