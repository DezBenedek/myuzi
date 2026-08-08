/**
 * Read a request body with a hard byte limit.
 *
 * Checking Content-Length alone is insufficient because chunked requests do
 * not have one. This keeps the Worker from buffering an attacker-controlled
 * unbounded body before the size check.
 */
export async function readLimitedBody(
  request: Request,
  maxBytes: number,
): Promise<Uint8Array | null> {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) return null;

  const declared = request.headers.get("content-length");
  let declaredLength: number | null = null;
  if (declared) {
    const length = Number(declared);
    if (!Number.isSafeInteger(length) || length < 0 || length > maxBytes) {
      return null;
    }
    declaredLength = length;
  }

  const body = request.body;
  if (!body) return null;

  const reader = body.getReader();
  let result = new Uint8Array(
    Math.min(maxBytes, Math.max(1, declaredLength ?? 64 * 1024)),
  );
  let total = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;

      if (total + value.byteLength > maxBytes) {
        try {
          await reader.cancel("request body too large");
        } catch (_) {}
        return null;
      }
      if (total + value.byteLength > result.length) {
        const next = new Uint8Array(
          Math.min(maxBytes, Math.max(total + value.byteLength, result.length * 2)),
        );
        next.set(result);
        result = next;
      }
      result.set(value, total);
      total += value.byteLength;
    }
  } finally {
    reader.releaseLock();
  }

  return result.subarray(0, total);
}

export async function readLimitedJson<T = unknown>(
  request: Request,
  maxBytes = 256 * 1024,
): Promise<T | null> {
  const body = await readLimitedBody(request, maxBytes);
  if (!body) return null;
  try {
    return JSON.parse(new TextDecoder().decode(body)) as T;
  } catch (_) {
    return null;
  }
}
