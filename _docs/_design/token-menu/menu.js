// Fixed review fixtures. No provider files, permissions, or network access.
const providers = [
  { name: "Claude Code", tone: "#ff9c5f", total: 746820, weights: [0,0,0,0,0,0,1,2,5,12,18,7,4,8,14,12,4] },
  { name: "Codex", tone: "#c8b9a5", total: 384260, weights: [0,0,0,0,0,1,2,5,5,7,9,3,2,10,8,4,3] },
  { name: "Grok", tone: "#a8b3c3", total: 96540, weights: [1,1,0,0,0,0,0,1,0,1,3,2,1,1,7,5,2] },
  { name: "OpenCode", tone: "#899d91", total: 56980, weights: [0,0,0,0,0,0,0,1,3,5,2,3,1,7,5,1,2] },
];
const captions = {
  overview: "Overview compares each tool’s share of today’s tokens.",
  activity: "Activity shows when tokens were used. Select an hour to inspect it.",
  compact: "Compact keeps exact counts in a short menu.",
};
const get = id => document.getElementById(id);
const exact = n => n.toLocaleString("en-US");
const short = n => Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 2 }).format(n);
const hourLabel = h => String(h).padStart(2, "0") + ":00";
const sum = nums => nums.reduce((a, b) => a + b, 0);
const enabled = get("enabled");
const statusItem = get("status");
const panel = get("popup");
const sample = get("sample");
let menuOpen = true;
let hour = null;

function hourlyCounts(total, weights) {
  const denominator = sum(weights);
  let cumulative = 0;
  let previous = 0;
  return weights.map(weight => {
    cumulative += weight;
    const next = Math.round(total * cumulative / denominator);
    const value = next - previous;
    previous = next;
    return value;
  });
}

function readFixture(provider, index) {
  let value = provider.total;
  if (sample.value === "empty" || (sample.value === "partial" && index === 3)) value = null;
  if (sample.value === "partial" && index === 2) value = 0;
  const hours = hourlyCounts(value ?? 0, provider.weights);
  return { ...provider, value, hours, count: value === null || hour === null ? value : hours[hour] };
}

function providerRow(p, total, design) {
  const share = p.count === null || !total ? null : (p.count * 100 / total).toFixed(1) + "%";
  const count = p.count === null ? "Unavailable" : exact(p.count);
  const detail = p.count === null ? "No readable local source." :
    p.count === 0 ? "Local source available. No recorded tokens in this period." :
    exact(p.count) + " tokens · " + share + " of counted usage";
  const figure = p.count === null || design !== "overview" ? count : short(p.count);
  return '<details class="provider"><summary><span class="tool"><i class="dot" style="--tone:' + p.tone +
    '"></i>' + p.name + '</span><span class="number">' + figure + '</span></summary><p class="detail">' + detail + '</p></details>';
}

function timeline(rows) {
  const hours = rows[0].hours.map((_, i) => sum(rows.map(p => p.hours[i])));
  const max = Math.max(...hours, 1);
  const bars = hours.map((count, h) => {
    const label = hourLabel(h) + " · " + exact(count) + " tokens";
    return '<button class="bar" data-hour="' + h + '" aria-label="' + label + '" title="' + label +
      '" aria-pressed="' + (hour === h) + '"><i style="--height:' + (100 * count / max) + '%"></i></button>';
  }).join("");
  return '<div class="timeline"><div class="bars" aria-label="Hourly token counts">' + bars +
    '</div><div class="axis"><span>00:00</span><span>08:00</span><span>16:00</span></div></div>';
}

function snapshot(design, rows) {
  const present = rows.filter(p => p.value !== null);
  const partial = present.length < rows.length;
  const total = sum(present.map(p => p.count));
  const dayTotal = sum(present.map(p => p.value));
  const label = hour === null ? (partial ? "Counted tokens" : "All providers") : "Hour beginning " + hourLabel(hour);
  const displayTotal = present.length ? exact(total) : "—";
  const formattedDaily = present.length ? short(dayTotal) : "—";
  statusItem.querySelector("span").textContent = present.length && partial ? formattedDaily + "*" : formattedDaily;
  statusItem.setAttribute("aria-label", "YEN token usage, " + (present.length ? exact(dayTotal) + " counted tokens today" : "no local sources"));
  statusItem.title = partial ? "Partial coverage · " + present.length + " of 4 sources" : "Total tokens today";
  let content = "";
  if (design !== "compact") {
    content += '<div class="total"><div class="eyeline">' + label + '</div><div class="amount"><strong>' +
      (present.length ? short(total) : "—") + '</strong><small>tokens</small></div>';
    if (design === "overview" && total) {
      content += '<div class="share" aria-hidden="true">' + present.filter(p => p.count).map(p =>
        '<i style="--tone:' + p.tone + ';--count:' + p.count + '"></i>').join("") + '</div>';
    }
    content += "</div>";
  }
  if (design === "activity" && present.length) content += timeline(rows);
  panel.classList.toggle("activity", design === "activity");
  content += '<div class="rows"><div class="rows-head"><span>Provider</span><span>Tokens</span></div>';
  content += rows.map(p => providerRow(p, total, design)).join("");
  if (design === "compact") content += '<div class="compact-total"><span>' + (partial ? "Counted total" : "Total") + '</span><span>' + displayTotal + '</span></div>';
  get("body").innerHTML = content + "</div>";
  get("source-status").textContent = present.length === 0 ? "No readable local sources" :
    partial ? "Partial total · " + present.length + " of 4 local sources" : "4 local sources";
}

function visibility() {
  statusItem.hidden = !enabled.checked;
  panel.hidden = !enabled.checked || !menuOpen;
  statusItem.setAttribute("aria-expanded", String(!panel.hidden));
  const hint = get("hint");
  hint.hidden = !panel.hidden;
  hint.textContent = enabled.checked ? "Click the YEN count in the menu bar to open it." :
    "Turn on Show Token Usage in General to add the YEN menu.";
}

function render() {
  const key = location.hash.slice(1);
  const design = Object.hasOwn(captions, key) ? key : "overview";
  for (const link of document.querySelectorAll("nav a")) {
    if (link.hash === "#" + design) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  get("caption").textContent = captions[design];
  snapshot(design, providers.map(readFixture));
  visibility();
}

function bindControls() {
  window.addEventListener("hashchange", () => { hour = null; menuOpen = true; render(); });
  sample.addEventListener("change", () => { hour = null; menuOpen = true; render(); });
  statusItem.addEventListener("click", () => { menuOpen = !menuOpen; visibility(); });
  enabled.addEventListener("change", () => { menuOpen = false; hour = null; render(); });
  get("body").addEventListener("click", event => {
    const bar = event.target.closest("[data-hour]");
    if (!bar) return;
    const selected = Number(bar.dataset.hour);
    hour = hour === selected ? null : selected;
    render();
    get("body").querySelector('[data-hour="' + selected + '"]').focus();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && !panel.hidden) { menuOpen = false; visibility(); statusItem.focus(); }
  });
  document.querySelector(".desktop").addEventListener("click", event => {
    if (panel.hidden || event.composedPath().includes(panel) || event.target.closest("#status,label")) return;
    menuOpen = false;
    visibility();
  });
}

bindControls();
render();
