using Pkg
Pkg.add(["HTTP", "JSON3", "Dates"])

using HTTP, JSON3, Dates

# -- StatsCan WDS API ---------------------------------------------------------
# Table  : 11-10-0134-01  Gini coefficients of adjusted market, total and after-tax income
# Vectors: Canada + 10 provinces, three income concepts each
#   Column order: Adjusted market income, Adjusted total income, Adjusted after-tax income
# Docs   : https://www.statcan.gc.ca/en/developers/wds/user-guide
# -----------------------------------------------------------------------------

const REGIONS = [
    "Canada"                    => (96439636, 96439637, 96439638),
    "Newfoundland and Labrador" => (96439642, 96439643, 96439644),
    "Prince Edward Island"      => (96439645, 96439646, 96439647),
    "Nova Scotia"               => (96439648, 96439649, 96439650),
    "New Brunswick"             => (96439651, 96439652, 96439653),
    "Quebec"                    => (96439654, 96439655, 96439656),
    "Ontario"                   => (96439657, 96439658, 96439659),
    "Manitoba"                  => (96439663, 96439664, 96439665),
    "Saskatchewan"              => (96439666, 96439667, 96439668),
    "Alberta"                   => (96439669, 96439670, 96439671),
    "British Columbia"          => (96439672, 96439673, 96439674),
]

const SERIES_NAMES = ["Adjusted market income", "Adjusted total income", "Adjusted after-tax income"]
const N_PERIODS    = 100   # fetch up to 100 periods; API returns all available (1976-present)
const ENDPOINT     = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods"

function fetch_series(vector_ids::Vector{Int}, n::Int)
    body    = JSON3.write([Dict("vectorId" => v, "latestN" => n) for v in vector_ids])
    headers = ["Content-Type" => "application/json"]
    resp    = HTTP.post(ENDPOINT, headers, body)
    parsed  = JSON3.read(String(resp.body))

    results = Dict{Int, NamedTuple{(:years, :values), Tuple{Vector{Int}, Vector{Float64}}}}()
    for item in parsed
        item[:status] == "SUCCESS" || error("API error: $(item[:status])")
        pts    = item[:object][:vectorDataPoint]
        vid    = item[:object][:vectorId]
        years  = [year(Date(string(p[:refPer]))) for p in pts]
        values = Float64[p[:value] for p in pts]
        results[vid] = (years = years, values = values)
    end
    return results
end

println("Fetching Gini data for Canada and provinces from Statistics Canada...")

all_vector_ids = [v for (_, vs) in REGIONS for v in vs]
raw = fetch_series(all_vector_ids, N_PERIODS)

# Build nested Dict: region name -> series name -> {x, y}
data = Dict{String, Dict{String, Dict{String, Vector}}}()
for (region, vids) in REGIONS
    data[region] = Dict{String, Dict{String, Vector}}()
    for (name, vid) in zip(SERIES_NAMES, vids)
        d = raw[vid]
        data[region][name] = Dict("x" => d.years, "y" => round.(d.values, digits=4))
    end
end

data_json = JSON3.write(data)
println("Data fetched. Building HTML...")

html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Gini Coefficients of Adjusted Income</title>
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
      display: flex;
      align-items: center;
      gap: 1.5rem;
      flex-wrap: wrap;
    }

    header h1 {
      font-size: 1.15rem;
      font-weight: 600;
      letter-spacing: 0.01em;
    }

    .chart-controls {
      padding: 0.6rem 1rem;
      border-bottom: 1px solid #e0e0e0;
      background: #fafafa;
      flex-shrink: 0;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .chart-ctrl-label {
      font-size: 0.75rem;
      font-weight: 500;
      color: #777;
    }

    #region-select {
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

    #region-select:focus {
      border-color: #636efa;
      box-shadow: 0 0 0 2px rgba(99,110,250,0.15);
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

    #rank-year {
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

    #rank-year:focus { border-color: #636efa; }

    .rank-list {
      flex: 1;
      overflow-y: auto;
      padding: 0.4rem 0;
    }

    .rank-row {
      display: grid;
      grid-template-columns: 18px 1fr 38px;
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
  <h1>Gini Coefficients of Adjusted Income</h1>
</header>

<main>
  <section>
    <div class="section-label">About this data</div>
    <div class="prose">
      <h2>Gini Coefficient</h2>
      <p>
        The Gini coefficient measures income inequality within a population. It ranges from 0 (perfect equality – everyone earns the same) to 1 (perfect inequality – one person earns everything).
      </p>

       <h2>Adjusted Household Income</h2>
      <p>
        Statistics Canada defines a household as a "person or group of persons who occupy the same dwelling and do not have a usual place of residence elsewhere in Canada or abroad."
      </p>
        Each series uses household income divided by the square root of household size to account for economies of scale within the household.
      <p>
      </p>

      <h2>Components of Income Concepts</h2>
      <p>
        <strong>Market income</strong> = Employment income + Investment income + Private retirement income + Other market income
      </p>
      <p>
        <strong>Total income</strong> = Market income + OAS and GIS + CPP and QPP benefits + Employment Insurance + Child benefits + Social assistance + Workers compensation + GST/HST credits + Other government transfers
      </p>
      <p>
        <strong>After-tax income</strong> = Total income - Income taxes
      </p>

     

      <p class="source">
        Data source: Statistics Canada, Table 11-10-0134-01
      </p>
    </div>
  </section>

  <section>
    <div class="section-label">Chart</div>
    <div class="chart-controls">
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

  const SERIES     = ["Adjusted market income", "Adjusted total income", "Adjusted after-tax income"];
  const COLORS     = ["#636efa", "#ef553b", "#00cc96"];
  const BAR_COLORS = ["#636efa", "#ef553b", "#00aa7a"];


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

  var currentRegion  = "Canada";
  var rankMeasureIdx = 0;

  var MARGIN_T = 50, MARGIN_B = 200;

  function buildLayout(region) {
    var el    = document.getElementById("chart");
    var plotH = Math.max((el.offsetHeight || 480) - MARGIN_T - MARGIN_B, 80);
    var noteY = -((MARGIN_B - 15) / plotH);
    return {
      title: { text: "Gini Coefficients of Adjusted Income – " + ABBR[region] },
      xaxis: { title: { text: "Year" } },
      yaxis: { title: { text: "Gini Coefficient" } },
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

  function buildTraces(region) {
    return SERIES.map(function(name, i) {
      return {
        type: "scatter", mode: "lines", name: name,
        x: DATA[region][name].x,
        y: DATA[region][name].y,
        line: { color: COLORS[i], width: 2 },
        hovertemplate: "%{x}<br>%{y:.4f}<extra></extra>",
      };
    });
  }

  function renderRanking() {
    var year    = parseInt(document.getElementById("rank-year").value);
    var measure = SERIES[rankMeasureIdx];

    var entries = Object.keys(DATA).map(function(region) {
      var s   = DATA[region][measure];
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
           + '<span class="rank-val">' + e.value.toFixed(3) + '</span>'
           + '</div>';
    }).join('');
  }

  function selectRegion(region) {
    currentRegion = region;
    document.getElementById("region-select").value = region;
    Plotly.react("chart", buildTraces(region), buildLayout(region), { responsive: true });
    renderRanking();
  }

  // Populate year dropdown (most recent first)
  var yearSel = document.getElementById("rank-year");
  DATA["Canada"]["Adjusted market income"].x.slice().reverse().forEach(function(y) {
    var opt = document.createElement("option");
    opt.value = y; opt.textContent = y;
    yearSel.appendChild(opt);
  });

  // Initialise
  Plotly.newPlot("chart", buildTraces("Canada"), buildLayout("Canada"), { responsive: true });
  renderRanking();

  // Chart region dropdown
  document.getElementById("region-select").addEventListener("change", function() {
    currentRegion = this.value;
    Plotly.react("chart", buildTraces(this.value), buildLayout(this.value), { responsive: true });
    renderRanking();
  });

  // Year dropdown
  yearSel.addEventListener("change", renderRanking);

  // Recompute legend/annotation positions whenever the chart div is resized.
  // Debounced to avoid a relayout → resize → relayout loop.
  var resizeTimer;
  new ResizeObserver(function() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function() {
      Plotly.relayout("chart", buildLayout(currentRegion));
    }, 50);
  }).observe(document.getElementById("chart"));

  // Measure tabs
  document.querySelectorAll(".measure-tab").forEach(function(btn) {
    btn.addEventListener("click", function() {
      document.querySelectorAll(".measure-tab").forEach(function(b) { b.classList.remove("active"); });
      this.classList.add("active");
      rankMeasureIdx = parseInt(this.getAttribute("data-idx"));
      renderRanking();
    });
  });

</script>

</body>
</html>"""

output = joinpath(@__DIR__, "gini.html")
write(output, html)
println("Saved -> $output")

if Sys.isapple()
    run(`open $output`)
elseif Sys.iswindows()
    run(`cmd /c start $output`)
else
    run(`xdg-open $output`)
end
