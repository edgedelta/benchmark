import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const SCENARIOS = ["Pass-Through", "Filter", "Mask", "Lookup"];
const NAME2KEY = { "Edge Delta": "ed", "Bindplane": "bp", "OpenTelemetry Collector": "otel", "Cribl": "cribl" };

export function num(s) {
  if (s == null) return null;
  const t = String(s).trim();
  if (t === "" || /^n\/?a$/i.test(t) || /failed/i.test(t)) return null;
  const m = t.replace(/,/g, "").match(/-?\d+(\.\d+)?/);
  return m ? parseFloat(m[0]) : null;
}

function cells(line) { return line.split("|").slice(1, -1).map((c) => c.trim()); }

// First markdown table appearing after a line matching `afterRe`.
export function tableAfter(lines, afterRe) {
  let i = lines.findIndex((l) => afterRe.test(l));
  if (i < 0) return null;
  while (i < lines.length && !lines[i].trim().startsWith("|")) i++;
  if (i >= lines.length) return null;
  const headers = cells(lines[i]); i++;
  if (i < lines.length && lines[i].trim().startsWith("|") && cells(lines[i]).every((c) => /^:?-+:?$/.test(c))) i++;
  const rows = [];
  while (i < lines.length && lines[i].trim().startsWith("|")) { rows.push(cells(lines[i])); i++; }
  return { headers, rows };
}

const colIndex = (headers, re) => headers.findIndex((h) => re.test(h));

export function parseReport(body, tag) {
  const lines = body.split(/\r?\n/);
  const d = String(tag).replace(/[^0-9]/g, "");
  const run = {
    runId: tag,
    date: `${d.slice(0,4)}-${d.slice(4,6)}-${d.slice(6,8)}`,
    scenarios: SCENARIOS.slice(),
    versions: {},
    vendors: {},
  };
  for (const k of Object.values(NAME2KEY)) {
    run.vendors[k] = { name: null, avg: [null,null,null,null], peak: [null,null,null,null], cpu: null, mem: null, perCpu: null };
  }

  SCENARIOS.forEach((sc, si) => {
    const t = tableAfter(lines, new RegExp(`Benchmark Scenario:\\s*${sc}`, "i"));
    if (!t) return;
    const ai = colIndex(t.headers, /avg throughput/i);
    const pi = colIndex(t.headers, /peak throughput/i);
    t.rows.forEach((r) => {
      const key = NAME2KEY[r[0]];
      if (!key) return;
      run.vendors[key].name = r[0];
      if (ai >= 0) run.vendors[key].avg[si] = num(r[ai]);
      if (pi >= 0) run.vendors[key].peak[si] = num(r[pi]);
    });
  });

  const eff = tableAfter(lines, /Resource Efficiency \(Across Scenarios\)/i);
  if (eff) {
    const ci = colIndex(eff.headers, /avg cpu/i);
    const mi = colIndex(eff.headers, /peak memory/i);
    const pci = colIndex(eff.headers, /per cpu/i);
    eff.rows.forEach((r) => {
      const key = NAME2KEY[r[0]]; if (!key) return;
      if (ci >= 0) run.vendors[key].cpu = num(r[ci]);
      if (mi >= 0) run.vendors[key].mem = num(r[mi]);
      if (pci >= 0) run.vendors[key].perCpu = num(r[pci]);
    });
  }

  const ver = tableAfter(lines, /Tested Agent Versions/i);
  if (ver) {
    const vi = colIndex(ver.headers, /version/i);
    ver.rows.forEach((r) => { const key = NAME2KEY[r[0]]; if (key && vi >= 0) run.versions[key] = r[vi]; });
  }
  return run;
}

// CLI: node backfill.mjs <out.json> [owner/repo]
if (import.meta.url === `file://${process.argv[1]}`) {
  const out = process.argv[2] || "history.json";
  const repo = process.argv[3];
  const repoArgs = repo ? ["--repo", repo] : [];
  const list = JSON.parse(execFileSync("gh", ["release", "list", ...repoArgs, "--limit", "100", "--json", "tagName,createdAt"], { encoding: "utf8" }));
  const runs = [];
  for (const rel of list) {
    try {
      const body = execFileSync("gh", ["release", "view", rel.tagName, ...repoArgs, "--json", "body", "-q", ".body"], { encoding: "utf8" });
      const run = parseReport(body, rel.tagName);
      const hasData = Object.values(run.vendors).some((v) => v.avg.some((x) => x != null));
      if (hasData) runs.push(run);
      else console.warn(`skip ${rel.tagName}: no parseable throughput data`);
    } catch (e) { console.warn(`skip ${rel.tagName}: ${e.message}`); }
  }
  runs.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  writeFileSync(out, JSON.stringify(runs, null, 2) + "\n");
  console.log(`backfilled ${runs.length} runs -> ${out}`);
}
