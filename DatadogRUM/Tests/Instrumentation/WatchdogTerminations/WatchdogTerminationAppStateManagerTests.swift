/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class WatchdogTerminationAppStateManagerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var sut: WatchdogTerminationAppStateManager!
    var dataStore: RUMDataStore!
    var featureScope: FeatureScopeMock!
    var core: PassthroughCoreMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()

        featureScope = FeatureScopeMock()
        dataStore = RUMDataStore(featureScope: featureScope)
        sut = WatchdogTerminationAppStateManager(
            dataStore: dataStore,
            featureScope: featureScope,
            sysctl: Sysctl(),
            vendorIdProvider: VendorIdProviderMock()
        )
        core = PassthroughCoreMock(
            context: .mockWith(applicationStateHistory: .mockAppInBackground()),
            messageReceiver: sut
        )
    }

    func testAppStart_SetsIsActive() throws {
        try sut.start()

        let isActiveExpectation = expectation(description: "isActive is set to true")

        // app state changes
        core.context.applicationStateHistory.append(.init(state: .active, date: .init()))
        dataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertTrue(appState?.isActive == true)
            isActiveExpectation.fulfill()
        }
        wait(for: [isActiveExpectation], timeout: 1)

        let isBackgroundedExpectation = expectation(description: "isActive is set to false")

        // app state changes again
        core.context.applicationStateHistory.append(.init(state: .background, date: .init()))
        dataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertTrue(appState?.isActive == false)
            isBackgroundedExpectation.fulfill()
        }

        wait(for: [isBackgroundedExpectation], timeout: 1)
    }

    func testDeleteAppState() throws {
        try sut.start()

        let isActiveExpectation = expectation(description: "isActive is set")
        core.context.applicationStateHistory.append(.init(state: .active, date: .init()))
        dataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertNotNil(appState)
            isActiveExpectation.fulfill()
        }
        wait(for: [isActiveExpectation], timeout: 1)

        let deleteExpectation = expectation(description: "isActive is set to false")
        sut.deleteAppState()
        dataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertNil(appState)
            deleteExpectation.fulfill()
        }

        wait(for: [deleteExpectation], timeout: 1)
    }
}
