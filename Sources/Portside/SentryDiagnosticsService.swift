import Foundation
import PortsideCore
import Sentry

/// The only Portside type allowed to depend on the Sentry SDK.
public final class SentryDiagnosticsService: DiagnosticsService, @unchecked Sendable {
    private static let release = "com.portside.app@0.1.0+1"
    private static let allowedTagKeys: Set<String> = [
        "stage", "error_code", "portside_version", "portside_build", "macos_version", "architecture",
        "runtime_name", "runtime_version", "graphics_backend", "process_type", "exit_code", "duration", "retry_count"
    ]
    private static let allowedBreadcrumbs: Set<String> = [
        "setup_started", "requirements_checked", "runtime_download_started", "runtime_verified", "prefix_created",
        "steam_install_started", "steam_update_started", "steam_launch_requested", "process_exited", "repair_requested"
    ]

    public init() {
        SentrySDK.start { options in
            #if DEBUG
            options.dsn = nil
            options.environment = "debug"
            #else
            options.dsn = "https://5aa6a3d7a22bd8bb4b718bc2d6cfaac7@o4511935178080256.ingest.us.sentry.io/4511935182405632"
            options.environment = "production"
            #endif
            options.releaseName = Self.release
            options.debug = false
            options.sendDefaultPii = false
            options.tracesSampleRate = 0
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.maxBreadcrumbs = 20
            options.maxCacheItems = 30
            options.beforeSend = { event in
                event.user = nil
                event.extra = nil
                event.context = nil
                event.tags = event.tags?.filter { Self.allowedTagKeys.contains($0.key) }
                return event
            }
        }
    }

    public func breadcrumb(_ name: String, context: DiagnosticContext) {
        guard Self.allowedBreadcrumbs.contains(name) else { return }
        let crumb = Breadcrumb(level: .info, category: "portside")
        crumb.message = name
        SentrySDK.addBreadcrumb(crumb)
    }

    public func capture(error: Error, context: DiagnosticContext) {
        let safeCode = context.errorCode ?? "portside_error"
        let safeError = NSError(domain: "Portside", code: 1, userInfo: [NSLocalizedDescriptionKey: safeCode])
        SentrySDK.configureScope { scope in
            for (key, value) in context.fields where Self.allowedTagKeys.contains(key) {
                scope.setTag(value: value, key: key)
            }
        }
        SentrySDK.capture(error: safeError)
    }

    public func submitManualDiagnostic(report: Data, context: DiagnosticContext) -> String? {
        let limitedReport = Data(report.prefix(64_000))
        SentrySDK.configureScope { scope in
            for (key, value) in context.fields where Self.allowedTagKeys.contains(key) {
                scope.setTag(value: value, key: key)
            }
            scope.addAttachment(Attachment(data: limitedReport, filename: "portside-diagnostic.txt", contentType: "text/plain"))
        }
        let eventID = SentrySDK.capture(message: "Portside manual diagnostic")
        SentrySDK.configureScope { scope in scope.clearAttachments() }
        return eventID.sentryIdString
    }
}
