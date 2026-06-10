import { readFileSync, writeFileSync } from "node:fs";

// Given a list of { version, date } (date = "YYYY-MM-DD"), return the version
// with the latest date on or before `date`, or null if none qualifies.
export function versionAtDate(list, date) {
  const eligible = (list || [])
    .filter((e) => e && e.date && e.date <= date)
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return eligible.length ? eligible[eligible.length - 1].version : null;
}

// For each run, fill versions[vendor] with the GA version active on the run date.
// Existing (real) version values are preserved — only missing ones are filled.
// The "_comment" key in versionsData (if present) is ignored.
export function applyVersions(history, versionsData) {
  const keys = Object.keys(versionsData).filter((k) => k !== "_comment");
  return history.map((run) => {
    const versions = { ...(run.versions || {}) };
    for (const k of keys) {
      if (versions[k] == null) {
        const v = versionAtDate(versionsData[k], run.date);
        if (v != null) versions[k] = v;
      }
    }
    return { ...run, versions };
  });
}

// CLI: node backfill-versions.mjs <history.json> <agent-versions.json> <out.json>
if (import.meta.url === `file://${process.argv[1]}`) {
  const [historyPath, versionsPath, outPath] = process.argv.slice(2);
  if (!historyPath || !versionsPath || !outPath) {
    console.error("usage: backfill-versions.mjs <history.json> <agent-versions.json> <out.json>");
    process.exit(1);
  }
  const history = JSON.parse(readFileSync(historyPath, "utf8"));
  const versionsData = JSON.parse(readFileSync(versionsPath, "utf8"));
  const out = applyVersions(history, versionsData);
  writeFileSync(outPath, JSON.stringify(out, null, 2) + "\n");
  console.log(`applied versions to ${out.length} runs -> ${outPath}`);
}
