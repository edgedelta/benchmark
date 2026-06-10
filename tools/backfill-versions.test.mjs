import { test } from "node:test";
import assert from "node:assert/strict";
import { versionAtDate, applyVersions } from "./backfill-versions.mjs";

const list = [
  { version: "v1.0.0", date: "2026-01-05" },
  { version: "v1.1.0", date: "2026-03-10" },
  { version: "v1.2.0", date: "2026-05-26" },
];

test("returns null before the earliest release", () => {
  assert.equal(versionAtDate(list, "2026-01-04"), null);
});

test("returns the version released exactly on the date", () => {
  assert.equal(versionAtDate(list, "2026-03-10"), "v1.1.0");
});

test("returns the latest release on or before the date", () => {
  assert.equal(versionAtDate(list, "2026-04-01"), "v1.1.0");
  assert.equal(versionAtDate(list, "2026-06-08"), "v1.2.0");
});

test("applyVersions fills versions per run date, all four vendors", () => {
  const versionsData = {
    ed: [{ version: "v2.13.0", date: "2026-03-10" }, { version: "v2.18.0", date: "2026-05-26" }],
    cribl: [{ version: "4.17.0", date: "2026-03-11" }],
  };
  const history = [
    { runId: "a", date: "2026-03-12", versions: {}, vendors: {} },
    { runId: "b", date: "2026-06-08", versions: {}, vendors: {} },
  ];
  const out = applyVersions(history, versionsData);
  assert.equal(out[0].versions.ed, "v2.13.0");
  assert.equal(out[0].versions.cribl, "4.17.0");
  assert.equal(out[1].versions.ed, "v2.18.0");
});

test("applyVersions does NOT overwrite a version already present (real run data wins)", () => {
  const versionsData = { ed: [{ version: "v2.13.0", date: "2026-03-10" }] };
  const history = [{ runId: "a", date: "2026-03-12", versions: { ed: "v9.9.9" }, vendors: {} }];
  const out = applyVersions(history, versionsData);
  assert.equal(out[0].versions.ed, "v9.9.9");
});

test("applyVersions ignores the _comment key in version data", () => {
  const versionsData = { _comment: "notes", ed: [{ version: "v2.13.0", date: "2026-03-10" }] };
  const history = [{ runId: "a", date: "2026-03-12", versions: {}, vendors: {} }];
  const out = applyVersions(history, versionsData);
  assert.equal(out[0].versions._comment, undefined);
  assert.equal(out[0].versions.ed, "v2.13.0");
});
