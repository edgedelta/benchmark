import { test } from "node:test";
import assert from "node:assert/strict";
import { parseReport, num } from "./backfill.mjs";

test("num parses formatted values and N/A", () => {
  assert.equal(num("61,507.40 logs/sec"), 61507.40);
  assert.equal(num("381.7%"), 381.7);
  assert.equal(num("212.0 MB"), 212.0);
  assert.equal(num("N/A"), null);
  assert.equal(num("N/A ❌ Failed to start"), null);
});

const BODY = `# Benchmark Report
**Date:** 2026-06-08 | **Run ID:** x

## Benchmark Scenario: Pass-Through
### Performance Comparison
| Vendor | Avg Throughput | Peak Throughput | Total Logs | Avg CPU | Peak Memory | Rank |
|--------|----------------|-----------------|------------|---------|-------------|------|
| Edge Delta | 61,507.40 logs/sec | 61,974.55 logs/sec | 3,690,086 | 381.7% | 212.0 MB | 1 |
| Bindplane | 30,896.33 logs/sec | 32,517.43 logs/sec | 1,856,200 | 204.1% | 287.5 MB | 2 |
| Cribl | N/A | N/A | N/A | N/A | N/A | N/A |

## Benchmark Scenario: Filter
### Performance Comparison
| Vendor | Avg Throughput | Peak Throughput | Total Logs | Avg CPU | Peak Memory | Rank |
|--------|----------------|-----------------|------------|---------|-------------|------|
| Edge Delta | 49,809.38 logs/sec | 50,191.85 logs/sec | 2,988,320 | 451.1% | 228.4 MB | 1 |
| Cribl | 2,391.64 logs/sec | 2,527.62 logs/sec | 143,520 | 100.8% | 680 MB | 4 |

### Resource Efficiency (Across Scenarios)
| Vendor | Avg CPU | Avg Peak Memory | Throughput per CPU % |
|--------|---------|-----------------|----------------------|
| Edge Delta | 447.1% | 226.1 MB | 114.8 |
| Cribl | 100.9% | 751.0 MB | 22.5 |

## Tested Agent Versions
| Vendor | Version |
|--------|---------|
| Edge Delta | v1.2.3 |
| Cribl | v4.9 |
`;

test("parseReport extracts throughput, efficiency, versions", () => {
  const run = parseReport(BODY, "20260608-093535");
  assert.equal(run.runId, "20260608-093535");
  assert.equal(run.date, "2026-06-08");
  assert.equal(run.vendors.ed.avg[0], 61507.40);
  assert.equal(run.vendors.ed.peak[1], 50191.85);
  assert.equal(run.vendors.cribl.avg[0], null);    // Pass-Through N/A
  assert.equal(run.vendors.cribl.avg[1], 2391.64);  // Filter
  assert.equal(run.vendors.ed.cpu, 447.1);
  assert.equal(run.vendors.ed.mem, 226.1);
  assert.equal(run.vendors.ed.perCpu, 114.8);
  assert.equal(run.versions.ed, "v1.2.3");
});
