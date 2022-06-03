/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias RUMSessionListener = (String, Bool) -> Void

/// Dependency container for injecting components to `RUMScopes` hierarchy.
internal struct RUMScopeDependencies {
    let rumApplicationID: String
    let sessionSampler: Sampler
    /// The start time of the application, indicated as SDK init. Measured in device time (without NTP correction).
    let sdkInitDate: Date
    let backgroundEventTrackingEnabled: Bool
    let appStateListener: AppStateListening
    let userInfoProvider: RUMUserInfoProvider
    let launchTimeProvider: LaunchTimeProviderType
    let connectivityInfoProvider: RUMConnectivityInfoProvider
    let serviceName: String
    let applicationVersion: String
    let sdkVersion: String
    let source: String
    let firstPartyURLsFilter: FirstPartyURLsFilter
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
    let rumUUIDGenerator: RUMUUIDGenerator
    /// Adjusts RUM events time (device time) to server time.
    let dateCorrector: DateCorrectorType
    /// Integration with Crash Reporting. It updates the crash context with RUM info.
    /// `nil` if Crash Reporting feature is not enabled.
    let crashContextIntegration: RUMWithCrashContextIntegration?
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    /// Produces `RUMViewUpdatesThrottlerType` for each started RUM view scope.
    let viewUpdatesThrottlerFactory: () -> RUMViewUpdatesThrottlerType

    let vitalCPUReader: SamplingBasedVitalReader
    let vitalMemoryReader: SamplingBasedVitalReader
    let vitalRefreshRateReader: ContinuousVitalReader

    let onSessionStart: RUMSessionListener?
}

internal extension RUMScopeDependencies {
    init(
        rumFeature: RUMFeature,
        crashReportingFeature: CrashReportingFeature?,
        context: DatadogV1Context,
        telemetry: Telemetry?
    ) {
        self.init(
            rumApplicationID: rumFeature.configuration.applicationID,
            sessionSampler: rumFeature.configuration.sessionSampler,
            sdkInitDate: context.sdkInitDate,
            backgroundEventTrackingEnabled: rumFeature.configuration.backgroundEventTrackingEnabled,
            appStateListener: context.appStateListener,
            userInfoProvider: RUMUserInfoProvider(userInfoProvider: context.userInfoProvider),
            launchTimeProvider: context.launchTimeProvider,
            connectivityInfoProvider: RUMConnectivityInfoProvider(
                networkConnectionInfoProvider: context.networkConnectionInfoProvider,
                carrierInfoProvider: context.carrierInfoProvider
            ),
            serviceName: context.service,
            applicationVersion: context.version,
            sdkVersion: context.sdkVersion,
            source: context.source,
            firstPartyURLsFilter: FirstPartyURLsFilter(hosts: rumFeature.configuration.firstPartyHosts),
            eventBuilder: RUMEventBuilder(
                eventsMapper: RUMEventsMapper(
                    viewEventMapper: rumFeature.configuration.viewEventMapper,
                    errorEventMapper: rumFeature.configuration.errorEventMapper,
                    resourceEventMapper: rumFeature.configuration.resourceEventMapper,
                    actionEventMapper: rumFeature.configuration.actionEventMapper,
                    longTaskEventMapper: rumFeature.configuration.longTaskEventMapper,
                    telemetry: telemetry
                )
            ),
            eventOutput: RUMEventFileOutput(
                fileWriter: rumFeature.storage.writer
            ),
            rumUUIDGenerator: rumFeature.configuration.uuidGenerator,
            dateCorrector: context.dateCorrector,
            crashContextIntegration: crashReportingFeature.map { .init(crashReporting: $0) },
            ciTest: CITestIntegration.active?.rumCITest,
            viewUpdatesThrottlerFactory: { RUMViewUpdatesThrottler() },
            vitalCPUReader: VitalCPUReader(telemetry: telemetry),
            vitalMemoryReader: VitalMemoryReader(),
            vitalRefreshRateReader: VitalRefreshRateReader(),
            onSessionStart: rumFeature.configuration.onSessionStart
        )
    }
}
