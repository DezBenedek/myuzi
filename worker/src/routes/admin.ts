import { Hono } from "hono";

import type { Env, Variables } from "../types";
import { getFamily } from "../lib/db";
import { id } from "../lib/crypto";
import { requireAuth } from "../middleware/auth";

const admin = new Hono<{ Bindings: Env; Variables: Variables }>();

function isSuperadmin(email: string, configured: string): boolean {
  const allowed = configured
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  return allowed.includes(email.trim().toLowerCase());
}

admin.use("*", requireAuth);
admin.use("*", async (c, next) => {
  if (!isSuperadmin(c.get("user").email, c.env.SUPERADMIN_EMAILS ?? "")) {
    return c.json({ error: "Superadmin jogosultság szükséges" }, 403);
  }
  await next();
});

admin.get("/families", async (c) => {
  const query = (c.req.query("q") ?? "").trim().toLowerCase().slice(0, 80);
  const pattern = `%${query}%`;
  const rows = await c.env.DB.prepare(
    `SELECT f.id, f.name, f.plan, u.id AS owner_id, u.name AS owner_name, u.email AS owner_email
     FROM families f JOIN users u ON u.id = f.owner_id
     WHERE ? = '' OR lower(f.name) LIKE ? OR lower(u.name) LIKE ? OR lower(u.email) LIKE ?
     ORDER BY f.name
     LIMIT 100`,
  )
    .bind(query, pattern, pattern, pattern)
    .all<{
      id: string;
      name: string;
      plan: string;
      owner_id: string;
      owner_name: string;
      owner_email: string;
    }>();
  return c.json({
    families: rows.results ?? [],
  });
});

admin.get("/invoices", async (c) => {
  const rows = await c.env.DB.prepare(
    `SELECT i.id, i.invoice_number, i.issued_at, i.amount, i.currency,
            i.period_label, i.filename, i.size_bytes, i.created_at,
            f.id AS family_id, f.name AS family_name,
            u.email AS owner_email
     FROM manual_invoices i
     JOIN families f ON f.id = i.family_id
     JOIN users u ON u.id = f.owner_id
     WHERE i.voided_at IS NULL
     ORDER BY i.issued_at DESC, i.created_at DESC
     LIMIT 200`,
  )
    .all<{
      id: string;
      invoice_number: string;
      issued_at: string;
      amount: number;
      currency: string;
      period_label: string | null;
      filename: string;
      size_bytes: number;
      created_at: string;
      family_id: string;
      family_name: string;
      owner_email: string;
    }>();
  return c.json({ invoices: rows.results ?? [] });
});

admin.post("/invoices", async (c) => {
  const form = await c.req.parseBody();
  const familyId = String(form.familyId ?? "").trim();
  const invoiceNumber = String(form.invoiceNumber ?? "").trim().slice(0, 80);
  const issuedAt = String(form.issuedAt ?? "").trim();
  const amount = Number.parseInt(String(form.amount ?? "0"), 10);
  const currency = String(form.currency ?? "HUF").trim().toUpperCase().slice(0, 3);
  const periodLabel = String(form.periodLabel ?? "").trim().slice(0, 120) || null;
  const uploaded = form.file;
  const file = uploaded instanceof File ? uploaded : null;

  if (!familyId || !invoiceNumber || !/^\d{4}-\d{2}-\d{2}$/.test(issuedAt)) {
    return c.json({ error: "A család, számlaszám és dátum kötelező" }, 400);
  }
  if (!Number.isSafeInteger(amount) || amount < 0 || !/^[A-Z]{3}$/.test(currency)) {
    return c.json({ error: "Érvénytelen összeg vagy pénznem" }, 400);
  }
  if (!file || file.size <= 0 || file.size > 10 * 1024 * 1024) {
    return c.json({ error: "PDF kell, legfeljebb 10 MB méretben" }, 400);
  }

  const family = await getFamily(c.env.DB, familyId);
  if (!family) return c.json({ error: "Család nem található" }, 404);

  const bytes = new Uint8Array(await file.arrayBuffer());
  const header = new TextDecoder().decode(bytes.subarray(0, 5));
  if (header !== "%PDF-") {
    return c.json({ error: "A feltöltött fájl nem PDF" }, 415);
  }

  const invoiceId = id("minv");
  const key = `invoices/${familyId}/${invoiceId}.pdf`;
  await c.env.INVOICES.put(key, bytes, {
    httpMetadata: { contentType: "application/pdf" },
    customMetadata: {
      invoiceNumber,
      familyId,
      uploadedBy: c.get("userId"),
    },
  });

  try {
    await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO manual_invoices
         (id, family_id, invoice_number, issued_at, amount, currency, period_label,
          filename, r2_key, size_bytes, uploaded_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        invoiceId,
        familyId,
        invoiceNumber,
        issuedAt,
        amount,
        currency,
        periodLabel,
        file.name || `${invoiceNumber}.pdf`,
        key,
        bytes.byteLength,
        c.get("userId"),
      ),
      c.env.DB.prepare(
        `INSERT INTO admin_audit_log
         (id, actor_id, action, entity_type, entity_id, metadata_json)
         VALUES (?, ?, 'invoice_upload', 'manual_invoice', ?, ?)`,
      ).bind(
        id("audit"),
        c.get("userId"),
        invoiceId,
        JSON.stringify({ familyId, invoiceNumber, size: bytes.byteLength }),
      ),
    ]);
  } catch (err) {
    await c.env.INVOICES.delete(key);
    throw err;
  }

  return c.json({ ok: true, invoiceId }, 201);
});

admin.delete("/invoices/:id", async (c) => {
  const invoiceId = c.req.param("id");
  const invoice = await c.env.DB.prepare(
    `SELECT r2_key FROM manual_invoices WHERE id = ? AND voided_at IS NULL`,
  )
    .bind(invoiceId)
    .first<{ r2_key: string }>();
  if (!invoice) return c.json({ error: "Számla nem található" }, 404);

  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE manual_invoices SET voided_at = datetime('now') WHERE id = ?`,
    ).bind(invoiceId),
    c.env.DB.prepare(
      `INSERT INTO admin_audit_log
       (id, actor_id, action, entity_type, entity_id)
       VALUES (?, ?, 'invoice_void', 'manual_invoice', ?)`,
    ).bind(id("audit"), c.get("userId"), invoiceId),
  ]);
  await c.env.INVOICES.delete(invoice.r2_key);
  return c.json({ ok: true });
});

export { isSuperadmin };
export default admin;
