/* Pipeline Throughput Benchmark — driven by data/history.json */

const SCENARIOS = ["Pass-Through", "Filter", "Mask", "Lookup"];
const VENDORS = [
  { key: "ed",       name: "Edge Delta",              short: "Edge Delta" },
  { key: "bp",       name: "Bindplane",               short: "Bindplane" },
  { key: "otel",     name: "OpenTelemetry Collector", short: "OTel Collector" },
  { key: "cribl",    name: "Cribl",                   short: "Cribl" },
  { key: "fluentd",  name: "Fluentd",                 short: "Fluentd" },
  { key: "logstash", name: "Logstash",                short: "Logstash" },
];
const PALETTE = { ed: "#00DA63", bp: "#27A1FF", otel: "#9F4FFF", cribl: "#FF9554", fluentd: "#00C2D7", logstash: "#E6B800" };
const vendorColor = (k) => PALETTE[k];
const PLOT_H = 440;

const fmt = (n) => n == null ? "N/A" : n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmt0 = (n) => n.toLocaleString("en-US", { maximumFractionDigits: 0 });
const fmtK = (n) => n === 0 ? "0" : n >= 1000 ? (n / 1000) + "k" : String(n);

function niceScale(maxVal, targetTicks = 7) {
  if (!(maxVal > 0)) return { max: 10, ticks: [0, 10] };
  const rawStep = maxVal / targetTicks;
  const pow = Math.pow(10, Math.floor(Math.log10(rawStep)));
  const n = rawStep / pow;
  const niceStep = (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * pow;
  const max = Math.ceil(maxVal / niceStep) * niceStep;
  const ticks = [];
  for (let t = 0; t <= max + niceStep * 0.5; t += niceStep) ticks.push(Math.round(t));
  return { max, ticks: [...new Set(ticks)] };
}

/* ───── Throughput (grouped bars) ───── */
function ThroughputChart({ data, axisMax, ticks }) {
  return (
    <div className="tp">
      <div className="plot">
        {ticks.map((t) => (
          <div className="grid" key={t} style={{ bottom: (t / axisMax) * PLOT_H + "px" }}>
            <span className="ytick">{fmtK(t)}</span>
            <span className="gline" />
          </div>
        ))}
        <div className="groups">
          {SCENARIOS.map((sc, si) => (
            <div className="group" key={sc}>
              <div className="bars">
                {VENDORS.map((v) => {
                  const val = data[v.key][si];
                  if (val == null) {
                    return (
                      <div className="barslot" key={v.key} data-na="1">
                        <div className="na">N/A</div>
                        <div className="na-base" style={{ background: vendorColor(v.key) }} />
                      </div>
                    );
                  }
                  const h = (val / axisMax) * PLOT_H;
                  return (
                    <div className="barslot" key={v.key}>
                      <div className="bval" style={{ bottom: h + 8 + "px" }}>{fmt0(val)}</div>
                      <div className={"bar" + (v.key === "ed" ? " ed" : "")} style={{ height: h + "px", background: vendorColor(v.key) }}>
                        <div className="tip">
                          <div className="tip-v" style={{ color: vendorColor(v.key) }}>{v.name}</div>
                          <div className="tip-s">{sc}</div>
                          <div className="tip-n">{fmt(val)} <span>logs/sec</span></div>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>
      <div className="xaxis">{SCENARIOS.map((sc) => <div className="xlab" key={sc}>{sc}</div>)}</div>
    </div>
  );
}

/* ───── Resource Efficiency ───── */
function Bars({ title, unit, note, get, fmtv, better, markBest = true }) {
  const rows = VENDORS.map((v) => ({ v, val: get(v.key) }));
  const present = rows.filter((r) => r.val != null);
  const max = present.length ? Math.max(...present.map((r) => r.val)) : 1;
  const sorted = [...rows].sort((a, b) => {
    if (a.val == null) return 1;
    if (b.val == null) return -1;
    return better === "lower" ? a.val - b.val : b.val - a.val;
  });
  const bestKey = sorted.find((r) => r.val != null)?.v.key;
  return (
    <div className="effcard">
      <div className="eff-head"><div className="eff-title">{title}</div><div className="eff-note">{note}</div></div>
      <div className="eff-rows">
        {sorted.map((r, i) => {
          const w = r.val == null ? 0 : (r.val / max) * 100;
          const isBest = markBest && r.v.key === bestKey;
          return (
            <div className="eff-row" key={r.v.key}>
              <div className="eff-name">
                {r.v.key === "ed" && <span className="dot" style={{ background: vendorColor("ed") }} />}
                {r.v.short}
              </div>
              <div className="eff-track">
                <div className="eff-fill" style={{ width: w + "%", background: vendorColor(r.v.key), animationDelay: i * 70 + "ms" }} />
              </div>
              <div className={"eff-val" + (isBest ? " best" : "")}>
                {r.val == null ? "N/A" : fmtv(r.val)}<span className="eff-unit">{r.val == null ? "" : unit}</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function EfficiencyView({ eff }) {
  return (
    <div className="eff">
      <Bars title="Avg peak memory" unit=" MB" note="Lower is better" better="lower" get={(k) => eff[k].mem} fmtv={(v) => v.toFixed(1)} />
      <Bars title="Throughput per CPU %" unit="" note="Higher is better" better="higher" get={(k) => eff[k].perCpu} fmtv={(v) => v.toFixed(1)} />
      <Bars title="Avg CPU usage" unit="%" note="Cores consumed · context" better="higher" markBest={false} get={(k) => eff[k].cpu} fmtv={(v) => v.toFixed(1)} />
    </div>
  );
}

/* ───── Trend (line chart over time) ───── */
function TrendChart({ history, scenarioIndex, metric, visible, hover, setHover }) {
  const W = 1040, H = 440, padL = 58, padR = 18, padT = 18, padB = 42;
  const plotW = W - padL - padR, plotH = H - padT - padB;
  const n = history.length;

  const series = VENDORS.map((v) => {
    let prevVer = null;
    return {
      v,
      pts: history.map((r, i) => {
        const vd = r.vendors && r.vendors[v.key];
        const arr = vd ? vd[metric] : null;
        const val = arr && arr[scenarioIndex] != null ? arr[scenarioIndex] : null;
        const ver = r.versions && r.versions[v.key] != null ? r.versions[v.key] : null;
        const changed = ver != null && prevVer != null && ver !== prevVer;
        if (ver != null) prevVer = ver;
        return { i, val, date: r.date, ver, changed };
      }),
    };
  });

  const vals = [];
  series.forEach((s) => { if (visible.has(s.v.key)) s.pts.forEach((p) => { if (p.val != null) vals.push(p.val); }); });
  const { max: yMax, ticks } = niceScale(vals.length ? Math.max(...vals) : 10);

  const X = (i) => (n <= 1 ? padL + plotW / 2 : padL + (i / (n - 1)) * plotW);
  const Y = (val) => padT + plotH - (val / yMax) * plotH;
  const step = Math.max(1, Math.ceil(n / 8));

  React.useEffect(() => { setHover(null); }, [scenarioIndex, metric]);

  return (
    <div className="trend-plot">
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: "auto", display: "block" }}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={padL} x2={W - padR} y1={Y(t)} y2={Y(t)} stroke="var(--ed-border-1)" strokeWidth="1" />
            <text x={padL - 10} y={Y(t)} textAnchor="end" dominantBaseline="middle" fontFamily="var(--ed-font-mono)" fontSize="11" fill="var(--ed-text-secondary)">{fmtK(t)}</text>
          </g>
        ))}
        <line x1={padL} x2={W - padR} y1={Y(0)} y2={Y(0)} stroke="var(--ed-border-2)" strokeWidth="1" />
        {history.map((r, i) => (i % step === 0 || i === n - 1) ? (
          <text key={i} x={X(i)} y={H - padB + 20} textAnchor="middle" fontFamily="var(--ed-font-mono)" fontSize="10.5" fill="var(--ed-text-secondary)">{(r.date ?? "").slice(5)}</text>
        ) : null)}
        {series.map((s) => {
          if (!visible.has(s.v.key)) return null;
          const isEd = s.v.key === "ed";
          const segs = []; let cur = [];
          s.pts.forEach((p) => { if (p.val == null) { if (cur.length) segs.push(cur); cur = []; } else cur.push(p); });
          if (cur.length) segs.push(cur);
          return (
            <g key={s.v.key}>
              {segs.map((seg, k) => (
                <polyline key={k} fill="none" stroke={vendorColor(s.v.key)} strokeWidth={isEd ? 2.6 : 1.6}
                  strokeLinejoin="round" strokeLinecap="round" points={seg.map((p) => `${X(p.i)},${Y(p.val)}`).join(" ")} />
              ))}
              {s.pts.map((p) => {
                if (p.val == null) return null;
                const cx = X(p.i), cy = Y(p.val);
                const handlers = {
                  style: { cursor: "pointer" },
                  onMouseEnter: () => setHover({ key: s.v.key, name: s.v.name, val: p.val, date: p.date, ver: p.ver, changed: p.changed, x: cx, y: cy }),
                  onMouseLeave: () => setHover(null),
                };
                if (p.changed) {
                  const d = isEd ? 5 : 4.4;
                  return <path key={p.i} d={`M ${cx} ${cy - d} L ${cx + d} ${cy} L ${cx} ${cy + d} L ${cx - d} ${cy} Z`}
                    fill="var(--ed-surface-1)" stroke={vendorColor(s.v.key)} strokeWidth="2" {...handlers} />;
                }
                return <circle key={p.i} cx={cx} cy={cy} r={isEd ? 3.6 : 3} fill="var(--ed-surface-1)"
                  stroke={vendorColor(s.v.key)} strokeWidth="2" {...handlers} />;
              })}
            </g>
          );
        })}
      </svg>
      {hover && (
        <div className="trend-tip" style={{ left: (hover.x / W * 100) + "%", top: (hover.y / H * 100) + "%" }}>
          <div className="tip-v" style={{ color: vendorColor(hover.key) }}>{hover.name}</div>
          <div className="tip-s">{SCENARIOS[scenarioIndex]} · {hover.date}</div>
          <div className="tip-n">{fmt(hover.val)} <span>logs/sec</span></div>
          {hover.ver != null && <div className="tip-ver">{hover.changed ? "◆ updated to " : "version "}{hover.ver}</div>}
        </div>
      )}
    </div>
  );
}

/* ───── App ───── */
function App() {
  const [history, setHistory] = React.useState(null);
  const [err, setErr] = React.useState(null);
  const [metric, setMetric] = React.useState("avg");
  const [view, setView] = React.useState("throughput");
  const [scenarioIdx, setScenarioIdx] = React.useState(0);
  const [hidden, setHidden] = React.useState(() => new Set());
  const [hover, setHover] = React.useState(null);

  React.useEffect(() => {
    fetch("data/history.json", { cache: "no-cache" })
      .then((r) => { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then((h) => setHistory(Array.isArray(h) ? h : []))
      .catch((e) => setErr(e.message));
  }, []);

  if (err) return <div className="wrap"><div className="card state">Failed to load benchmark data: {err}</div></div>;
  if (history == null) return <div className="wrap"><div className="card state">Loading benchmark data…</div></div>;
  if (history.length === 0) return <div className="wrap"><div className="card state">No benchmark runs published yet.</div></div>;

  const latest = history[history.length - 1];
  const AVG = {}, PEAK = {}, EFF = {};
  VENDORS.forEach((v) => {
    const vd = latest.vendors?.[v.key] || {};
    AVG[v.key] = vd.avg || [null, null, null, null];
    PEAK[v.key] = vd.peak || [null, null, null, null];
    EFF[v.key] = { cpu: vd.cpu ?? null, mem: vd.mem ?? null, perCpu: vd.perCpu ?? null };
  });
  const data = metric === "avg" ? AVG : PEAK;

  const allLatest = [];
  VENDORS.forEach((v) => (AVG[v.key] || []).concat(PEAK[v.key] || []).forEach((x) => { if (x != null) allLatest.push(x); }));
  const { max: axisMax, ticks } = niceScale(allLatest.length ? Math.max(...allLatest) : 10);

  const visible = new Set(VENDORS.map((v) => v.key).filter((k) => !hidden.has(k)));

  const toggle = (k) => {
    if (view !== "trend") return;
    setHidden((prev) => { const n = new Set(prev); n.has(k) ? n.delete(k) : n.add(k); return n; });
  };

  return (
    <div className="wrap">
      <div className="card">
        <header className="head">
          <div className="brand">
            <div className="titles">
              <h1>Pipeline throughput benchmark</h1>
              <p className="sub">
                {view === "throughput" ? "Across four processing scenarios · logs/sec · higher is better"
                  : view === "efficiency" ? "Resource efficiency across all scenarios"
                  : "Trend over time · logs/sec · " + SCENARIOS[scenarioIdx]}
              </p>
            </div>
          </div>
          <div className="controls">
            <div className="seg">
              <button className={view === "throughput" ? "on" : ""} onClick={() => { setView("throughput"); setHover(null); }}>Throughput</button>
              <button className={view === "efficiency" ? "on" : ""} onClick={() => { setView("efficiency"); setHover(null); }}>Efficiency</button>
              <button className={view === "trend" ? "on" : ""} onClick={() => setView("trend")}>Trend</button>
            </div>
            <div className="seg">
              <button className={metric === "avg" ? "on" : ""} disabled={view === "efficiency"} onClick={() => setMetric("avg")}>Average</button>
              <button className={metric === "peak" ? "on" : ""} disabled={view === "efficiency"} onClick={() => setMetric("peak")}>Peak</button>
            </div>
          </div>
        </header>

        {view === "trend" && (
          <div className="seg seg-scn">
            {SCENARIOS.map((sc, i) => (
              <button key={sc} className={scenarioIdx === i ? "on" : ""} onClick={() => setScenarioIdx(i)}>{sc}</button>
            ))}
          </div>
        )}

        <div className="legend">
          {VENDORS.map((v) => {
            const off = view === "trend" && hidden.has(v.key);
            return (
              <div className={"leg" + (view === "trend" ? " leg-click" : "") + (off ? " off" : "")} key={v.key} onClick={() => toggle(v.key)}>
                <span className="sw" style={{ background: vendorColor(v.key) }} />
                <span className={v.key === "ed" ? "leg-ed" : ""}>{v.name}</span>
                {latest.versions?.[v.key] && <span className="leg-ver">{latest.versions[v.key]}</span>}
              </div>
            );
          })}
        </div>

        <div className="viewbody">
          {view === "throughput" && <ThroughputChart key={metric} data={data} axisMax={axisMax} ticks={ticks} />}
          {view === "efficiency" && <EfficiencyView eff={EFF} />}
          {view === "trend" && <TrendChart history={history} scenarioIndex={scenarioIdx} metric={metric} visible={visible} hover={hover} setHover={setHover} />}
        </div>

        <footer className="foot">
          <span>{latest.date} · run {latest.runId}{view === "trend" ? " · " + history.length + " runs" : ""}</span>
          <span className="na-key">{view === "trend" ? "◆ = agent version change · " : ""}N/A = scenario not supported by that vendor</span>
        </footer>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
