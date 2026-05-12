import net from "node:net";

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 9876;
const DEFAULT_TIMEOUT_MS = 60_000;

export type BlenderResponse = {
  status?: "ok" | "error";
  result?: unknown;
  message?: string;
  stdout?: string;
  stderr?: string;
};

export class BlenderBridgeError extends Error {
  constructor(message: string, public readonly cause?: unknown) {
    super(message);
    this.name = "BlenderBridgeError";
  }
}

function bridgeHost(): string {
  return process.env.BLENDER_MCP_HOST ?? DEFAULT_HOST;
}

function bridgePort(): number {
  const raw = process.env.BLENDER_MCP_PORT;
  if (!raw) return DEFAULT_PORT;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) return DEFAULT_PORT;
  return parsed;
}

function bridgeTimeoutMs(): number {
  const raw = process.env.BLENDER_MCP_TIMEOUT_MS;
  if (!raw) return DEFAULT_TIMEOUT_MS;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed < 1000) return DEFAULT_TIMEOUT_MS;
  return parsed;
}

function connectionHint(host: string, port: number): string {
  return (
    `Cannot reach Blender MCP bridge at ${host}:${port}. ` +
    `In the open Blender session, run scripts/start_blender_mcp.py, ` +
    `or start a background bridge with scripts/start_blender_mcp_background.ps1.`
  );
}

export async function blenderExecute(
  code: string,
  options: { strictJson?: boolean; timeoutMs?: number } = {},
): Promise<BlenderResponse> {
  const host = bridgeHost();
  const port = bridgePort();
  const timeoutMs = options.timeoutMs ?? bridgeTimeoutMs();
  const request = Buffer.from(
    JSON.stringify({
      type: "execute",
      code,
      strict_json: options.strictJson ?? true,
    }) + "\0",
    "utf8",
  );

  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    const chunks: Buffer[] = [];
    let settled = false;

    const finish = (fn: () => void): void => {
      if (settled) return;
      settled = true;
      socket.destroy();
      fn();
    };

    socket.setTimeout(timeoutMs);

    socket.on("connect", () => {
      socket.write(request);
    });

    socket.on("data", (chunk) => {
      chunks.push(chunk);
      const buffer = Buffer.concat(chunks);
      const end = buffer.indexOf(0);
      if (end === -1) return;

      const payload = buffer.subarray(0, end).toString("utf8");
      finish(() => {
        try {
          const parsed = JSON.parse(payload) as BlenderResponse;
          if (parsed.status === "error") {
            reject(new BlenderBridgeError(parsed.message ?? "Blender returned an unknown error"));
            return;
          }
          resolve(parsed);
        } catch (e) {
          reject(new BlenderBridgeError(`Blender returned invalid JSON: ${payload.slice(0, 300)}`, e));
        }
      });
    });

    socket.on("timeout", () => {
      finish(() => {
        reject(new BlenderBridgeError(`Blender MCP request timed out after ${timeoutMs}ms`));
      });
    });

    socket.on("error", (e: NodeJS.ErrnoException) => {
      finish(() => {
        if (e.code === "ECONNREFUSED" || e.code === "EHOSTUNREACH" || e.code === "ENOTFOUND") {
          reject(new BlenderBridgeError(connectionHint(host, port), e));
          return;
        }
        reject(new BlenderBridgeError(`Blender MCP socket error: ${e.message}`, e));
      });
    });

    socket.on("close", () => {
      if (settled) return;
      finish(() => {
        reject(new BlenderBridgeError("Blender MCP socket closed before a complete response was received"));
      });
    });
  });
}

export function blenderBridgeAddress(): { host: string; port: number; timeoutMs: number } {
  return {
    host: bridgeHost(),
    port: bridgePort(),
    timeoutMs: bridgeTimeoutMs(),
  };
}
