/**
 * HTTP client for the s&box CoworkBridge.
 *
 * The bridge runs inside the editor and listens on http://localhost:38080.
 * All requests are POST with a JSON body; the bridge returns JSON.
 *
 * If the editor isn't running or the bridge wasn't started, requests will
 * time out or fail with ECONNREFUSED. Map those to actionable error messages.
 */

// Default to 127.0.0.1 (not localhost) to avoid IPv4/IPv6 mismatch with the
// HttpListener-bound bridge on Windows.
const BRIDGE_URL = process.env.SBOX_BRIDGE_URL ?? "http://127.0.0.1:38080";
const TIMEOUT_MS = 30_000;

export class BridgeError extends Error {
  constructor(message: string, public readonly cause?: unknown) {
    super(message);
    this.name = "BridgeError";
  }
}

export async function bridgeCall<T = unknown>(
  path: string,
  body: Record<string, unknown> = {},
): Promise<T> {
  const url = `${BRIDGE_URL}${path}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (e) {
    clearTimeout(timer);
    const err = e as { code?: string; name?: string; message?: string; cause?: { code?: string; message?: string; address?: string; port?: number } };
    if (err?.name === "AbortError") {
      throw new BridgeError(
        `Request to ${path} timed out after ${TIMEOUT_MS}ms. The editor may be busy or hung.`,
      );
    }
    // Drill into Node's nested cause for the real fetch error code.
    const causeCode = err?.cause?.code ?? err?.code ?? "unknown";
    const causeMsg = err?.cause?.message ?? err?.message ?? "no message";
    const causeAddr = err?.cause?.address ? `${err.cause.address}:${err.cause.port}` : "?";
    const detail = `name=${err?.name} code=${causeCode} addr=${causeAddr} msg="${causeMsg}"`;

    if (causeCode === "ECONNREFUSED" || /ECONNREFUSED/i.test(causeMsg)) {
      throw new BridgeError(
        `Cannot reach s&box editor bridge at ${BRIDGE_URL} (${detail}). ` +
          `Make sure the editor is open and you ran Editor > Cowork > Start MCP Bridge.`,
        e,
      );
    }
    // Fetch failed for some other reason - surface the full detail so we can diagnose.
    throw new BridgeError(`Bridge fetch failed: ${detail}`, e);
  }
  clearTimeout(timer);

  const text = await res.text();
  let parsed: unknown;
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    throw new BridgeError(`Bridge returned non-JSON response (status ${res.status}): ${text.slice(0, 200)}`);
  }

  if (!res.ok) {
    const errMsg = (parsed as { error?: string })?.error ?? `status ${res.status}`;
    throw new BridgeError(`Bridge error: ${errMsg}`);
  }

  // Bridge convention: top-level `error` field means the call failed even though HTTP is 200.
  const obj = parsed as { error?: string };
  if (obj?.error) throw new BridgeError(`Bridge handler error: ${obj.error}`);

  return parsed as T;
}
