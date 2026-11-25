import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Check, CircleDollarSign, WalletCards } from 'lucide-react'
import {
  TOP_UP_FILTERS,
  buildTopUpsPath,
  topUpDate,
  topUpStatusLabel,
  topUpSummary,
  type TopUpRow,
} from './topups-view'

const API_BASE = import.meta.env.VITE_API_URL ?? 'http://localhost:3000/api/v1'
const CURRENCY = 'EGP'
const money = (value: unknown) => `${CURRENCY} ${Number(value ?? 0).toFixed(2)}`

class TopUpsApiError extends Error {}

async function fetchTopUps(status: string): Promise<TopUpRow[]> {
  const token = localStorage.getItem('wasalny-admin-token')
  let response: Response
  try {
    response = await fetch(`${API_BASE}${buildTopUpsPath(status)}`, {
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    })
  } catch {
    throw new TopUpsApiError(`Cannot reach the API at ${API_BASE}.`)
  }
  if (response.status === 401) {
    localStorage.removeItem('wasalny-admin-token')
    if (window.location.pathname !== '/login') window.location.assign('/login')
    throw new TopUpsApiError('Your session has expired.')
  }
  if (!response.ok) {
    const body = await response.json().catch(() => ({}))
    throw new TopUpsApiError(body.message ?? `Request failed (${response.status})`)
  }
  return response.json() as Promise<TopUpRow[]>
}

/** Admin view of GET /admin/topups — read-only, same design as the rest of the dashboard. */
export default function TopUpsPage() {
  const [status, setStatus] = useState('')
  const topUps = useQuery<TopUpRow[], TopUpsApiError>({
    queryKey: ['topups', status],
    queryFn: () => fetchTopUps(status),
  })
  const rows = topUps.data ?? []
  const summary = topUpSummary(rows)

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">PAYMENT OPERATIONS</div>
        <h1>Top-ups</h1>
        <p>Review captain wallet top-ups and their confirmation status from Kashier.</p>
      </div>
    </div>
    {topUps.error && <div className="error-banner" role="alert">
      <span><strong>Data not loaded:</strong> {topUps.error.message}</span>
      <button className="button button-outline" onClick={() => topUps.refetch()}>Retry</button>
    </div>}
    <section className="metric-grid report-metrics">
      <article className="metric-card">
        <div className="metric-top"><span>Shown in this view</span><span className="metric-icon"><WalletCards size={17} /></span></div>
        <div className="metric-value">{String(summary.total)}</div>
      </article>
      <article className="metric-card">
        <div className="metric-top"><span>Succeeded (net credited)</span><span className="metric-icon"><Check size={17} /></span></div>
        <div className="metric-value">{money(summary.credited)}</div>
      </article>
      <article className="metric-card">
        <div className="metric-top"><span>Pending confirmation</span><span className="metric-icon blue"><CircleDollarSign size={17} /></span></div>
        <div className="metric-value">{String(summary.pending)}</div>
      </article>
      <article className="metric-card">
        <div className="metric-top"><span>Failed or expired</span><span className="metric-icon rose"><WalletCards size={17} /></span></div>
        <div className="metric-value">{String(summary.failed)}</div>
      </article>
    </section>
    <section className="panel table-panel">
      <div className="table-toolbar">
        <span className="panel-kicker">FILTER BY STATUS</span>
        <select
          id="topup-status"
          className="table-select"
          aria-label="Filter top-ups by status"
          value={status}
          onChange={(event) => setStatus(event.target.value)}
        >
          {TOP_UP_FILTERS.map((filter) => (
            <option key={filter.value} value={filter.value}>{filter.label}</option>
          ))}
        </select>
      </div>
      <div className="table-scroll">
        <table>
          <thead><tr>
            <th>CREATED</th><th>CAPTAIN</th><th>REFERENCE</th><th>CHARGED</th>
            <th>CREDIT</th><th>FEE</th><th>STATUS</th><th>PAID AT</th><th>DETAIL</th>
          </tr></thead>
          <tbody>
            {rows.map((row) => <tr key={row.id}>
              <td>{topUpDate(row.createdAt)}</td>
              <td><strong>{row.user?.name ?? '—'}</strong></td>
              <td className="mono">{row.providerOrderRef ?? row.id}</td>
              <td className="amount">{money(row.chargeAmount)}</td>
              <td className="amount">{money(row.creditAmount)}</td>
              <td>{money(row.feeAmount)}</td>
              <td><span className={`status status-${row.status.toLowerCase()}`}><i />{topUpStatusLabel(row.status)}</span></td>
              <td>{topUpDate(row.paidAt)}</td>
              <td className="muted">{row.failureReason ?? '—'}</td>
            </tr>)}
          </tbody>
        </table>
      </div>
      {!topUps.error && rows.length === 0 && (
        <div className="empty-inline">{topUps.isPending ? 'Loading…' : 'No top-ups match this filter.'}</div>
      )}
    </section>
  </>
}
