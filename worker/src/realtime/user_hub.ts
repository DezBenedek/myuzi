import { DurableObject } from "cloudflare:workers";

export type RealtimeEvent = {
  type: string;
  [key: string]: unknown;
};

/**
 * Per-user WebSocket hub (hibernatable).
 * One Durable Object instance per userId — fans out realtime events.
 */
export class UserHub extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.headers.get("Upgrade")?.toLowerCase() === "websocket") {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      const userId = url.searchParams.get("userId") ?? "";
      server.serializeAttachment({ userId, connectedAt: Date.now() });
      try {
        server.send(JSON.stringify({ type: "hello", userId, ts: Date.now() }));
      } catch (_) {}
      return new Response(null, { status: 101, webSocket: client });
    }

    if (request.method === "POST" && url.pathname.endsWith("/publish")) {
      const text = await request.text();
      let payload = text;
      try {
        JSON.parse(text);
      } catch {
        payload = JSON.stringify({ type: "event", raw: text });
      }
      let sent = 0;
      for (const ws of this.ctx.getWebSockets()) {
        try {
          ws.send(payload);
          sent++;
        } catch (_) {}
      }
      return Response.json({ ok: true, sent });
    }

    return new Response("Not found", { status: 404 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    if (typeof message !== "string") return;
    try {
      const data = JSON.parse(message) as { type?: string };
      if (data.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", ts: Date.now() }));
      }
    } catch (_) {}
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string) {
    try {
      ws.close(code, reason);
    } catch (_) {}
  }

  async webSocketError(_ws: WebSocket, _error: unknown) {
    // Client disconnects are normal; avoid noisy logs.
  }
}
