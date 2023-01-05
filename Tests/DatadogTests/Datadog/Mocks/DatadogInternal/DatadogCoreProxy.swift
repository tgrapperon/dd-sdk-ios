/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import Datadog

/// A `DatadogCoreProtocol` which proxies all calls to the real `DatadogCore` implementation. It intercepts
/// all events written to the actual core and provides APIs to read their values back for tests.
///
/// Usage example:
///
///     ```
///     let core = DatadogCoreProxy(context: .mockWith(service: "foo-bar"))
///     defer { core.flushAndTearDown() }
///     core.register(feature: LoggingFeature.mockAny())
///
///     let logger = Logger.builder.build(in: core)
///     logger.debug("message")
///
///     let events = core.waitAndReturnEvents(of: LoggingFeature.self, ofType: LogEvent.self)
///     XCTAssertEqual(events[0].serviceName, "foo-bar")
///     ```
///
internal class DatadogCoreProxy: DatadogCoreProtocol {
    private let proxy: DatadogCoreProtocol & DatadogV1CoreProtocol

    private var featureScopeInterceptors: [String: FeatureScopeInterceptor] = [:]

    init(context: DatadogContext = .mockAny()) {
        self.context = context
        self.proxy = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: context.trackingConsent,
            userInfoProvider: .mockWith(userInfo: context.userInfo ?? .empty),
            performance: .mockAny(),
            httpClient: .mockAny(),
            encryption: nil,
            contextProvider: .mockWith(context: context),
            applicationVersion: context.version
        )
    }

    var context: DatadogContext {
        didSet {
            let core = self.proxy as! DatadogCore
            core.contextProvider.replace(context: context)
        }
    }

    func register(feature: DatadogFeature) throws {
        featureScopeInterceptors[feature.name] = FeatureScopeInterceptor()
        try proxy.register(feature: feature)
    }

    func feature<T>(named name: String, type: T.Type) -> T? where T: DatadogFeature {
        return proxy.feature(named: name, type: type)
    }

    func register(integration: DatadogFeatureIntegration) throws {
        try proxy.register(integration: integration)
    }

    func integration<T>(named name: String, type: T.Type) -> T? where T: DatadogFeatureIntegration {
        return proxy.integration(named: name, type: type)
    }

    func scope(for feature: String) -> FeatureScope? {
        return proxy.scope(for: feature).map { scope in
            FeatureScopeProxy(proxy: scope, interceptor: featureScopeInterceptors[feature]!)
        }
    }

    func set(feature: String, attributes: @escaping () -> FeatureBaggage) {
        proxy.set(feature: feature, attributes: attributes)
    }

    func send(message: FeatureMessage, sender: DatadogCoreProtocol, else fallback: @escaping () -> Void) {
        proxy.send(message: message, sender: self, else: fallback)
    }

    func flush() {
        proxy.flush()
    }

    func flushAndTearDown() {
        proxy.flushAndTearDown()

        if temporaryCoreDirectory.coreDirectory.exists() {
            temporaryCoreDirectory.coreDirectory.delete()
        }
        if temporaryCoreDirectory.osDirectory.exists() {
            temporaryCoreDirectory.osDirectory.delete()
        }
    }
}

extension DatadogCoreProxy: DatadogV1CoreProtocol {
    func feature<T>(_ type: T.Type) -> T? {
        return proxy.feature(type)
    }

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        featureScopeInterceptors[key] = FeatureScopeInterceptor()

        proxy.register(feature: instance)
    }

    func scope<T>(for featureType: T.Type) -> FeatureScope? {
        return proxy.scope(for: featureType).map { scope in
            let key = String(describing: T.self)
            return FeatureScopeProxy(proxy: scope, interceptor: featureScopeInterceptors[key]!)
        }
    }
}

private struct FeatureScopeProxy: FeatureScope {
    let proxy: FeatureScope
    let interceptor: FeatureScopeInterceptor

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) throws -> Void) {
        interceptor.enter()
        proxy.eventWriteContext(bypassConsent: bypassConsent) { context, writer in
            try block(context, interceptor.intercept(writer: writer))
            interceptor.leave()
        }
    }
}

private class FeatureScopeInterceptor {
    struct InterceptingWriter: Writer {
        static let jsonEncoder = JSONEncoder.default()

        let actualWriter: Writer
        unowned var interception: FeatureScopeInterceptor?

        func write<T>(value: T) where T: Encodable {
            actualWriter.write(value: value)

            let event = value
            let data = try! InterceptingWriter.jsonEncoder.encode(value)
            interception?.events.append((event, data))
        }
    }

    func intercept(writer: Writer) -> Writer {
        return InterceptingWriter(actualWriter: writer, interception: self)
    }

    // MARK: - Synchronizing and awaiting events:

    @ReadWriteLock
    private var events: [(event: Any, data: Data)] = []

    private let group = DispatchGroup()

    func enter() { group.enter() }
    func leave() { group.leave() }

    func waitAndReturnEvents() -> [(event: Any, data: Data)] {
        _ = group.wait(timeout: .distantFuture)
        return events
    }
}

extension DatadogCoreProxy {
    /// Returns all events of given type for certain Feature.
    ///
    /// - Parameter feature: The Feature to retrieve events from
    /// - Parameter type: The type of events to filter out
    /// - Returns: A list of events.
    func waitAndReturnEvents<F, T>(of feature: F.Type, ofType type: T.Type) -> [T] where F: V1Feature, T: Encodable {
        flush()

        let key = String(describing: F.self)
        let interceptor = self.featureScopeInterceptors[key]!
        return interceptor.waitAndReturnEvents().compactMap { $0.event as? T }
    }

    /// Returns serialized events of given Feature.
    ///
    /// - Parameter feature: The Feature to retrieve events from
    /// - Returns: A list of serialized events.
    func waitAndReturnEventsData<F>(of feature: F.Type) -> [Data] where F: V1Feature {
        flush()

        let key = String(describing: F.self)
        let interceptor = self.featureScopeInterceptors[key]!
        return interceptor.waitAndReturnEvents().map { $0.data }
    }
}
