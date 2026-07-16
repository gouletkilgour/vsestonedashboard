using Pkg
Pkg.add(["HTTP", "JSON3", "Dates"])

using HTTP, JSON3, Dates

# -- StatsCan WDS API ---------------------------------------------------------
# Table    : 36-10-0660-01  Distributions of household economic accounts,
#            wealth, by characteristic, Canada, quarterly
# Dimensions used (coordinate = "1.<stat>.<quintile>.<wealth>.0.0.0.0.0.0"):
#   2 Statistics      -> Value (1), Distribution of value (2), Value per household (3)
#   3 Characteristics -> wealth quintiles (53-57)
#   4 Wealth          -> asset / liability / net worth categories (1-11)
# Docs: https://www.statcan.gc.ca/en/developers/wds/user-guide
# -----------------------------------------------------------------------------

const QUINTILES = [
    "Lowest wealth quintile"  => 53,
    "Second wealth quintile"  => 54,
    "Third wealth quintile"   => 55,
    "Fourth wealth quintile"  => 56,
    "Highest wealth quintile" => 57,
]

const STATS = [
    "Value"                 => 1,
    "Distribution of value" => 2,
    "Value per household"   => 3,
]

const WEALTH_TYPES = [
    "Total assets"                => 1,
    "Financial assets"            => 2,
    "Life insurance and pensions" => 3,
    "Other financial assets"      => 4,
    "Non-financial assets"        => 5,
    "Real estate"                 => 6,
    "Other non-financial assets"  => 7,
    "Total liabilities"           => 8,
    "Mortgage liabilities"        => 9,
    "Other liabilities"           => 10,
    "Net worth (wealth)"          => 11,
]

const PRODUCT_ID    = 36100660
const START_DATE     = Date(2010, 10, 1)   # Q4 2010
const N_PERIODS      = 90                  # buffer of recent quarters; filtered to START_DATE onward
const META_ENDPOINT  = "https://www150.statcan.gc.ca/t1/wds/rest/getSeriesInfoFromCubePidCoord"
const DATA_ENDPOINT  = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods"

coordinate(stat_id, quintile_id, wealth_id) = "1.$(stat_id).$(quintile_id).$(wealth_id).0.0.0.0.0.0"

println("Looking up vector IDs for wealth distribution series...")

combo_ids = [(qid, sid, wid) for (_, qid) in QUINTILES for (_, sid) in STATS for (_, wid) in WEALTH_TYPES]

coords_payload = [Dict("productId" => PRODUCT_ID, "coordinate" => coordinate(sid, qid, wid))
                   for (qid, sid, wid) in combo_ids]

meta_resp = HTTP.post(META_ENDPOINT, ["Content-Type" => "application/json"], JSON3.write(coords_payload))
meta_parsed = JSON3.read(String(meta_resp.body))

vector_for_coord = Dict{String, Int}()
for item in meta_parsed
    item[:status] == "SUCCESS" || error("Metadata API error: $(item[:status])")
    vector_for_coord[item[:object][:coordinate]] = item[:object][:vectorId]
end

vector_ids = Int[]
key_for_vector = Dict{Int, Tuple{String,String,String}}()
for (quintile, qid) in QUINTILES, (stat, sid) in STATS, (wealth, wid) in WEALTH_TYPES
    vid = vector_for_coord[coordinate(sid, qid, wid)]
    push!(vector_ids, vid)
    key_for_vector[vid] = (quintile, stat, wealth)
end

println("Fetching data for $(length(vector_ids)) series from Statistics Canada...")

data_payload = JSON3.write([Dict("vectorId" => v, "latestN" => N_PERIODS) for v in vector_ids])
data_resp = HTTP.post(DATA_ENDPOINT, ["Content-Type" => "application/json"], data_payload)
data_parsed = JSON3.read(String(data_resp.body))

function quarter_label(d::Date)
    q = div(month(d) - 1, 3) + 1
    return "$(year(d)) Q$(q)"
end

data = Dict{String, Dict{String, Dict{String, Dict{String, Vector}}}}()
for (quintile, _) in QUINTILES
    data[quintile] = Dict{String, Dict{String, Dict{String, Vector}}}()
    for (stat, _) in STATS
        data[quintile][stat] = Dict{String, Dict{String, Vector}}()
    end
end

for item in data_parsed
    item[:status] == "SUCCESS" || error("Data API error: $(item[:status])")
    vid = item[:object][:vectorId]
    quintile, stat, wealth = key_for_vector[vid]
    xs     = String[]   # ISO dates, so the chart's time axis reflects true elapsed time
    labels = String[]   # "20XX QN" labels for hover text and Q4 tick marks
    ys     = Float64[]
    for p in item[:object][:vectorDataPoint]
        d = Date(string(p[:refPer]))
        d < START_DATE && continue
        isnothing(p[:value]) && continue   # 2010-2019 only report Q4; skip the unpublished quarters
        push!(xs, string(d))
        push!(labels, quarter_label(d))
        push!(ys, round(Float64(p[:value]), digits=1))
    end
    data[quintile][stat][wealth] = Dict("x" => xs, "label" => labels, "y" => ys)
end

data_json = JSON3.write(data)
println("Data fetched. Building HTML...")

html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Wealth Distribution and Composition</title>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f5f5f5;
      color: #222;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    header {
      padding: 1.25rem 2rem;
      background: #fff;
      border-bottom: 1px solid #e0e0e0;
    }

    header h1 {
      font-size: 1.15rem;
      font-weight: 600;
      letter-spacing: 0.01em;
    }

    main {
      flex: 1;
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1.5rem;
      padding: 1.5rem 2rem;
      min-height: 0;
    }

    section {
      background: #fff;
      border: 1px solid #e0e0e0;
      border-radius: 6px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      min-height: 500px;
    }

    .section-label {
      font-size: 0.7rem;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #888;
      padding: 0.75rem 1.25rem;
      border-bottom: 1px solid #e0e0e0;
      background: #fafafa;
      flex-shrink: 0;
    }

    .chart-controls {
      padding: 0.6rem 1rem;
      border-bottom: 1px solid #e0e0e0;
      background: #fafafa;
      flex-shrink: 0;
      display: flex;
      align-items: center;
      gap: 1rem;
      flex-wrap: wrap;
    }

    .ctrl-group {
      display: flex;
      align-items: center;
      gap: 0.4rem;
    }

    .chart-ctrl-label {
      font-size: 0.75rem;
      font-weight: 500;
      color: #777;
    }

    .chart-controls select {
      font-family: inherit;
      font-size: 0.82rem;
      padding: 0.22rem 0.5rem;
      border: 1px solid #d0d0d0;
      border-radius: 4px;
      background: #fff;
      color: #222;
      cursor: pointer;
      outline: none;
    }

    .chart-controls select:focus {
      border-color: #636efa;
      box-shadow: 0 0 0 2px rgba(99,110,250,0.15);
    }

    #chart { flex: 1; min-height: 420px; }

    .prose {
      flex: 1;
      padding: 1.5rem 1.75rem;
      line-height: 1.7;
      font-size: 0.93rem;
      overflow: auto;
    }

    .prose h2 { font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem; }
    .prose h2:not(:first-child) { margin-top: 1.25rem; }
    .prose p  { color: #444; margin-bottom: 1rem; }
    .prose p:last-child { margin-bottom: 0; }
    .prose strong { color: #222; font-weight: 600; }
    .prose p.indent-1 { margin-left: 1.25rem; }
    .prose p.indent-2 { margin-left: 2.5rem; }

    .source { font-size: 0.75rem; color: #aaa; margin-top: 1.25rem; }

    @media (max-width: 900px) { main { grid-template-columns: 1fr; } }
  </style>
</head>
<body>

<header>
  <h1>Wealth Distribution and Composition</h1>
</header>

<main>
  <section>
    <div class="section-label">About this data</div>
    <div class="prose">

      <p>
        This chart shows how household assets, liabilities, and net worth (wealth) are distributed across households, grouped into five wealth quintiles.
      </p>

      <h2>Unit of Analysis</h2>
      <p>
        These series are based on household (not individual) wealth. Households are ranked and grouped into quintiles by net worth, from the lowest quintile (least wealthy 20% of households) to the highest quintile (wealthiest 20% of households).
      </p>

      <h2>Statistics</h2>
      <p>
        <strong>Value</strong> is the aggregate dollar amount held by all households in a given quintile, expressed in millions of dollars.
      </p>
      <p>
        <strong>Distribution of value</strong> is the share of the national total held by a given quintile, expressed as a percentage.
      </p>
      <p>
        <strong>Value per household</strong> is the average dollar amount per household within a given quintile.
      </p>

      <h2>Wealth Categories</h2>
      <p>
        Net worth (wealth) = Total assets − Total liabilities
      </p>
      <p class="indent-1">
        Total assets = Financial assets + Non-financial assets
      </p>
      <p class="indent-2">
        Financial assets = Life insurance and pensions (excludes public plans such as OAS, GIS, and CPP/QPP) + Other financial assets (includes total currency and deposits, Canadian short-term paper, Canadian bonds and debentures, foreign investments in paper and bonds, mortgages, equity and investment funds, and other receivables)
      </p>
      <p class="indent-2">
        Non-financial assets = Real estate + Other non-financial assets (includes consumer durables, machinery and equipment, and intellectual property products; excludes accumulation of value of collectibles)
      </p>
      <p class="indent-1">
        Total liabilities = Mortgage liabilities + Other liabilities (includes credit cards, retail store and gasoline station cards, vehicle loans, lines of credit, student loans, other loans, and other money owed)
      </p>

      <p class="source">
        Data source: Statistics Canada, Table 36-10-0660-01
      </p>
    </div>
  </section>

  <section>
    <div class="section-label">Chart</div>
    <div class="chart-controls">
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Wealth quintile:</span>
        <select id="quintile-select">
          <option value="Lowest wealth quintile">Lowest wealth quintile</option>
          <option value="Second wealth quintile">Second wealth quintile</option>
          <option value="Third wealth quintile">Third wealth quintile</option>
          <option value="Fourth wealth quintile">Fourth wealth quintile</option>
          <option value="Highest wealth quintile" selected>Highest wealth quintile</option>
        </select>
      </div>
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Statistic:</span>
        <select id="stat-select">
          <option value="Value">Value</option>
          <option value="Distribution of value" selected>Distribution of value</option>
          <option value="Value per household">Value per household</option>
        </select>
      </div>
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Wealth type:</span>
        <select id="wealth-select">
          <option value="Net worth (wealth)" selected>Net worth (wealth)</option>
          <option value="Total assets">&nbsp;&nbsp;Total assets</option>
          <option value="Financial assets">&nbsp;&nbsp;&nbsp;&nbsp;Financial assets</option>
          <option value="Life insurance and pensions">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Life insurance and pensions</option>
          <option value="Other financial assets">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Other financial assets</option>
          <option value="Non-financial assets">&nbsp;&nbsp;&nbsp;&nbsp;Non-financial assets</option>
          <option value="Real estate">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Real estate</option>
          <option value="Other non-financial assets">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Other non-financial assets</option>
          <option value="Total liabilities">&nbsp;&nbsp;Total liabilities</option>
          <option value="Mortgage liabilities">&nbsp;&nbsp;&nbsp;&nbsp;Mortgage liabilities</option>
          <option value="Other liabilities">&nbsp;&nbsp;&nbsp;&nbsp;Other liabilities</option>
        </select>
      </div>
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Frequency:</span>
        <select id="freq-select">
          <option value="Quarterly">Quarterly</option>
          <option value="Annual" selected>Annual</option>
        </select>
      </div>
    </div>
    <div id="chart"></div>
  </section>
</main>

<script>
  const DATA = $(data_json);

  const STAT_INFO = {
    "Value":                 { axisTitle: "Value (\$ millions)",          hoverFmt: "\$%{customdata[1]:,.0f}M" },
    "Distribution of value": { axisTitle: "Share of Total (%)",          hoverFmt: "%{customdata[1]:.1f}%" },
    "Value per household":   { axisTitle: "Value per Household (\$)",     hoverFmt: "\$%{customdata[1]:,.0f}" },
  };

  function titleCaseWord(w) {
    return w.split("-").map(p => p.charAt(0).toUpperCase() + p.slice(1).toLowerCase()).join("-");
  }

  function titleCase(str) {
    const minor = new Set(["and", "of", "in", "the", "a", "an"]);
    return str.split(" ").map((w, i) => (i > 0 && minor.has(w.toLowerCase())) ? w.toLowerCase() : titleCaseWord(w)).join(" ");
  }

  // Builds a y-axis label like "Share of Total Net Worth" or "Share of Total Real
  // Estate Wealth" instead of a generic "Share of Total (%)", so it's clear which
  // pool the percentage is a share of.
  function shareAxisLabel(wealth) {
    const name = titleCase(wealth.replace(" (wealth)", ""));
    const lower = name.toLowerCase();
    const prefix = lower.startsWith("total ") ? "Share of " : "Share of Total ";
    const needsWealthSuffix = !(lower.endsWith("assets") || lower.endsWith("liabilities") || lower.endsWith("worth"));
    return prefix + name + (needsWealthSuffix ? " Wealth" : "") + " (%)";
  }

  // Decomposable wealth types are shown as a stacked bar chart of their immediate
  // parts (so composition is visible), but only for the dollar-based statistics,
  // where the parts genuinely sum to the total. Everything else - leaf categories,
  // Net worth, and a composite's own "Distribution of value" (which can't be
  // decomposed into parts that sum correctly, see below) - is a single line.
  const DECOMPOSITIONS = {
    "Total assets":         ["Financial assets", "Non-financial assets"],
    "Financial assets":     ["Life insurance and pensions", "Other financial assets"],
    "Non-financial assets": ["Real estate", "Other non-financial assets"],
    "Total liabilities":    ["Mortgage liabilities", "Other liabilities"],
  };

  const COMPONENT_COLORS = ["#636efa", "#ef553b"];

  let currentQuintile = "Highest wealth quintile";
  let currentStat     = "Distribution of value";
  let currentWealth   = "Net worth (wealth)";
  let currentFreq     = "Annual";

  const QUARTERLY_START = "2019-10-01";

  // "Annual" keeps only each year's Q4 reading (the only period published for
  // 2010-2019 anyway); "Quarterly" keeps the full quarterly resolution, starting
  // where it becomes available, Q4 2019 onward.
  function filterByFrequency(s, freq) {
    const idx = [];
    s.label.forEach((lab, i) => {
      if (freq === "Annual" ? lab.endsWith("Q4") : s.x[i] >= QUARTERLY_START) idx.push(i);
    });
    return {
      x: idx.map(i => s.x[i]),
      label: idx.map(i => s.label[i]),
      y: idx.map(i => s.y[i]),
    };
  }

  function customData(s) {
    return s.label.map((lab, i) => [lab, s.y[i]]);
  }

  // A bar whose value rounds to exactly 0 renders with zero height - visually
  // indistinguishable from empty space, and nothing to hover over. Overlay a small
  // marker only at those points so they stay hoverable; ordinary non-zero bars are
  // left alone since their own rendered rectangle already provides a hover target.
  // Re-using the bar's own customdata keeps the tooltip showing that part's real
  // value rather than anything derived. `stacked` controls the marker's y position:
  // true sums a running cumulative total (for stacked bars, so the dot lands at the
  // segment's true on-screen position); false places it directly at the bar's own
  // value (for grouped/ungrouped bars, which don't stack).
  function withHoverMarkers(traces, stacked = true) {
    const cum = new Array(traces[0].y.length).fill(0);
    const markers = traces.map(t => ({
      x: t.x,
      y: t.y.map((v, i) => {
        if (v == null) return null;
        if (stacked) cum[i] += v;
        return v === 0 ? (stacked ? cum[i] : v) : null;
      }),
      customdata: t.customdata,
      type: "scatter",
      mode: "markers",
      marker: { size: 5, color: t.marker.color },
      hovertemplate: t.hovertemplate,
      showlegend: false,
    }));
    return traces.concat(markers);
  }

  function buildBarTrace(quintile, stat, wealth, freq, color, labelOverride) {
    const s = filterByFrequency(DATA[quintile][stat][wealth], freq);
    const label = labelOverride || wealth;
    return {
      x: s.x,
      y: s.y,
      customdata: customData(s),
      name: label,
      type: "bar",
      marker: { color },
      hovertemplate: "%{customdata[0]}<br>" + label + ": " + STAT_INFO[stat].hoverFmt + "<extra></extra>",
    };
  }

  // The green connected-line-and-point trace showing a composite's own real total,
  // overlaid on top of its component bars - so there's always something to hover
  // that reports the whole, not just the parts.
  function buildTotalLine(quintile, stat, wealth, freq) {
    const s = filterByFrequency(DATA[quintile][stat][wealth], freq);
    return {
      x: s.x,
      y: s.y,
      customdata: customData(s),
      name: wealth,
      type: "scatter",
      mode: "lines+markers",
      marker: { size: 6, color: "#00aa7a" },
      line: { color: "#00aa7a", width: 2 },
      hovertemplate: "%{customdata[0]}<br>" + wealth + ": " + STAT_INFO[stat].hoverFmt + "<extra></extra>",
    };
  }

  function buildTrace(quintile, stat, wealth, freq) {
    const decomp = DECOMPOSITIONS[wealth];

    // Net worth = Total assets - Total liabilities. For the dollar-based stats,
    // show assets and liabilities as their own bars (each a real, directly
    // reported amount) side by side, with Net worth itself as a connected line
    // showing how the two nets out over time.
    if (wealth === "Net worth (wealth)" && stat !== "Distribution of value") {
      const bars = withHoverMarkers([
        buildBarTrace(quintile, stat, "Total assets", freq, COMPONENT_COLORS[0]),
        buildBarTrace(quintile, stat, "Total liabilities", freq, COMPONENT_COLORS[1]),
      ], false);
      return bars.concat([buildTotalLine(quintile, stat, wealth, freq)]);
    }

    // "Distribution of value" for a part is that part's own share of the national
    // total for that specific category (e.g. Financial assets is a share of the
    // national financial-assets pool, Total assets a share of the national total-
    // assets pool). Those pools differ, so the parts would not sum to the parent's
    // share - so this statistic is never broken down, even for composite types.
    if (decomp && stat !== "Distribution of value") {
      const bars = withHoverMarkers(decomp.map((component, i) =>
        buildBarTrace(quintile, stat, component, freq, COMPONENT_COLORS[i])
      ));
      return bars.concat([buildTotalLine(quintile, stat, wealth, freq)]);
    }
    const s = filterByFrequency(DATA[quintile][stat][wealth], freq);
    return [{
      x: s.x,
      y: s.y,
      customdata: customData(s),
      name: wealth,
      type: "scatter",
      mode: "lines+markers",
      marker: { size: 4, color: "#636efa" },
      line: { color: "#636efa", width: 2 },
      hovertemplate: "%{customdata[0]}<br>" + STAT_INFO[stat].hoverFmt + "<extra></extra>",
    }];
  }

  var MARGIN_T = 50, MARGIN_B = 160;

  function buildLayout(quintile, stat, wealth, freq) {
    var el      = document.getElementById("chart");
    var plotH   = Math.max((el.offsetHeight || 480) - MARGIN_T - MARGIN_B, 80);
    var legendY = -(75 / plotH);
    var noteY   = -((MARGIN_B - 15) / plotH);
    var isNetWorthSplit = wealth === "Net worth (wealth)" && stat !== "Distribution of value";
    var isBreakdown = (!!DECOMPOSITIONS[wealth] && stat !== "Distribution of value") || isNetWorthSplit;
    var s = filterByFrequency(DATA[quintile][stat][wealth], freq);
    var tickvals = [], ticktext = [];
    s.label.forEach(function(lab, i) {
      if (lab.endsWith("Q4")) { tickvals.push(s.x[i]); ticktext.push(lab); }
    });
    return {
      title: { text: titleCase(wealth.replace(" (wealth)", "")) + " \\u2013 " + titleCase(quintile) + " \\u2013 Canada" },
      xaxis: { title: { text: "Quarter" }, type: "date", tickmode: "array", tickvals: tickvals, ticktext: ticktext },
      yaxis: { title: { text: stat === "Distribution of value" ? shareAxisLabel(wealth) : STAT_INFO[stat].axisTitle } },
      barmode: isNetWorthSplit ? "group" : "relative",
      legend: { x: 0.5, xanchor: "center", y: legendY, orientation: "h" },
      showlegend: isBreakdown,
      margin: { l: 70, b: MARGIN_B, r: 20, t: MARGIN_T },
      paper_bgcolor: "white",
      plot_bgcolor: "#E5ECF6",
      annotations: [{
        xref: "paper", yref: "paper",
        x: 0.5, y: noteY,
        xanchor: "center", yanchor: "bottom",
        showarrow: false,
        text: "Chart created by the Stone Centre on Wealth and Income Inequality<br>at the Vancouver School of Economics (UBC) using data from Statistics Canada",
        font: { size: 9, color: "#b0b0b0" },
      }],
    };
  }

  function update() {
    Plotly.react("chart", buildTrace(currentQuintile, currentStat, currentWealth, currentFreq), buildLayout(currentQuintile, currentStat, currentWealth, currentFreq), { responsive: true });
  }

  document.getElementById("quintile-select").addEventListener("change", function () {
    currentQuintile = this.value;
    update();
  });

  document.getElementById("stat-select").addEventListener("change", function () {
    currentStat = this.value;
    update();
  });

  document.getElementById("wealth-select").addEventListener("change", function () {
    currentWealth = this.value;
    update();
  });

  document.getElementById("freq-select").addEventListener("change", function () {
    currentFreq = this.value;
    update();
  });

  Plotly.newPlot("chart", buildTrace(currentQuintile, currentStat, currentWealth, currentFreq), buildLayout(currentQuintile, currentStat, currentWealth, currentFreq), { responsive: true });

  var resizeTimer;
  new ResizeObserver(function() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function() {
      Plotly.relayout("chart", buildLayout(currentQuintile, currentStat, currentWealth, currentFreq));
    }, 50);
  }).observe(document.getElementById("chart"));
</script>

</body>
</html>"""

output = joinpath(@__DIR__, "wealth_distribution.html")
write(output, html)
println("Saved -> $output")

if Sys.isapple()
    run(`open $output`)
elseif Sys.iswindows()
    run(`cmd /c start $output`)
else
    run(`xdg-open $output`)
end
