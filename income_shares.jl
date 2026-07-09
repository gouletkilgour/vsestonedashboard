using Pkg
Pkg.add(["HTTP", "JSON3", "Dates"])

using HTTP, JSON3, Dates

# -- StatsCan WDS API ---------------------------------------------------------
# Table  : 11-10-0055-01  High income tax filers in Canada
# Statistic: Share of income (dimension 4, member 11)
# Concepts: Market income (1), Total income (2), After-tax income (3)
# Groups  : Top 1% (3), Top 10% (5), Bottom 50% (10)
# Docs    : https://www.statcan.gc.ca/en/developers/wds/user-guide
# -----------------------------------------------------------------------------

# Each region maps group label => (market_vid, total_vid, aftertax_vid)
const REGIONS = [
    "Canada"                    => [
        "Top 1%"     => (62791037, 62802587, 62814137),
        "Top 10%"    => (62791087, 62802637, 62814187),
        "Bottom 50%" => (62791212, 62802762, 62814312),
    ],
    "Newfoundland and Labrador" => [
        "Top 1%"     => (62791587, 62803137, 62814687),
        "Top 10%"    => (62791637, 62803187, 62814737),
        "Bottom 50%" => (62791762, 62803312, 62814862),
    ],
    "Prince Edward Island"      => [
        "Top 1%"     => (62791862, 62803412, 62814962),
        "Top 10%"    => (62791912, 62803462, 62815012),
        "Bottom 50%" => (62792037, 62803587, 62815137),
    ],
    "Nova Scotia"               => [
        "Top 1%"     => (62792137, 62803687, 62815237),
        "Top 10%"    => (62792187, 62803737, 62815287),
        "Bottom 50%" => (62792312, 62803862, 62815412),
    ],
    "New Brunswick"             => [
        "Top 1%"     => (62792412, 62803962, 62815512),
        "Top 10%"    => (62792462, 62804012, 62815562),
        "Bottom 50%" => (62792587, 62804137, 62815687),
    ],
    "Quebec"                    => [
        "Top 1%"     => (62792687, 62804237, 62815787),
        "Top 10%"    => (62792737, 62804287, 62815837),
        "Bottom 50%" => (62792862, 62804412, 62815962),
    ],
    "Ontario"                   => [
        "Top 1%"     => (62792962, 62804512, 62816062),
        "Top 10%"    => (62793012, 62804562, 62816112),
        "Bottom 50%" => (62793137, 62804687, 62816237),
    ],
    "Manitoba"                  => [
        "Top 1%"     => (62793512, 62805062, 62816612),
        "Top 10%"    => (62793562, 62805112, 62816662),
        "Bottom 50%" => (62793687, 62805237, 62816787),
    ],
    "Saskatchewan"              => [
        "Top 1%"     => (62793787, 62805337, 62816887),
        "Top 10%"    => (62793837, 62805387, 62816937),
        "Bottom 50%" => (62793962, 62805512, 62817062),
    ],
    "Alberta"                   => [
        "Top 1%"     => (62794062, 62805612, 62817162),
        "Top 10%"    => (62794112, 62805662, 62817212),
        "Bottom 50%" => (62794237, 62805787, 62817337),
    ],
    "British Columbia"          => [
        "Top 1%"     => (62801762, 62813312, 62824862),
        "Top 10%"    => (62801812, 62813362, 62824912),
        "Bottom 50%" => (62801937, 62813487, 62825037),
    ],
]

const GROUPS    = ["Top 1%", "Top 10%", "Bottom 50%"]
const CONCEPTS  = ["Market income", "Total income", "After-tax income"]
const N_PERIODS = 50   # 1982–2023 annual; fetch up to 50 periods
const ENDPOINT  = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods"

function fetch_series(vector_ids::Vector{Int}, n::Int)
    body    = JSON3.write([Dict("vectorId" => v, "latestN" => n) for v in vector_ids])
    headers = ["Content-Type" => "application/json"]
    resp    = HTTP.post(ENDPOINT, headers, body)
    parsed  = JSON3.read(String(resp.body))

    results = Dict{Int, NamedTuple{(:years, :values), Tuple{Vector{Int}, Vector{Union{Float64,Nothing}}}}}()
    for item in parsed
        item[:status] == "SUCCESS" || error("API error: $(item[:status])")
        pts    = item[:object][:vectorDataPoint]
        vid    = item[:object][:vectorId]
        years  = [year(Date(string(p[:refPer]))) for p in pts]
        values = Union{Float64,Nothing}[isnothing(p[:value]) ? nothing : Float64(p[:value]) for p in pts]
        results[vid] = (years = years, values = values)
    end
    return results
end

println("Fetching income share data for Canada and provinces from Statistics Canada...")

all_vector_ids = [v for (_, groups) in REGIONS for (_, vids) in groups for v in vids]
raw = fetch_series(all_vector_ids, N_PERIODS)

# Build nested Dict: region -> group -> concept -> {x, y}
data = Dict{String, Dict{String, Dict{String, Dict{String, Vector}}}}()
for (region, groups) in REGIONS
    data[region] = Dict{String, Dict{String, Dict{String, Vector}}}()
    for (group, vids) in groups
        data[region][group] = Dict{String, Dict{String, Vector}}()
        for (concept, vid) in zip(CONCEPTS, vids)
            d = raw[vid]
            ys = [isnothing(v) ? nothing : round(v, digits=2) for v in d.values]
            data[region][group][concept] = Dict("x" => d.years, "y" => ys)
        end
    end
end

data_json = JSON3.write(data)
println("Data fetched. Building HTML...")

html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Income Shares</title>
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
      grid-template-columns: 1fr 1fr 1fr;
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
      min-height: 520px;
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
    .prose p  { color: #444; margin-bottom: 1rem; }
    .prose p:last-child { margin-bottom: 0; }
    .prose strong { color: #222; font-weight: 600; }

    .series-list {
      list-style: none;
      margin: 0.5rem 0 1rem;
    }

    .series-list li {
      display: flex;
      align-items: flex-start;
      gap: 0.6rem;
      font-size: 0.88rem;
      color: #444;
      margin-bottom: 0.5rem;
    }

    .dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      flex-shrink: 0;
      margin-top: 0.35em;
    }

    .dot-blue  { background: #636efa; }
    .dot-red   { background: #ef553b; }
    .dot-green { background: #00aa7a; }

    .source { font-size: 0.75rem; color: #aaa; margin-top: 1.25rem; }

    /* Rankings panel */

    .rank-controls {
      padding: 0.75rem 1rem 0.65rem;
      border-bottom: 1px solid #e0e0e0;
      background: #fafafa;
      flex-shrink: 0;
      display: flex;
      flex-direction: column;
      gap: 0.55rem;
    }

    .rank-controls-row {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .rank-ctrl-label {
      font-size: 0.75rem;
      font-weight: 500;
      color: #777;
      min-width: 38px;
    }

    .measure-tabs { display: flex; gap: 0.3rem; }

    .measure-tab {
      font-family: inherit;
      font-size: 0.72rem;
      font-weight: 500;
      padding: 0.18rem 0.5rem;
      border-radius: 3px;
      cursor: pointer;
      border: 1.5px solid transparent;
      background: transparent;
      transition: background 0.12s, color 0.12s;
      line-height: 1.5;
    }

    .measure-tab[data-idx="0"]        { border-color: #636efa; color: #636efa; }
    .measure-tab[data-idx="0"].active { background: #636efa;   color: #fff; }
    .measure-tab[data-idx="1"]        { border-color: #ef553b; color: #ef553b; }
    .measure-tab[data-idx="1"].active { background: #ef553b;   color: #fff; }
    .measure-tab[data-idx="2"]        { border-color: #00aa7a; color: #00aa7a; }
    .measure-tab[data-idx="2"].active { background: #00aa7a;   color: #fff; }

    #rank-year, #rank-group {
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

    #rank-year:focus, #rank-group:focus { border-color: #636efa; }

    .rank-list {
      flex: 1;
      overflow-y: auto;
      padding: 0.4rem 0;
    }

    .rank-row {
      display: grid;
      grid-template-columns: 18px 1fr 44px;
      align-items: center;
      gap: 0.45rem;
      padding: 0.32rem 0.9rem;
      cursor: pointer;
      border-radius: 4px;
      margin: 1px 0.4rem;
      transition: background 0.1s;
    }

    .rank-row:hover       { background: #f0f0f0; }
    .rank-row.rank-active { background: #f0f0f0; }
    .rank-row.rank-canada { font-style: italic; }

    .rank-num {
      font-size: 0.7rem;
      color: #bbb;
      text-align: right;
      font-variant-numeric: tabular-nums;
    }

    .rank-name {
      font-size: 0.8rem;
      color: #333;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .rank-val {
      font-size: 0.76rem;
      color: #555;
      font-variant-numeric: tabular-nums;
      text-align: right;
    }

    @media (max-width: 1100px) { main { grid-template-columns: 1fr 1fr; } }
    @media (max-width: 700px)  { main { grid-template-columns: 1fr; } }
  </style>
</head>
<body>

<header>
  <h1>Income Shares</h1>
</header>

<main>
  <section>
    <div class="section-label">About this data</div>
    <div class="prose">
      <h2>Income Shares</h2>
      <p>
        An income share measures the fraction of all income that is received by a particular group of individuals. These series focus on the income share of a particular segment of the distribution (i.e., top 1%, top 10%, bottom 50%).
       </p>
        <p>  
        For example, if the top 1%'s share of market income is 15%, it means that the highest-earning 1% in terms of market income collectively received 15% of all market income. 
        </p>
        <p>
        The shares for each income concept are computed separately, so those in the top 1% for market income are not necessarily those in the top 1% for total or after-tax income. Similarly, those in the top 1% in a given year are not necessarily those in the top 1% the following year.
      </p>
      
      <h2>Unit of Analysis</h2>
      <p>
        These series are based on individual, not household, income.
      </p>

     <h2>Components of Income Concepts</h2>
      <p>
        <strong>Market income</strong> = Employment income + Investment income + Private retirement income + Other market income
      </p>
      <p>
        <strong>Total income</strong> = Market income + OAS and GIS + CPP and QPP benefits + Employment Insurance + Child benefits + Social assistance + Workers' compensation + GST/HST credits + Other government transfers
      </p>
      <p>
        <strong>After-tax income</strong> = Total income - Income taxes
      </p>

      <p class="source">
        Data source: Statistics Canada, Table 11-10-0055-01
      </p>
    </div>
  </section>

  <section>
    <div class="section-label">Chart</div>
    <div class="chart-controls">
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Geography:</span>
        <select id="region-select">
          <option value="Canada">Canada</option>
          <option value="Newfoundland and Labrador">Newfoundland and Labrador</option>
          <option value="Prince Edward Island">Prince Edward Island</option>
          <option value="Nova Scotia">Nova Scotia</option>
          <option value="New Brunswick">New Brunswick</option>
          <option value="Quebec">Quebec</option>
          <option value="Ontario">Ontario</option>
          <option value="Manitoba">Manitoba</option>
          <option value="Saskatchewan">Saskatchewan</option>
          <option value="Alberta">Alberta</option>
          <option value="British Columbia">British Columbia</option>
        </select>
      </div>
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Income group:</span>
        <select id="group-select">
          <option value="Top 1%">Top 1%</option>
          <option value="Top 10%">Top 10%</option>
          <option value="Bottom 50%">Bottom 50%</option>
        </select>
      </div>
    </div>
    <div id="chart"></div>
  </section>

  <section id="rankings">
    <div class="section-label">Provincial Rankings</div>
    <div class="rank-controls">
      <div class="rank-controls-row">
        <span class="rank-ctrl-label">Year</span>
        <select id="rank-year"></select>
      </div>
      <div class="rank-controls-row">
        <span class="rank-ctrl-label">Group</span>
        <select id="rank-group">
          <option value="Top 1%">Top 1%</option>
          <option value="Top 10%">Top 10%</option>
          <option value="Bottom 50%">Bottom 50%</option>
        </select>
      </div>
      <div class="rank-controls-row">
        <span class="rank-ctrl-label">Measure</span>
        <div class="measure-tabs">
          <button class="measure-tab active" data-idx="0">Market</button>
          <button class="measure-tab"        data-idx="1">Total</button>
          <button class="measure-tab"        data-idx="2">After-tax</button>
        </div>
      </div>
    </div>
    <div id="rank-list" class="rank-list"></div>
  </section>
</main>

<script>
  const DATA = $(data_json);

  const COLORS   = ["#636efa", "#ef553b", "#00aa7a"];
  const CONCEPTS = ["Market income", "Total income", "After-tax income"];

  const ABBR = {
    "Canada":                    "Canada",
    "Newfoundland and Labrador": "NL",
    "Prince Edward Island":      "PEI",
    "Nova Scotia":               "NS",
    "New Brunswick":             "NB",
    "Quebec":                    "QC",
    "Ontario":                   "ON",
    "Manitoba":                  "MB",
    "Saskatchewan":              "SK",
    "Alberta":                   "AB",
    "British Columbia":          "BC",
  };

  let currentRegion  = "Canada";
  let currentGroup   = "Top 1%";
  var rankConceptIdx = 0;

  function buildTraces(region, group) {
    return CONCEPTS.map((concept, i) => ({
      x: DATA[region][group][concept].x,
      y: DATA[region][group][concept].y,
      name: concept,
      type: "scatter",
      mode: "lines",
      line: { color: COLORS[i], width: 2 },
      hovertemplate: "%{x}<br>%{y:.1f}%<extra></extra>",
    }));
  }

  var MARGIN_T = 50, MARGIN_B = 200;

  function buildLayout(region, group) {
    var el    = document.getElementById("chart");
    var plotH = Math.max((el.offsetHeight || 480) - MARGIN_T - MARGIN_B, 80);
    var noteY = -((MARGIN_B - 15) / plotH);
    return {
      title: { text: "Income Share \\u2013 " + group + " \\u2013 " + ABBR[region] },
      xaxis: { title: { text: "Year" } },
      yaxis: { title: { text: "Share of Income (%)" } },
      legend: { x: 0.5, xanchor: "center", y: -0.15, orientation: "h" },
      margin: { l: 60, b: MARGIN_B, r: 20, t: MARGIN_T },
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
    Plotly.react("chart", buildTraces(currentRegion, currentGroup), buildLayout(currentRegion, currentGroup), { responsive: true });
  }

  function selectRegion(region) {
    currentRegion = region;
    document.getElementById("region-select").value = region;
    update();
    renderRanking();
  }

  function renderRanking() {
    var year    = parseInt(document.getElementById("rank-year").value);
    var group   = document.getElementById("rank-group").value;
    var concept = CONCEPTS[rankConceptIdx];

    var entries = Object.keys(DATA).map(function(region) {
      var s   = DATA[region][group][concept];
      var idx = s.x.indexOf(year);
      return { region: region, value: idx >= 0 ? s.y[idx] : null };
    }).filter(function(e) { return e.value !== null; })
      .sort(function(a, b) { return b.value - a.value; });

    if (!entries.length) return;

    document.getElementById("rank-list").innerHTML = entries.map(function(e, i) {
      var cls = "rank-row"
              + (e.region === currentRegion ? " rank-active" : "")
              + (e.region === "Canada"       ? " rank-canada" : "");
      return '<div class="' + cls + '" onclick="selectRegion(\\'' + e.region + '\\')">'
           + '<span class="rank-num">' + (i + 1) + '</span>'
           + '<span class="rank-name">' + e.region + '</span>'
           + '<span class="rank-val">' + e.value.toFixed(1) + '%</span>'
           + '</div>';
    }).join('');
  }

  document.getElementById("region-select").addEventListener("change", function () {
    selectRegion(this.value);
  });

  document.getElementById("group-select").addEventListener("change", function () {
    currentGroup = this.value;
    update();
  });

  // Populate year dropdown (most recent first)
  var yearSel = document.getElementById("rank-year");
  DATA["Canada"]["Top 1%"]["Market income"].x.slice().reverse().forEach(function(y) {
    var opt = document.createElement("option");
    opt.value = y; opt.textContent = y;
    yearSel.appendChild(opt);
  });

  Plotly.newPlot("chart", buildTraces("Canada", "Top 1%"), buildLayout("Canada", "Top 1%"), { responsive: true });
  renderRanking();

  yearSel.addEventListener("change", renderRanking);
  document.getElementById("rank-group").addEventListener("change", renderRanking);

  document.querySelectorAll(".measure-tab").forEach(function(btn) {
    btn.addEventListener("click", function() {
      document.querySelectorAll(".measure-tab").forEach(function(b) { b.classList.remove("active"); });
      this.classList.add("active");
      rankConceptIdx = parseInt(this.getAttribute("data-idx"));
      renderRanking();
    });
  });

  var resizeTimer;
  new ResizeObserver(function() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function() {
      Plotly.relayout("chart", buildLayout(currentRegion, currentGroup));
    }, 50);
  }).observe(document.getElementById("chart"));
</script>

</body>
</html>"""

output = joinpath(@__DIR__, "income_shares.html")
write(output, html)
println("Saved → $output")

if Sys.isapple()
    run(`open $output`)
elseif Sys.iswindows()
    run(`cmd /c start $output`)
else
    run(`xdg-open $output`)
end
