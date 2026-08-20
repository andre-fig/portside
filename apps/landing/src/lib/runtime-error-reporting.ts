type RuntimeErrorPayload = {
  message: string;
  stack?: string;
  route: string;
  context: Record<string, unknown>;
};

declare global {
  interface Window {
    __portsideReportRuntimeError?: (payload: RuntimeErrorPayload) => void;
  }
}

export function reportRuntimeError(error: unknown, context: Record<string, unknown> = {}) {
  if (typeof window === "undefined") return;

  const message =
    error instanceof Response
      ? `Response ${error.status}${error.url ? ` at ${error.url}` : ""}`
      : error instanceof Error
        ? error.message
        : String(error);
  const stack = error instanceof Error ? error.stack : undefined;

  window.__portsideReportRuntimeError?.({
    message,
    ...(stack !== undefined && { stack }),
    route: window.location.pathname,
    context,
  });
}
