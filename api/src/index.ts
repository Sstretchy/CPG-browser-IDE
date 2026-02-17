import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync } from "node:fs";

const execFileAsync = promisify(execFile);
const app = new Hono();

const DB_PATH = process.env.CPG_DB_PATH ?? "/app/data/cpg.db";
const SQLITE_BIN = process.env.SQLITE_BIN ?? "sqlite3";
const PORT = Number(process.env.PORT ?? 8787);
let schemaDocsGroupColumnPromise: Promise<"kind" | "category"> | null = null;

type GraphNode = {
  id: string;
  label: string;
  kind: string;
  file: string | null;
  line: number | null;
};

type GraphEdge = {
  source: string;
  target: string;
  kind: string;
};

async function runSql<T>(sql: string): Promise<T[]> {
  const { stdout } = await execFileAsync(
    SQLITE_BIN,
    ["-cmd", ".timeout 5000", "-json", DB_PATH, sql],
    {
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  const data = stdout.trim();
  if (!data) return [];
  return JSON.parse(data) as T[];
}

async function getSchemaDocsGroupColumn(): Promise<"kind" | "category"> {
  if (!schemaDocsGroupColumnPromise) {
    schemaDocsGroupColumnPromise = runSql<{ name: string }>(
      "PRAGMA table_info(schema_docs)",
    ).then((columns) => {
      const names = new Set(columns.map((column) => column.name));
      return names.has("kind") ? "kind" : "category";
    });
  }
  return schemaDocsGroupColumnPromise;
}

app.get("/health", (c) =>
  c.json({
    ok: true,
    dbPath: DB_PATH,
    dbExists: existsSync(DB_PATH),
  }),
);

app.get("/api/schema/docs", async (c) => {
  const limit = Math.min(Number(c.req.query("limit") ?? "50"), 200);
  const groupColumn = await getSchemaDocsGroupColumn();
  const rows = await runSql<{
    kind: string;
    name: string;
    description: string | null;
    example: string | null;
  }>(
    `SELECT ${groupColumn} AS kind, name, description, example
     FROM schema_docs
     ORDER BY ${groupColumn}, name
     LIMIT ${limit}`,
  );
  return c.json(rows);
});

app.get("/api/queries", async (c) => {
  const rows = await runSql<{
    name: string;
    description: string | null;
    sql: string | null;
  }>(`SELECT name, description, sql FROM queries ORDER BY name LIMIT 100`);
  return c.json(rows);
});

app.get("/api/graph/function-neighborhood", async (c) => {
  const id = c.req.query("id");
  if (!id) {
    return c.json({ error: "Query param 'id' is required" }, 400);
  }

  const safeId = id.replace(/'/g, "''");

  const nodeRows = await runSql<GraphNode>(
    `WITH root AS (
      SELECT id FROM nodes WHERE id = '${safeId}' AND kind IN ('function','method') LIMIT 1
    )
    SELECT DISTINCT n.id, COALESCE(n.name, n.id) AS label, n.kind, n.file, n.line
    FROM nodes n
    WHERE n.id IN (
      SELECT source FROM edges WHERE kind = 'call' AND (source IN (SELECT id FROM root) OR target IN (SELECT id FROM root))
      UNION
      SELECT target FROM edges WHERE kind = 'call' AND (source IN (SELECT id FROM root) OR target IN (SELECT id FROM root))
      UNION
      SELECT id FROM root
    )
    LIMIT 120`,
  );

  const edgeRows = await runSql<GraphEdge>(
    `WITH root AS (
      SELECT id FROM nodes WHERE id = '${safeId}' AND kind IN ('function','method') LIMIT 1
    ), pair AS (
      SELECT source, target, kind FROM edges
      WHERE kind = 'call'
        AND (
          source IN (SELECT id FROM root) OR target IN (SELECT id FROM root)
        )
    )
    SELECT source, target, kind FROM pair LIMIT 240`,
  );

  return c.json({
    nodes: nodeRows,
    edges: edgeRows,
  });
});

app.get("/api/graph/functions/search", async (c) => {
  const q = (c.req.query("q") ?? "").trim();
  if (q.length < 2) return c.json([]);
  const safeQ = q.replace(/'/g, "''");
  const rows = await runSql<{
    id: string;
    name: string;
    file: string | null;
    line: number | null;
    package: string | null;
  }>(
    `SELECT id, name, file, line, package
     FROM nodes
     WHERE kind IN ('function','method')
       AND name LIKE '%${safeQ}%'
     ORDER BY name
     LIMIT 30`,
  );
  return c.json(rows);
});

serve({ fetch: app.fetch, port: PORT }, () => {
  // eslint-disable-next-line no-console
  console.log(`API listening on http://localhost:${PORT}`);
});
