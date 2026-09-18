const byId = id => document.getElementById(id);
const money = value => new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD', maximumFractionDigits: 2}).format(value);
async function get(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Service returned HTTP ${response.status}`);
  return response.json();
}
async function refresh() {
  try {
    const [portfolio, loans] = await Promise.all([get('/api/reports/portfolio'), get('/api/loans/recent')]);
    ['total', 'approved', 'declined'].forEach(key => byId(key).textContent = portfolio[key].toLocaleString());
    byId('amount').textContent = money(portfolio.approvedAmount);
    byId('health').textContent = 'Services connected';
    const rows = loans.map(loan => {
      const row = document.createElement('tr');
      [String(loan.customerId).padStart(3, '0'), money(loan.amount), loan.status,
       new Date(loan.createdAt).toLocaleTimeString()].forEach((value, index) => {
        const cell = document.createElement('td');
        if (index === 2) {
          const badge = document.createElement('span');
          badge.className = 'status' + (value === 'DECLINED' ? ' declined' : '');
          badge.textContent = value;
          cell.append(badge);
        } else cell.textContent = value;
        row.append(cell);
      });
      return row;
    });
    if (rows.length) byId('loans').replaceChildren(...rows);
  } catch (error) {
    byId('health').textContent = error.message;
  }
}
byId('application').addEventListener('submit', async event => {
  event.preventDefault();
  byId('submit').disabled = true;
  byId('result').className = 'result';
  byId('result').textContent = 'Processing application…';
  const started = performance.now();
  try {
    const body = {requestId: crypto.randomUUID(), customerId: Number(byId('customer').value),
      amount: Number(byId('loanAmount').value), termMonths: Number(byId('term').value), scenario: byId('scenario').value};
    const response = await fetch('/api/loans/apply', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    const result = await response.json();
    const elapsed = Math.round(performance.now() - started);
    if (!response.ok) throw new Error(`HTTP ${response.status} · ${elapsed} ms · ${result.error}`);
    byId('result').textContent = `${result.status} · ${elapsed} ms · ${result.reason}. Request ${result.requestId}`;
    await refresh();
  } catch (error) {
    byId('result').className = 'result error';
    byId('result').textContent = error.message;
  } finally { byId('submit').disabled = false; }
});
byId('refresh').addEventListener('click', refresh);
refresh();
setInterval(() => { if (!document.hidden) refresh(); }, 10000);
