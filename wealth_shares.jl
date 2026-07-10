using Pkg
Pkg.add(["JSON3"])

using JSON3

# -- World Inequality Database (WID.world) -----------------------------------
# Country      : Canada (CA)
# Variable     : shweal992j -- Net personal wealth share, equal-split adults
#                (age 20+); "j" population = individual with resources split
#                equally within couples.
# Groups       : Top 1% (p99p100), Top 10% (p90p100), Bottom 50% (p0p50)
# Coverage     : As much history as WID publishes (sparse benchmark years
#                back to ~1820, annual from ~1980 onward).
# Data is fetched via fetch_wealth_shares.R, which uses the official "wid" R
# package (world-inequality-database/wid-r-tool) rather than calling the WID
# backend API directly.
# Docs         : https://wid.world/codes-dictionary/
# -----------------------------------------------------------------------------

println("Fetching wealth share data for Canada from the World Inequality Database (via official R client)...")

tmpdir    = mktempdir()
json_path = joinpath(tmpdir, "wid_wealth_shares.json")
r_script  = joinpath(@__DIR__, "fetch_wealth_shares.R")

run(`Rscript $(r_script) $(json_path)`)

data      = JSON3.read(read(json_path, String))
data_json = JSON3.write(data)
println("Data fetched. Building HTML...")

html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Wealth Shares</title>
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

    .source { font-size: 0.75rem; color: #aaa; margin-top: 1.25rem; }

    @media (max-width: 900px) { main { grid-template-columns: 1fr; } }
  </style>
</head>
<body>

<header>
  <h1>Wealth Shares</h1>
</header>

<main>
  <section>
    <div class="section-label">About this data</div>
    <div class="prose">
      <h2>Wealth Shares</h2>
      <p>
        A wealth share measures the fraction of all net personal wealth that is held by a particular group of individuals. These series focus on the wealth share of a particular segment of the distribution (i.e., top 1%, top 10%, bottom 50%). 

      </p>
      <p>
For example, if the top 1%’s share of net personal wealth is 15%, it means that the wealthiest 1% collectively hold 15% of all net personal wealth.
      </p>
  
 <h2>Unit of Analysis</h2>
      <p>
        These series use the "equal-split adults" convention: wealth is measured at the individual level (adults aged 20+), but resources are split equally between partners within a couple.
      </p>

  

      <h2>Components of Net Personal Wealth</h2>
      <p>
        <strong>Net personal wealth</strong> = Non-financial assets + Financial assets - Liabilities
      </p>

      <p>
        Non-financial assets = Housing assets + Business and other non-financial assets
      </p>

      <p>
        Financial assets = Currency, deposits, bonds, and loans + Equities and fund shares + Pension funds and life insurance
      </p>

     

      <p class="source">
        Data source: World Inequality Database (WID.world), variable <code>shweal___992_j</code>, Canada
      </p>
    </div>
  </section>

  <section>
    <div class="section-label">Chart</div>
    <div class="chart-controls">
      <div class="ctrl-group">
        <span class="chart-ctrl-label">Wealth group:</span>
        <select id="group-select">
          <option value="Top 1%" selected>Top 1%</option>
          <option value="Top 10%">Top 10%</option>
          <option value="Bottom 50%">Bottom 50%</option>
        </select>
      </div>
    </div>
    <div id="chart"></div>
  </section>
</main>

<script>
  const DATA = $(data_json);

  const COLORS = {
    "Top 1%":     "#ef553b",
    "Top 10%":    "#ab63fa",
    "Bottom 50%": "#636efa",
  };

  let currentGroup = "Top 1%";

  function buildTrace(group) {
    return [{
      x: DATA[group].x,
      y: DATA[group].y,
      name: group,
      type: "scatter",
      mode: "lines+markers",
      marker: { size: 4 },
      line: { color: COLORS[group], width: 2 },
      hovertemplate: "%{x}<br>%{y:.2f}%<extra></extra>",
    }];
  }

  var MARGIN_T = 50, MARGIN_B = 200;

  function buildLayout(group) {
    var el    = document.getElementById("chart");
    var plotH = Math.max((el.offsetHeight || 480) - MARGIN_T - MARGIN_B, 80);
    var noteY = -((MARGIN_B - 15) / plotH);
    return {
      title: { text: "Share of Net Personal Wealth \\u2013 " + group + " \\u2013 Canada" },
      xaxis: { title: { text: "Year" } },
      yaxis: { title: { text: "Share of Wealth (%)" } },
      legend: { x: 0.5, xanchor: "center", y: -0.15, orientation: "h" },
      margin: { l: 60, b: MARGIN_B, r: 20, t: MARGIN_T },
      paper_bgcolor: "white",
      plot_bgcolor: "#E5ECF6",
      annotations: [{
        xref: "paper", yref: "paper",
        x: 0.5, y: noteY,
        xanchor: "center", yanchor: "bottom",
        showarrow: false,
        text: "Chart created by the Stone Centre on Wealth and Income Inequality<br>at the Vancouver School of Economics (UBC) using data from the World Inequality Database",
        font: { size: 9, color: "#b0b0b0" },
      }],
    };
  }

  function update() {
    Plotly.react("chart", buildTrace(currentGroup), buildLayout(currentGroup), { responsive: true });
  }

  function selectGroup(group) {
    currentGroup = group;
    document.getElementById("group-select").value = group;
    update();
  }

  document.getElementById("group-select").addEventListener("change", function () {
    selectGroup(this.value);
  });

  Plotly.newPlot("chart", buildTrace(currentGroup), buildLayout(currentGroup), { responsive: true });

  var resizeTimer;
  new ResizeObserver(function() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function() {
      Plotly.relayout("chart", buildLayout(currentGroup));
    }, 50);
  }).observe(document.getElementById("chart"));
</script>

</body>
</html>"""

output = joinpath(@__DIR__, "wealth_shares.html")
write(output, html)
println("Saved -> $output")

if Sys.isapple()
    run(`open $output`)
elseif Sys.iswindows()
    run(`cmd /c start $output`)
else
    run(`xdg-open $output`)
end
