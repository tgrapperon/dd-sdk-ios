/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

extension WatchdogTerminationAppState: RandomMockable, AnyMockable {
    public static func mockAny() -> DatadogRUM.WatchdogTerminationAppState {
        return .init(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: .mockAny(),
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny()
        )
    }

    public static func mockRandom() -> WatchdogTerminationAppState {
        return .init(
            appVersion: .mockRandom(),
            osVersion: .mockRandom(),
            systemBootTime: .mockRandom(),
            isDebugging: .mockRandom(),
            wasTerminated: .mockRandom(),
            isActive: .mockRandom(),
            vendorId: .mockRandom()
        )
    }
}

class WatchdogTerminationReporterMock: WatchdogTerminationReporting {
    var didSend: XCTestExpectation

    init(didSend: XCTestExpectation) {
        self.didSend = didSend
    }

    func send() {
        didSend.fulfill()
    }
}

struct VendorIdProviderMock: VendorIdProvider, RandomMockable {
    static func mockRandom() -> VendorIdProviderMock {
        return VendorIdProviderMock(stubbedVendorId: .mockRandom())
    }

    var stubbedVendorId: String?
    private(set) var vendorId: String? {
        get {
            stubbedVendorId
        }
        set {
            stubbedVendorId = newValue
        }
    }

    init(stubbedVendorId: String? = nil) {
        self.stubbedVendorId = stubbedVendorId
    }

    static func mockWith(vendorId: String) -> VendorIdProviderMock {
        return VendorIdProviderMock(stubbedVendorId: vendorId)
    }
}

extension WatchdogTerminationReporter: RandomMockable {
    public static func mockRandom() -> Self {
        return .init()
    }
}

extension WatchdogTerminationChecker: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationChecker {
        return .init(
            appStateManager: .mockRandom(),
            deviceInfo: .mockRandom()
        )
    }
}

extension WatchdogTerminationAppStateManager: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationAppStateManager {
        return .init(
            dataStore: .mockRandom(),
            vendorIdProvider: VendorIdProviderMock(),
            featureScope: FeatureScopeMock(),
            sysctl: Sysctl.mockRandom()
        )
    }
}

extension Sysctl: RandomMockable {
    public static func mockRandom() -> DatadogInternal.Sysctl {
        return .init()
    }
}

extension RUMDataStore: RandomMockable {
    public static func mockRandom() -> DatadogRUM.RUMDataStore {
        return .init(featureScope: FeatureScopeMock())
    }
}

extension WatchdogTerminationMonitor: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationMonitor {
        return .init(
            checker: .mockRandom(),
            appStateManager: .mockRandom(),
            reporter: WatchdogTerminationReporter.mockRandom(),
            telemetry: NOPTelemetry()
        )
    }
}

extension LaunchReport: RandomMockable {
    public static func mockRandom() -> DatadogInternal.LaunchReport {
        return .init(didCrash: .mockRandom())
    }
}
