/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Manages the app state changes observed during application lifecycle events such as application start, resume and termination.
internal final class WatchdogTerminationAppStateManager {
    static let appStateKey = "app-state"

    let notificationCenter: NotificationCenter
    var vendorIdProvider: VendorIdProvider
    let dataStore: RUMDataStore
    let featureScope: FeatureScope
    let sysctl: SysctlProviding
    var lastAppState: AppState?
    var isWeatching: Bool

    init(
        dataStore: RUMDataStore,
        vendorIdProvider: VendorIdProvider,
        featureScope: FeatureScope,
        sysctl: SysctlProviding,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dataStore = dataStore
        self.notificationCenter = notificationCenter
        self.vendorIdProvider = vendorIdProvider
        self.featureScope = featureScope
        self.sysctl = sysctl
        self.isWeatching = false
    }

    func start() throws {
        DD.logger.debug("Start app state monitoring")
        isWeatching = true
        try storeCurrentAppState()
    }

    func stop() throws {
        DD.logger.debug("Stop app state monitoring")
        isWeatching = false
    }

    func updateAppState(block: @escaping (inout WatchdogTerminationAppState?) -> Void) {
        dataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            var appState = appState
            block(&appState)
            DD.logger.debug("Updating app state in data store")
            self.dataStore.setValue(appState, forKey: .watchdogAppStateKey)
        }
    }

    func storeCurrentAppState() throws {
        try currentAppState { [self] appState in
            dataStore.setValue(appState, forKey: .watchdogAppStateKey)
        }
    }

    func deleteAppState() {
        DD.logger.debug("Deleting app state from data store")
        dataStore.removeValue(forKey: .watchdogAppStateKey)
    }

    func readAppState(completion: @escaping (WatchdogTerminationAppState?) -> Void) {
        dataStore.value(forKey: .watchdogAppStateKey) { (state: WatchdogTerminationAppState?) in
            DD.logger.debug("Reading app state from data store.")
            completion(state)
        }
    }

    func currentAppState(completion: @escaping (WatchdogTerminationAppState) -> Void) throws {
        let systemBootTime = try sysctl.systemBootTime()
        let osVersion = try sysctl.osVersion()
        let isDebugging = try sysctl.isDebugging()
        let vendorId = vendorIdProvider.vendorId
        featureScope.context { context in
            let state: WatchdogTerminationAppState = .init(
                appVersion: context.version,
                osVersion: osVersion,
                systemBootTime: systemBootTime,
                isDebugging: isDebugging,
                wasTerminated: false,
                isActive: true,
                vendorId: vendorId
            )
            completion(state)
        }
    }
}

extension WatchdogTerminationAppStateManager: FeatureMessageReceiver {
    func receive(message: DatadogInternal.FeatureMessage, from core: any DatadogInternal.DatadogCoreProtocol) -> Bool {
        guard isWeatching else {
            return false
        }

        switch message {
        case .baggage, .webview, .telemetry:
            break
        case .context(let context):
            let state = context.applicationStateHistory.currentSnapshot.state
            guard state != lastAppState else {
                return false
            }
            switch state {
            case .active:
                updateAppState { state in
                    state?.isActive = true
                }
            case .inactive, .background:
                updateAppState { state in
                    state?.isActive = false
                }
            case .terminated:
                updateAppState { state in
                    state?.wasTerminated = true
                }
            }
            lastAppState = state
        }
        return false
    }
}
