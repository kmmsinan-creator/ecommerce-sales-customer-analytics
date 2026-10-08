window.addEventListener('error', e => { const s = document.querySelector('#sub'); if (s) s.textContent = 'Script error: ' + e.message; });
const $ = s => document.querySelector(s);
const MN = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const ml = (m, p) => MN[+m.slice(5, 7) - 1] + ' ' + m.slice(2, 4) + (p ? '*' : '');
const mx = x => ml(x.month, x.is_partial);
const n0 = v => Math.round(v).toLocaleString('en-GB');
const gbp = v => '£' + n0(v);
const k0 = v => '£' + Math.round(v / 1000) + 'k';
const p0 = v => v + '%';
const pc = v => v.toFixed(1) + '%';
const tc = s => s.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
const nm = s => { s = tc(s); return s.length > 28 ? s.slice(0, 27) + '…' : s; };
const C = ['#0f766e', '#c47f00', '#7a93ad', '#b4413b', '#4a4e69'];
Chart.defaults.font.family = '"Segoe UI",system-ui,sans-serif';
Chart.defaults.color = '#5b6b7c';
const D = {};

const ds = (label, data, color) => ({ label, data, backgroundColor: color, borderColor: color, borderWidth: 2, tension: .25, pointRadius: 3 });
const cfg = (type, labels, sets, o = {}) => {
  const h = !!o.h, v = h ? 'x' : 'y', f = o.fmt || (x => x);
  const lin = { beginAtZero: true, stacked: !!o.st, ticks: { callback: x => f(x) } }, cat = { stacked: !!o.st };
  return { type, data: { labels, datasets: sets }, options: { maintainAspectRatio: false, indexAxis: h ? 'y' : 'x',
    scales: h ? { x: lin, y: cat } : { x: cat, y: lin },
    plugins: { legend: { display: sets.length > 1 }, tooltip: { callbacks: { label: c => (sets.length > 1 ? c.dataset.label + ': ' : '') + (o.tip || f)(c.parsed[v]) } } } } };
};
const card = (sec, title, note, wide) => {
  const d = document.createElement('div');
  d.className = 'card' + (wide ? ' wide' : '');
  d.innerHTML = `<h3>${title}</h3>${note ? `<p class="note">${note}</p>` : ''}`;
  $('#' + sec + ' .grid').append(d);
  return d;
};
const chart = (sec, title, config, note, wide) => {
  const d = card(sec, title, note, wide), b = document.createElement('div');
  b.className = 'box'; b.innerHTML = '<canvas></canvas>'; d.append(b);
  new Chart(b.firstChild, config);
};
// cols: [header, fn(row), 'n' for numbers]
const tbl = (sec, title, cols, rows, note, wide) => {
  const d = card(sec, title, note, wide);
  d.insertAdjacentHTML('beforeend', `<div class="tbl"><table><thead><tr>${cols.map(c => `<th class="${c[2] || ''}">${c[0]}</th>`).join('')}</tr></thead><tbody>${rows.map(r => `<tr>${cols.map(c => `<td class="${c[2] || ''}">${c[1](r)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`);
};
const kpi = (label, val, sub) => $('#overview .kpis').insertAdjacentHTML('beforeend', `<div class="kpi"><span>${label}</span><b>${val}</b><small>${sub || ''}</small></div>`);

const B = {
  overview() {
    const k = D.kpis, m = D.monthly, uk = D.countries.markets.find(x => x.market === 'UK');
    kpi('Revenue', gbp(k.revenue), 'gross sales');
    kpi('Net revenue', gbp(k.net_revenue), 'after cancellations');
    kpi('Orders', n0(k.orders), n0(k.units) + ' units');
    kpi('Customers', n0(k.customers), pc(k.repeat_rate_pct) + ' ordered 2+ times');
    kpi('Average order', gbp(k.avg_order_value), gbp(k.revenue_per_customer) + ' per customer');
    kpi('Cancelled', k.cancel_rate_value_pct.toFixed(2) + '%', gbp(k.cancellation_value) + ' of sales');
    const best = m.filter(x => !x.is_partial).reduce((a, b) => b.revenue > a.revenue ? b : a);
    chart('overview', 'Monthly revenue', cfg('bar', m.map(mx), [{ label: 'Revenue', data: m.map(x => x.revenue), backgroundColor: m.map(x => x.is_partial ? '#b9c3cf' : C[0]) }], { fmt: k0, tip: gbp }),
      `Best full month: ${ml(best.month)} at ${gbp(best.revenue)}. Revenue is steady from January to August, then climbs through autumn. *December 2011 covers only 1–9 December. With 12 months of data, seasonality cannot be separated from growth.`, 1);
    const tp = D.products.top.slice(0, 10);
    chart('overview', 'Top 10 products by revenue', cfg('bar', tp.map(x => nm(x.name)), [ds('Revenue', tp.map(x => x.revenue), C[0])], { h: 1, fmt: k0, tip: gbp }),
      `The top product is only ${pc(tp[0].share_pct)} of revenue, so sales are spread across the range.`);
    const ct = D.countries.countries.filter(x => x.country !== 'United Kingdom').slice(0, 8);
    chart('overview', 'Revenue by country, excluding the UK', cfg('bar', ct.map(x => x.country), [ds('Revenue', ct.map(x => x.revenue), C[2])], { h: 1, fmt: k0, tip: gbp }),
      `The UK is ${pc(uk.share_pct)} of revenue (${gbp(uk.revenue)}); international markets make up the rest.`);
  },
  customers() {
    const S = D.rfm.segments, m = D.monthly, Cu = D.customers, ch = S.find(s => s.segment === 'Champions');
    chart('customers', 'Customer segments (RFM)', cfg('bar', S.map(s => s.segment), [ds('% of customers', S.map(s => s.pct_of_customers), C[2]), ds('% of revenue', S.map(s => s.pct_of_revenue), C[0])], { h: 1, fmt: p0 }),
      `Champions are ${pc(ch.pct_of_customers)} of customers but ${pc(ch.pct_of_revenue)} of customer revenue. Segments use fixed recency and frequency cutoffs; snapshot date ${D.rfm.snapshot_date}.`);
    const dc = Cu.deciles;
    chart('customers', 'Revenue by customer decile', cfg('bar', dc.map(d => d.decile === 1 ? 'Top 10%' : `${d.decile * 10 - 9}–${d.decile * 10}%`), [ds('Share of revenue', dc.map(d => d.share_pct), C[0])], { fmt: p0 }),
      `The top 10% of customers generate ${pc(dc[0].share_pct)} of customer revenue; the top 30% generate ${pc(dc[2].cumulative_pct)}.`);
    const fb = Cu.frequency_bands;
    chart('customers', 'Purchase frequency', cfg('bar', fb.map(b => b.band), [ds('% of customers', fb.map(b => b.pct_of_customers), C[2]), ds('% of revenue', fb.map(b => b.pct_of_revenue), C[0])], { fmt: p0 }),
      `Customers with 10+ orders are ${pc(fb[3].pct_of_customers)} of customers and ${pc(fb[3].pct_of_revenue)} of revenue.`);
    chart('customers', 'New vs returning customers per month', cfg('bar', m.map(mx), [ds('New', m.map(x => x.new_customers), C[1]), ds('Returning', m.map(x => x.returning_customers), C[0])], { st: 1, fmt: n0 }),
      'December 2010 is all "new" because the data starts there. The returning share rises mostly because the pool of past customers grows, so it does not show better retention.');
    const cv = D.cohorts.average_curve.filter(x => x.months_since > 0);
    chart('customers', 'Cohort retention: share of a cohort buying again', cfg('line', cv.map(x => 'Month ' + x.months_since), [ds('Retention', cv.map(x => x.avg_retention_pct), C[3])], { fmt: p0 }),
      `About ${pc(cv[0].avg_retention_pct)} of new customers buy again the next month. Weighted average across cohorts, excluding the December 2010 cohort; months 9–10 rest on only 1–2 cohorts.`);
    tbl('customers', 'At-risk customers to win back', [['Customer', r => r.customer_id], ['Last purchase', r => r.last_purchase], ['Days ago', r => r.recency_days, 'n'], ['Orders', r => r.orders, 'n'], ['Total spend', r => gbp(r.total_spend), 'n']], D.rfm.at_risk_top,
      'Highest-spending customers who bought 3+ times but have not ordered for over 180 days.');
  },
  products() {
    const P = D.products, pa = P.pareto;
    tbl('products', 'Top 15 products by revenue', [['#', r => r.rank, 'n'], ['Product', r => tc(r.name)], ['Revenue', r => gbp(r.revenue), 'n'], ['Units', r => n0(r.units), 'n'], ['Avg price', r => '£' + r.avg_price.toFixed(2), 'n'], ['Share', r => pc(r.share_pct), 'n'], ['Cumulative', r => pc(r.cumulative_pct), 'n']], P.top,
      `${n0(pa.products_for_80pct)} of ${n0(pa.total_products)} products (${pc(pa.pct_of_products)}) generate 80% of revenue.`, 1);
    chart('products', 'Top 5 products: monthly revenue', { type: 'line', data: { labels: P.months.map(m => ml(m, m === '2011-12')), datasets: P.top5_monthly.map((p, i) => ds(nm(p.name), p.revenue, [C[0], C[1], C[2], C[3], C[4]][i])) },
      options: { maintainAspectRatio: false, scales: { y: { beginAtZero: true, ticks: { callback: k0 } } }, plugins: { tooltip: { callbacks: { label: c => c.dataset.label + ': ' + gbp(c.parsed.y) } } } } },
      '*December 2011 is partial.', 1);
    tbl('products', 'High volume, low value', [['Product', r => tc(r.name)], ['Units rank', r => r.units_rank, 'n'], ['Revenue rank', r => n0(r.revenue_rank), 'n'], ['Units', r => n0(r.units), 'n'], ['Revenue', r => gbp(r.revenue), 'n'], ['Avg price', r => '£' + r.avg_price.toFixed(2), 'n']], P.volume_vs_value,
      'Products in the top 50 by units sold that rank far lower by revenue. Candidates for bundling or a price review.', 1);
  },
  markets() {
    const Co = D.countries, c10 = Co.countries.slice(0, 10), find = n => Co.countries.find(x => x.country === n);
    tbl('markets', 'UK vs international', [['Market', r => r.market], ['Revenue', r => gbp(r.revenue), 'n'], ['Share', r => pc(r.share_pct), 'n'], ['Orders', r => n0(r.orders), 'n'], ['Customers', r => n0(r.customers), 'n'], ['Avg order', r => gbp(r.avg_order_value), 'n']], Co.markets,
      '"Unknown" holds rows labelled Unspecified or European Community, which are not countries.');
    chart('markets', 'Average order value by country', cfg('bar', c10.map(x => x.country), [ds('Average order', c10.map(x => x.avg_order_value), C[1])], { h: 1, fmt: gbp }),
      `The Netherlands (${find('Netherlands').customers} customers) and EIRE (${find('EIRE').customers} customers) have very large orders from very few buyers, so those markets depend on a handful of accounts.`);
    tbl('markets', 'Top 10 countries', [['#', r => r.rank, 'n'], ['Country', r => r.country], ['Revenue', r => gbp(r.revenue), 'n'], ['Share', r => pc(r.share_pct), 'n'], ['Orders', r => n0(r.orders), 'n'], ['Customers', r => n0(r.customers), 'n'], ['Avg order', r => gbp(r.avg_order_value), 'n']], c10,
      'Shares exclude the Unspecified / EC rows.', 1);
    tbl('markets', 'Best-selling products in the five largest international markets', [['Country', r => r.country], ['Top 3 products', r => r.products.map(p => tc(p.name) + ' (' + gbp(p.revenue) + ')').join('<br>'), 'w']], Co.top_products_by_country, '', 1);
  },
  quality() {
    const X = D.cancellations, Q = D.quality, m = D.monthly, a = X.april;
    chart('quality', 'Cancellation rate by month (% of sales value)', cfg('line', m.map(mx), [ds('Cancelled', m.map(x => x.cancel_rate_pct), C[3])], { fmt: p0 }),
      `April 2011 reads ${a.rate_all_pct}%, but ${a.rate_excluding_c550456_pct}% without one invoice (C550456). October's rise is also one large invoice. Cancellations are frequent but small: ${pc(X.kpis.rate_by_orders_pct)} of invoices, ${X.kpis.rate_by_value_pct}% of value.`, 1);
    tbl('quality', 'Case study: the April spike', [['Invoice', r => r.invoice_no], ['Date', r => r.invoice_date], ['Type', r => r.line_type], ['Lines', r => r.lines, 'n'], ['Value', r => gbp(r.value), 'n']], X.april_case_study,
      'Customer 15749. The two January invoices total exactly the cancelled amount, and a new invoice follows 12 minutes later. This looks like an order re-issued after an amendment, not lost demand.');
    tbl('quality', 'Ten largest cancelled invoices', [['#', r => r.rank, 'n'], ['Invoice', r => r.invoice_no], ['Customer', r => r.customer_id || '–'], ['Date', r => r.cancelled_at.slice(0, 10)], ['Value', r => gbp(r.value), 'n']], X.top_invoices,
      `The top 1% of cancelled invoices hold ${pc(X.concentration.top_1pct_share)} of cancelled value.`);
    tbl('quality', 'Products with the most cancelled value', [['Product', r => nm(r.name)], ['Cancelled', r => gbp(r.cancel_value), 'n'], ['Invoices', r => r.cancel_invoices, 'n'], ['% of its sales', r => pc(r.cancel_rate_pct), 'n']], X.products);
    tbl('quality', 'Cancellation rate by country', [['Country', r => r.country], ['Sales', r => gbp(r.sales_value), 'n'], ['Cancelled', r => gbp(r.cancel_value), 'n'], ['Rate', r => r.cancel_rate_pct.toFixed(2) + '%', 'n']], X.countries, 'Countries with sales above £50,000.');
    const rec = Q.reconciliation.concat([{ line_type: 'Total', rows: Q.raw.rows, value: Q.raw.value, meaning: 'Equals Quantity × UnitPrice over all raw rows' }]);
    tbl('quality', 'Reconciliation: every raw row has exactly one line type', [['Line type', r => r.line_type], ['Rows', r => n0(r.rows), 'n'], ['Net value', r => gbp(r.value), 'n'], ['Meaning', r => r.meaning, 'w']], rec,
      'No rows were deleted. Each metric on this site filters by line type, so every figure traces back to the raw file.', 1);
    tbl('quality', 'Data issues found and how they were handled', [['Issue', r => r.issue], ['Rows', r => n0(r.count), 'n'], ['Treatment', r => r.treatment, 'w']], Q.issues, '', 1);
    card('quality', 'Limitations', '', 1).insertAdjacentHTML('beforeend', '<ul>' + Q.limitations.map(l => `<li>${l}</li>`).join('') + '</ul>');
  }
};
const built = {};
function show(t) {
  document.querySelectorAll('nav button').forEach(b => b.classList.toggle('on', b.dataset.t === t));
  document.querySelectorAll('main section').forEach(s => s.hidden = s.id !== t);
  if (!built[t]) { built[t] = 1; B[t](); }
}
document.querySelectorAll('nav button').forEach(b => b.onclick = () => show(b.dataset.t));
Promise.all(['kpis', 'monthly', 'products', 'countries', 'customers', 'rfm', 'cancellations', 'cohorts', 'quality', 'meta']
  .map(n => fetch(`data/${n}.json`).then(r => r.json()).then(j => D[n] = j)))
  .then(() => {
    $('#sub').textContent = `UCI Online Retail: ${n0(D.meta.rows)} transaction lines, ${D.meta.date_from} to ${D.meta.date_to}`;
    $('#foot').textContent = `Data: ${D.meta.source}. All figures come from SQL analysis of the cleaned data; see the repository for the code and business rules.`;
    show('overview');
  })
  .catch(() => { $('#sub').textContent = 'Could not load data. Open this page through GitHub Pages or a local server (python -m http.server), not by double-clicking the file.'; });
