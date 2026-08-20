import Foundation
import PortsideCore
import Sentry

/// The only Portside type allowed to depend on the Sentry SDK.
public final class SentryDiagnosticsService: DiagnosticsService, @unchecked Sendable {
    private static let dsn = "https://5aa6a3d7a22bd8bb4b718bc2d6cfaac7@o4511935178080256.ingest.us.sentry.io/4511935182405632"
    private static let release = "com.portside.app@0.1.0+1"
    private static let allowedTagKeys: Set<String> = [
        "stage", "error_code", "portside_version", "portside_build", "macos_version", "architecture",
        "runtime_version", "template_version", "engine_version", "renderer", "app_id",
        "executable_architecture", "graphics_api", "launch_attempt", "fallback_index", "exit_code",
        "window_detected", "rollback_performed", "process_started", "webhelper_started",
        "interface_verification", "msync_enabled", "esync_enabled"
    ]
    private static let allowedBreadcrumbs: Set<String> = [
        "setup_started", "requirements_checked", "runtime_download_started", "runtime_verified", "prefix_created",
        "steam_install_started", "steam_update_started", "steam_launch_requested", "process_exited", "repair_requested",
        "steam_started", "steamwebhelper_started", "steam_process_handoff_complete", "steam_handoff_failed",
        "steam_window_detected", "second_open"
    ]

    public init() {
        SentrySDK.start { options in
            // Keep diagnostics enabled in Debug as well. The app is often validated
            // directly from Xcode, and a nil DSN there made setup failures disappear.
            options.dsn = Self.dsn
            #if DEBUG
            options.environment = "debug"
            options.debug = true
            #else
            options.environment = "production"
            options.debug = false
            #endif
            options.releaseName = Self.release
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

    public func event(_ name: String, context: DiagnosticContext) {
        guard Self.allowedBreadcrumbs.contains(name) else { return }
        let crumb = Breadcrumb(level: .info, category: "portside.event")
        crumb.message = name
        for (key, value) in context.fields { crumb.setData(value: value, key: key) }
        SentrySDK.addBreadcrumb(crumb)
    }

    public func capture(error: Error, context: DiagnosticContext) {
        let safeCode = context.errorCode ?? "portside_error"
        let safeDescription = PortsideLogger.sanitize(error.localizedDescription)
        let safeError = NSError(domain: "Portside", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(safeCode): \(safeDescription)"])
        SentrySDK.configureScope { scope in
            for (key, value) in context.fields where Self.allowedTagKeys.contains(key) {
                scope.setTag(value: value, key: key)
            }
        }
        SentrySDK.capture(error: safeError)
        // Setup failures leave the app open, but flushing here also protects the
        // report when the user immediately quits or retries from the failure view.
        SentrySDK.flush(timeout: 2)
    }

}
