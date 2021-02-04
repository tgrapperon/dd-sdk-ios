/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for writing and reading  the `CrashContext`
internal protocol CrashContextProviderType: class {
    /// Returns current `CrashContext` value.
    var currentCrashContext: CrashContext { get }
    /// Notifies on current `CrashContext` change.
    var onCrashContextChange: ((CrashContext) -> Void)? { set get }

    /// Updates the `CrashContext` with last `RUMViewEvent` information.
    func update(lastRUMViewEvent: RUMViewEvent)

    /// Updates the `CrashContext` with last `TarckingConsent` information.
    func update(lastTrackingConsent: TrackingConsent)
}

/// Manages the `CrashContext` reads and writes in a thread-safe manner.
internal class CrashContextProvider: CrashContextProviderType, ConsentSubscriber {
    /// Queue for synchronizing internal operations.
    private let queue: DispatchQueue
    /// Unsychronized `CrashContext`. The `queue` must be used to synchronize its mutation.
    private var unsafeCrashContext: CrashContext {
        willSet { onCrashContextChange?(newValue) }
    }

    // MARK: - Initializer

    init(consentProvider: ConsentProvider) {
        self.queue = DispatchQueue(
            label: "com.datadoghq.crash-context",
            target: .global(qos: .utility)
        )
        self.unsafeCrashContext = CrashContext(
            // Set initial `TrackingConsent`
            lastTrackingConsent: .init(trackingConsent: consentProvider.currentValue),
            lastRUMViewEvent: nil
        )

        // Subscribe for `TrackingConsent` updates
        consentProvider.subscribe(consentSubscriber: self)
    }

    // MARK: - CrashContextProviderType

    var currentCrashContext: CrashContext {
        queue.sync { unsafeCrashContext }
    }

    var onCrashContextChange: ((CrashContext) -> Void)? = nil

    func update(lastRUMViewEvent: RUMViewEvent) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            var context = self.unsafeCrashContext
            context.lastRUMViewEvent = lastRUMViewEvent
            self.unsafeCrashContext = context
        }
    }

    /// Updates `CrashContext` with last `TarckingConsent` information.
    func update(lastTrackingConsent: TrackingConsent) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            var context = self.unsafeCrashContext
            context.lastTrackingConsent = .init(trackingConsent: lastTrackingConsent)
            self.unsafeCrashContext = context
        }
    }

    // MARK: - ConsentSubscriber

    func consentChanged(from oldValue: TrackingConsent, to newValue: TrackingConsent) {
        update(lastTrackingConsent: newValue)
    }
}
