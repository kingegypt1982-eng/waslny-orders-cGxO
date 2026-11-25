import { useEffect, useState } from 'react'
import { Link, NavLink, Navigate, Outlet, Route, Routes, useLocation, useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Activity, ArrowRight, ArrowUpRight, Bell, Bike, Boxes, Check, ChevronDown, CircleDollarSign, ClipboardList, Download, Eye, LayoutDashboard, LifeBuoy, Menu, MoreHorizontal, Search, Settings2, ShieldCheck, Users, WalletCards, X } from 'lucide-react'
import './dashboard.css'
import { applicationReviewLabel, isDocUploaded } from './labels'
import TopUpsPage from './TopUpsPage'

type Order = { id: string; reference: string; status: string; pickupLabel: string; deliveryLabel: string; price: number; createdAt: string; client?: { name: string }; captain?: { id?: string; name: string } | null }
type Captain = {
  id: string; status: string; vehicleType: string; vehiclePlate: string; createdAt: string
  nationalIdDocument: string; nationalIdBackDocument?: string; licenseDocument: string; licenseBackDocument?: string
  vehicleDocument: string; vehicleBackDocument?: string; profilePhotoDocument?: string
  nationalIdLast4?: string | null; dateOfBirth?: string | null; governorate?: string | null
  licenseNumber?: string | null; vehicleRegistrationNumber?: string | null
  vehicleMake?: string | null; vehicleModel?: string | null; vehicleColor?: string | null
  rejectionReason?: string | null; approvedAt?: string | null; reviewedAt?: string | null
  user: { id: string; name: string; email: string; phone?: string | null; wallet?: { balance: number } | null }
}
type Client = { id: string; name: string; email: string; phone?: string; suspendedAt?: string | null; createdAt?: string; _count?: { clientOrders: number } }
type WalletRecord = { id: string; name: string; email: string; wallet: { balance: number } | null; walletTransactions: { id: string; amount: number; type: string; createdAt: string; note?: string | null }[] }
type DashboardData = {
  clients: number
  captains: number
  pendingCaptains: number
  openOrders: number
  completedOrders: number
  revenue: number
  commission: number
  recentOrders: Order[]
  weeklyRevenue?: { date: string; day: string; revenue: number; commission: number; orders: number }[]
}
type Pricing = { basePrice: number; pricePerKm: number; commissionPercent: number; minimumWalletBalance: number }

const navigation: { label: string; to: string; icon: typeof Users; stat?: 'openOrders' | 'pendingCaptains' }[] = [
  { label: 'Overview', to: '/', icon: LayoutDashboard },
  { label: 'Orders', to: '/orders', icon: ClipboardList, stat: 'openOrders' },
  { label: 'Captains', to: '/captains', icon: Bike, stat: 'pendingCaptains' },
  { label: 'Clients', to: '/clients', icon: Users },
  { label: 'Wallets', to: '/wallets', icon: WalletCards },
  { label: 'Top-ups', to: '/topups', icon: CircleDollarSign },
  { label: 'Reports', to: '/reports', icon: Activity },
]

const API_BASE = import.meta.env.VITE_API_URL ?? 'http://localhost:3000/api/v1'
const TODAY_LABEL = new Date().toLocaleDateString('en-GB', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' }).toUpperCase()

// Single source of truth for money in the admin web (the mobile app uses
// moneyLabel()/currencyLabel() from core/texts.dart with the same shape).
const CURRENCY = 'EGP'
const money = (value: unknown) => `${CURRENCY} ${Number(value ?? 0).toFixed(2)}`

class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

function handleUnauthorized() {
  localStorage.removeItem('wasalny-admin-token')
  if (window.location.pathname !== '/login') window.location.assign('/login')
}

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const token = localStorage.getItem('wasalny-admin-token')
  let response: Response
  try {
    response = await fetch(`${API_BASE}${path}`, {
      ...init, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...init?.headers },
    })
  } catch {
    throw new ApiError(`Cannot reach the API at ${API_BASE} (server down, network issue, or CORS blocked).`, 0)
  }
  if (response.status === 401) {
    if (!path.startsWith('/auth/')) handleUnauthorized()
    throw new ApiError('Your session has expired or the credentials are invalid.', 401)
  }
  if (!response.ok) throw new ApiError((await response.json().catch(() => ({}))).message ?? `Request failed (${response.status})`, response.status)
  return response.json() as Promise<T>
}
function useData<T>(key: string, path: string) {
  return useQuery<T, ApiError>({ queryKey: [key], queryFn: () => api<T>(path) })
}

function QueryError({ error, retry }: { error: { message: string } | null | undefined; retry?: () => void }) {
  if (!error) return null
  return <div className="error-banner" role="alert"><span><strong>Data not loaded:</strong> {error.message}</span>{retry && <button className="button button-outline" onClick={() => retry()}>Retry</button>}</div>
}

function Frame() {
  const [menuOpen, setMenuOpen] = useState(false)
  const location = useLocation()
  const { data: stats } = useData<DashboardData>('dashboard', '/admin/dashboard')
  const section = location.pathname.startsWith('/captains') ? 'Captains' : navigation.find((item) => item.to === location.pathname)?.label ?? (location.pathname === '/pricing' ? 'Pricing' : 'Settings')
  return <div className="shell"><aside className={`sidebar ${menuOpen ? 'sidebar-open' : ''}`}>
    <Link to="/" className="brand" onClick={() => setMenuOpen(false)}><span className="brand-mark"><Boxes size={19} /></span>wasalny<span className="brand-light">orders</span></Link>
    <div className="workspace"><span className="workspace-avatar">W</span><span><strong>Wasalny Logistics</strong><small>Operations workspace</small></span><ChevronDown size={15} /></div>
    <span className="nav-caption">WORKSPACE</span><nav className="main-nav">{navigation.map(({ label, to, icon: Icon, stat }) => { const badge = stat ? stats?.[stat] : undefined; return <NavLink key={to} to={to} end={to === '/'} onClick={() => setMenuOpen(false)} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}><Icon size={18} /><span>{label}</span>{badge != null && badge > 0 && <b>{badge}</b>}</NavLink> })}</nav>
    <span className="nav-caption nav-caption-bottom">MANAGE</span><nav className="main-nav"><NavLink to="/pricing" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}><CircleDollarSign size={18} /><span>Pricing</span></NavLink><NavLink to="/settings" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}><Settings2 size={18} /><span>Settings</span></NavLink></nav>
    <div className="sidebar-bottom"><div className="help-row"><span className="help-icon"><LifeBuoy size={17} /></span><span><strong>Need a hand?</strong><small>Visit the help center</small></span></div><div className="account-row"><span className="account-avatar">AM</span><span><strong>Admin Manager</strong><small>Administrator</small></span><MoreHorizontal size={18} /></div></div>
  </aside>{menuOpen && <button className="mobile-scrim" onClick={() => setMenuOpen(false)} aria-label="Close navigation" />}
    <main className="main-area"><header className="topbar"><div className="topbar-left"><button className="icon-button mobile-menu" onClick={() => setMenuOpen(true)} aria-label="Open navigation"><Menu size={19} /></button><span className="breadcrumb">Workspace <span>/</span> <strong>{section}</strong></span></div><div className="topbar-actions"><span className="live-indicator"><i /> All systems operational</span><button className="icon-button notification-button" aria-label="Notifications"><Bell size={18} /><i /></button><span className="topbar-divider" /><button className="top-user" aria-label="Administrator menu"><span className="account-avatar">AM</span><ChevronDown size={14} /></button></div></header><div className="page-content"><Outlet /></div></main>
  </div>
}
function Heading({ eyebrow, title, description, action }: { eyebrow: string; title: string; description: string; action?: React.ReactNode }) {
  return <div className="page-heading"><div><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{description}</p></div>{action}</div>
}
function Metric({ label, value, change, icon: Icon, tone = 'mint' }: { label: string; value: string; change?: string; icon: typeof Users; tone?: string }) {
  return <article className="metric-card"><div className="metric-top"><span>{label}</span><span className={`metric-icon ${tone}`}><Icon size={17} /></span></div><div className="metric-value">{value}</div>{change && <div className="metric-foot"><span className="trend"><ArrowUpRight size={13} />{change}</span><span>vs last week</span></div>}</article>
}
function Status({ value }: { value: string }) {
  const labels: Record<string, string> = { PENDING: 'Pending', SEARCHING_CAPTAIN: 'Finding captain', ACCEPTED: 'Accepted', ARRIVED_AT_PICKUP: 'At pickup', PICKED_UP: 'Picked up', ON_THE_WAY: 'On the way', DELIVERED: 'Delivered', COMPLETED: 'Completed', CANCELLED: 'Cancelled', ACTIVE: 'Approved', REJECTED: 'Rejected', SUSPENDED: 'Suspended' }
  return <span className={`status status-${value.toLowerCase()}`}><i />{labels[value] ?? value}</span>
}
function OrdersTable({ rows }: { rows: Order[] }) {
  return <div className="table-scroll"><table><thead><tr><th>ORDER</th><th>ROUTE</th><th>CLIENT</th><th>CAPTAIN</th><th>VALUE</th><th>STATUS</th><th /></tr></thead><tbody>{rows.map((row) => <tr key={row.id}><td><strong className="mono">{row.reference}</strong><small>{new Date(row.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</small></td><td><div className="route-cell"><span>{row.pickupLabel}</span><span>{row.deliveryLabel}</span></div></td><td>{row.client?.name ?? '—'}</td><td>{row.captain?.name ?? <span className="muted">Unassigned</span>}</td><td className="amount">{money(row.price)}</td><td><Status value={row.status} /></td><td><button className="row-menu" aria-label={`More actions ${row.reference}`}><MoreHorizontal size={18} /></button></td></tr>)}</tbody></table></div>
}
function Toolbar({ value, setValue, placeholder }: { value: string; setValue: (value: string) => void; placeholder: string }) {
  return <div className="table-toolbar"><label className="search-field"><Search size={16} /><input value={value} onChange={(event) => setValue(event.target.value)} placeholder={placeholder} /></label><button className="icon-button filter-button" aria-label="Filter results"><Activity size={16} /></button></div>
}

function RevenueChart({ data }: { data?: { date: string; day: string; revenue: number; commission: number; orders: number }[] }) {
  if (!data || data.length === 0) {
    return <div className="chart-placeholder">لا توجد بيانات تسليم مسجلة لهذا الأسبوع بعد.</div>
  }
  const maxRevenue = Math.max(...data.map((d) => d.revenue), 50)
  const totalRevenue = data.reduce((sum, d) => sum + d.revenue, 0)
  const totalCommission = data.reduce((sum, d) => sum + d.commission, 0)

  return (
    <>
      <div className="chart-legend">
        <span><i /> Gross delivery ({money(totalRevenue)})</span>
        <span style={{ marginLeft: 14 }}><i style={{ background: '#bc8150' }} /> Commission ({money(totalCommission)})</span>
        <strong>7-Day Performance</strong>
      </div>
      <div className="chart-wrap" style={{ display: 'flex', alignItems: 'flex-end', gap: '10px', padding: '16px 4px 6px' }}>
        {data.map((item, idx) => {
          const heightPct = Math.max(8, Math.round((item.revenue / maxRevenue) * 100))
          return (
            <div key={idx} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', height: '100%', justifyContent: 'flex-end' }}>
              <span style={{ fontSize: '9px', color: '#278263', fontWeight: 600, marginBottom: '4px' }}>
                {item.revenue > 0 ? `${item.revenue}` : ''}
              </span>
              <div
                style={{
                  width: '100%',
                  maxWidth: '34px',
                  height: `${heightPct}%`,
                  background: 'linear-gradient(180deg, #247c62 0%, #2fb38f 100%)',
                  borderRadius: '4px 4px 0 0',
                  transition: 'height 0.3s ease',
                }}
                title={`${item.day} (${item.date}): ${money(item.revenue)} - ${item.orders} orders`}
              />
              <span style={{ fontSize: '10px', color: '#7b8980', marginTop: '6px', fontWeight: 500 }}>
                {item.day}
              </span>
            </div>
          )
        })}
      </div>
    </>
  )
}

function Overview() {
  const dashboard = useData<DashboardData>('dashboard', '/admin/dashboard')
  const orders = useData<Order[]>('orders', '/admin/orders')
  const data = dashboard.data
  const rows = orders.data ?? []
  const today = TODAY_LABEL
  return <><Heading eyebrow={today} title="Good morning, team" description="Here's what's moving across Wasalny today." action={<div className="heading-actions"><button className="button button-outline" onClick={() => window.print()}><Download size={15} /> Export</button></div>} />
    <QueryError error={dashboard.error} retry={dashboard.refetch} />
    <QueryError error={orders.error} retry={orders.refetch} />
    <section className="metric-grid"><Metric label="Gross delivery value" value={money(data?.revenue ?? 0)} icon={CircleDollarSign} /><Metric label="Orders in progress" value={String(data?.openOrders ?? 0)} icon={ClipboardList} tone="blue" /><Metric label="Active captains" value={String(data?.captains ?? 0)} icon={Bike} tone="orange" /><Metric label="Registered clients" value={String(data?.clients ?? 0)} icon={Users} tone="rose" /></section>
    <section className="overview-grid"><article className="panel activity-panel"><div className="panel-heading"><div><div className="panel-kicker">PERFORMANCE</div><h2>Delivery activity</h2></div></div><RevenueChart data={data?.weeklyRevenue} /></article>
      <article className="panel attention-panel"><div className="panel-heading"><div><div className="panel-kicker">NEEDS ATTENTION</div><h2>On your radar</h2></div><span className="attention-count">{data?.pendingCaptains ?? 0}</span></div><div className="attention-list"><Link to="/captains" className="attention-item"><span className="attention-icon attention-amber"><ShieldCheck size={17} /></span><span><strong>Captain applications</strong><small>{data?.pendingCaptains ?? 0} waiting for review</small></span><ArrowRight size={16} /></Link></div><div className="attention-footer"><span><i /> Pending applications show up here from live data</span></div></article></section>
    <section className="panel table-panel"><div className="panel-heading table-heading"><div><div className="panel-kicker">LIVE OPERATIONS</div><h2>Recent orders</h2></div><Link to="/orders" className="text-link">View all orders <ArrowRight size={15} /></Link></div>{orders.error ? null : rows.length === 0 ? <div className="empty-inline">{orders.isPending ? 'Loading…' : 'No orders yet.'}</div> : <OrdersTable rows={rows.slice(0, 5)} />}</section><div className="dashboard-foot"><span><i /> {dashboard.isPending ? 'Loading…' : dashboard.error ? 'Stats unavailable' : 'Updated just now'}</span><span>Delivery commission earned <strong>{money(data?.commission ?? 0)}</strong> this month</span></div>
  </>
}
function OrdersPage() {
  const cache = useQueryClient()
  const [search, setSearch] = useState('')
  const [actionError, setActionError] = useState('')
  const orders = useData<Order[]>('orders', '/admin/orders')
  const captains = useData<Captain[]>('captains', '/admin/captains')
  const data = orders.data ?? []
  const update = useMutation({ mutationFn: ({ id, changes }: { id: string; changes: { status?: string; captainId?: string } }) => api(`/admin/orders/${id}`, { method: 'PATCH', body: JSON.stringify(changes) }), onSuccess: () => { setActionError(''); cache.invalidateQueries({ queryKey: ['orders'] }) }, onError: (error) => setActionError(error.message) })
  const filtered = data.filter((row) => `${row.reference} ${row.pickupLabel} ${row.deliveryLabel} ${row.client?.name ?? ''}`.toLowerCase().includes(search.toLowerCase()))
  const editable = Boolean(localStorage.getItem('wasalny-admin-token'))
  const statuses = ['PENDING', 'SEARCHING_CAPTAIN', 'ACCEPTED', 'ARRIVED_AT_PICKUP', 'PICKED_UP', 'ON_THE_WAY', 'DELIVERED', 'COMPLETED', 'CANCELLED']
  return <><Heading eyebrow="DELIVERY OPERATIONS" title="Orders" description="Track every shipment from pickup request to completion." action={<button className="button button-outline" onClick={() => window.print()}><Download size={15} /> Export orders</button>} /><QueryError error={orders.error} retry={orders.refetch} /><QueryError error={actionError ? { message: actionError } : null} retry={() => setActionError('')} /><section className="panel table-panel"><Toolbar value={search} setValue={setSearch} placeholder="Search by order, place, or client" /><div className="table-scroll"><table><thead><tr><th>ORDER</th><th>ROUTE</th><th>CLIENT</th><th>VALUE</th><th>STATUS</th><th>CAPTAIN</th></tr></thead><tbody>{filtered.map((row) => <tr key={row.id}><td><strong className="mono">{row.reference}</strong></td><td><div className="route-cell"><span>{row.pickupLabel}</span><span>{row.deliveryLabel}</span></div></td><td>{row.client?.name ?? '—'}</td><td className="amount">{money(row.price)}</td><td><select aria-label={`Change ${row.reference} status`} className="table-select" value={row.status} disabled={!editable || update.isPending} onChange={(event) => update.mutate({ id: row.id, changes: { status: event.target.value } })}>{statuses.map((status) => <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>)}</select></td><td><select aria-label={`Assign ${row.reference} captain`} className="table-select captain-select" value={row.captain?.id ?? ''} disabled={!editable || update.isPending} onChange={(event) => update.mutate({ id: row.id, changes: { captainId: event.target.value } })}><option value="">Unassigned</option>{(captains.data ?? []).filter((captain) => captain.status === 'ACTIVE').map((captain) => <option key={captain.user.id} value={captain.user.id}>{captain.user.name}</option>)}</select></td></tr>)}</tbody></table></div>{!orders.error && filtered.length === 0 && <div className="empty-inline">{orders.isPending ? 'Loading…' : 'No orders match this search.'}</div>}</section></>
}
const captainDocFields = [
  ['identity', 'National ID (front)', 'nationalIdDocument'],
  ['identity-back', 'National ID (back)', 'nationalIdBackDocument'],
  ['license', 'Driving license (front)', 'licenseDocument'],
  ['license-back', 'Driving license (back)', 'licenseBackDocument'],
  ['vehicle', 'Vehicle registration (front)', 'vehicleDocument'],
  ['vehicle-back', 'Vehicle registration (back)', 'vehicleBackDocument'],
  ['profile-photo', 'Profile photo', 'profilePhotoDocument'],
] as const

function useAuthBlobUrl(userId: string, docType: string, uploaded: boolean) {
  const [url, setUrl] = useState<string | null>(null)
  const [state, setState] = useState<'idle' | 'loading' | 'ready' | 'missing' | 'error'>('idle')
  useEffect(() => {
    if (!uploaded || !userId) { setState('missing'); return }
    const token = localStorage.getItem('wasalny-admin-token')
    if (!token) { setState('missing'); return }
    let objectUrl: string | null = null
    let cancelled = false
    setState('loading')
    fetch(`${API_BASE}/admin/captains/${userId}/documents/${docType}`, { headers: { Authorization: `Bearer ${token}` } })
      .then(async (response) => {
        if (response.status === 401) { handleUnauthorized(); throw new Error('unauthorized') }
        if (!response.ok) throw new Error(response.status === 404 ? 'missing' : 'failed')
        const blob = await response.blob()
        if (cancelled) return
        objectUrl = URL.createObjectURL(blob)
        setUrl(objectUrl)
        setState('ready')
      })
      .catch(() => { if (!cancelled) setState('error') })
    return () => { cancelled = true; if (objectUrl) URL.revokeObjectURL(objectUrl) }
  }, [userId, docType, uploaded])
  return { url, state }
}

function DocumentTile({ userId, docType, label, uploaded }: { userId: string; docType: string; label: string; uploaded: boolean }) {
  const { url, state } = useAuthBlobUrl(userId, docType, uploaded)
  if (state === 'missing') return <div className="doc-tile doc-missing"><span>{label}</span><small>Not uploaded</small></div>
  if (state === 'error') return <div className="doc-tile doc-missing"><span>{label}</span><small>Failed to load</small></div>
  if (!url) return <div className="doc-tile doc-missing"><span>{label}</span><small>Loading…</small></div>
  return <figure className="doc-tile"><a href={url} target="_blank" rel="noreferrer"><img src={url} alt={label} /></a><figcaption>{label}</figcaption></figure>
}

function DetailItem({ label, value }: { label: string; value?: string | null }) {
  return <div className="detail-item"><span>{label}</span><strong>{value?.trim() ? value : '—'}</strong></div>
}

function CaptainReviewPage() {
  const { userId = '' } = useParams()
  const cache = useQueryClient()
  const editable = Boolean(localStorage.getItem('wasalny-admin-token'))
  useEffect(() => { if (!editable) handleUnauthorized() }, [editable])
  const { data: captain, isLoading, error, refetch } = useQuery({
    queryKey: ['captain', userId],
    queryFn: () => api<Captain>(`/admin/captains/${userId}`),
    enabled: editable && Boolean(userId),
  })
  const [rejectOpen, setRejectOpen] = useState(false)
  const [reason, setReason] = useState('')
  const [message, setMessage] = useState('')
  const approve = useMutation({
    mutationFn: () => api(`/admin/captains/${userId}/approve`, { method: 'POST' }),
    onSuccess: () => { setMessage('Captain approved. The account is now active.'); cache.invalidateQueries({ queryKey: ['captain', userId] }); cache.invalidateQueries({ queryKey: ['captains'] }) },
    onError: (error) => setMessage(error.message),
  })
  const reject = useMutation({
    mutationFn: () => api(`/admin/captains/${userId}/reject`, { method: 'POST', body: JSON.stringify({ reason }) }),
    onSuccess: () => { setRejectOpen(false); setReason(''); setMessage('Application rejected. The captain can see the reason and resubmit documents.'); cache.invalidateQueries({ queryKey: ['captain', userId] }); cache.invalidateQueries({ queryKey: ['captains'] }) },
    onError: (error) => setMessage(error.message),
  })
  if (!editable) return <><Heading eyebrow="CAPTAIN REVIEW" title="Sign in required" description="Sign in from the login page to review applications." /></>
  if (error) return <><Heading eyebrow="CAPTAIN REVIEW" title="Could not load this application" description="The captain application could not be fetched from the API." /><QueryError error={error} retry={refetch} /></>
  if (isLoading || !captain) return <><Heading eyebrow="CAPTAIN REVIEW" title={isLoading ? 'Loading…' : 'Application not found'} description={isLoading ? 'Fetching the captain application.' : 'This captain application does not exist.'} /></>
  const missingDocs = captainDocFields.filter(([, , field]) => !isDocUploaded(captain[field as keyof Captain] as string | null | undefined))
  const canApprove = missingDocs.length === 0 && captain.status !== 'ACTIVE'
  return <>
    <Heading
      eyebrow="CAPTAIN REVIEW"
      title={captain.user.name}
      description={`Application submitted ${new Date(captain.createdAt).toLocaleDateString()}`}
      action={<div className="heading-actions"><Status value={captain.status} />
        {captain.status === 'PENDING' || captain.status === 'REJECTED'
          ? <div className="inline-actions">
              <button className="button button-primary" disabled={!canApprove || approve.isPending} title={canApprove ? 'Approve captain' : 'Required documents are missing'} onClick={() => approve.mutate()}><Check size={15} /> Approve</button>
              <button className="button button-outline" disabled={reject.isPending} onClick={() => { setRejectOpen(true); setMessage('') }}><X size={15} /> Reject</button>
            </div>
          : null}
      </div>}
    />
    {message && <p className="form-message review-message">{message}</p>}
    {captain.status === 'REJECTED' && captain.rejectionReason && <div className="review-warning"><strong>Rejection reason:</strong> {captain.rejectionReason}</div>}
    <div className="review-layout">
      <section className="panel settings-panel">
        <div className="panel-heading"><div><div className="panel-kicker">APPLICANT</div><h2>Captain details</h2></div><span className="settings-icon"><ShieldCheck size={18} /></span></div>
        <div className="detail-grid">
          <DetailItem label="Full name" value={captain.user.name} />
          <DetailItem label="Email" value={captain.user.email} />
          <DetailItem label="Phone" value={captain.user.phone} />
          <DetailItem label="National ID" value={captain.nationalIdLast4 ? `•••• ${captain.nationalIdLast4}` : null} />
          <DetailItem label="Date of birth" value={captain.dateOfBirth ? new Date(captain.dateOfBirth).toLocaleDateString() : null} />
          <DetailItem label="Governorate" value={captain.governorate} />
          <DetailItem label="Driving license no." value={captain.licenseNumber} />
          <DetailItem label="Vehicle registration no." value={captain.vehicleRegistrationNumber} />
          <DetailItem label="Vehicle type" value={captain.vehicleType} />
          <DetailItem label="Plate" value={captain.vehiclePlate} />
          <DetailItem label="Make" value={captain.vehicleMake} />
          <DetailItem label="Model" value={captain.vehicleModel} />
          <DetailItem label="Color" value={captain.vehicleColor} />
          <DetailItem label="Wallet" value={captain.user.wallet ? money(captain.user.wallet.balance) : null} />
          <DetailItem label="Approved at" value={captain.approvedAt ? new Date(captain.approvedAt).toLocaleString() : null} />
          <DetailItem label="Reviewed at" value={captain.reviewedAt ? new Date(captain.reviewedAt).toLocaleString() : null} />
        </div>
      </section>
      <section className="panel settings-panel">
        <div className="panel-heading"><div><div className="panel-kicker">DOCUMENTS</div><h2>{missingDocs.length === 0 ? 'All 7 documents uploaded' : `${missingDocs.length} of 7 documents missing`}</h2></div></div>
        <div className="doc-grid">
          {captainDocFields.map(([docType, label, field]) => (
            <DocumentTile key={docType} userId={userId} docType={docType} label={label} uploaded={isDocUploaded(captain[field as keyof Captain] as string | null | undefined)} />
          ))}
        </div>
      </section>
    </div>
    {rejectOpen && <div className="modal-scrim" role="dialog" aria-modal="true">
      <div className="modal-card">
        <div className="panel-heading"><div><div className="panel-kicker">REJECT APPLICATION</div><h2>Why is this application rejected?</h2></div><button className="icon-button" aria-label="Close" onClick={() => setRejectOpen(false)}><X size={16} /></button></div>
        <p className="settings-copy">The captain will see this reason and can update their documents and resubmit.</p>
        <textarea className="reason-input" required minLength={3} rows={4} placeholder="e.g. The driving license image is unreadable" value={reason} onChange={(event) => setReason(event.target.value)} />
        <div className="modal-actions">
          <button className="button button-outline" onClick={() => setRejectOpen(false)}>Cancel</button>
          <button className="button button-primary" disabled={reason.trim().length < 3 || reject.isPending} onClick={() => reject.mutate()}>{reject.isPending ? 'Rejecting…' : 'Reject application'}</button>
        </div>
      </div>
    </div>}
  </>
}

function CaptainsPage() {
  const [filter, setFilter] = useState('PENDING')
  const captains = useData<Captain[]>('captains', '/admin/captains')
  const [search, setSearch] = useState('')
  const data = captains.data ?? []
  const filtered = data.filter((row) => (filter === 'ALL' || row.status === filter) && `${row.user.name} ${row.user.email}`.toLowerCase().includes(search.toLowerCase()))
  const pendingCount = data.filter((row) => row.status === 'PENDING').length
  const filters = ['ALL', 'PENDING', 'ACTIVE', 'REJECTED', 'SUSPENDED']
  return <><Heading eyebrow="FLEET MANAGEMENT" title="Captains" description="Review applications and manage your delivery fleet." action={<span className="pending-chip">{applicationReviewLabel(pendingCount)}</span>} /><QueryError error={captains.error} retry={captains.refetch} /><section className="panel table-panel">
    <div className="table-toolbar"><label className="search-field"><Search size={16} /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search captains" /></label><div className="filter-chips">{filters.map((value) => <button key={value} className={`chip ${filter === value ? 'chip-active' : ''}`} onClick={() => setFilter(value)}>{value === 'ALL' ? 'All' : value === 'ACTIVE' ? 'Approved' : value.charAt(0) + value.slice(1).toLowerCase()}</button>)}</div></div>
    <div className="table-scroll"><table><thead><tr><th>CAPTAIN</th><th>VEHICLE</th><th>NATIONAL ID</th><th>WALLET</th><th>STATUS</th><th>ACTIONS</th></tr></thead><tbody>{filtered.map((row) => <tr key={row.id}>
      <td><div className="person-cell"><span className="person-avatar">{row.user.name.split(' ').map((part) => part[0]).join('').slice(0, 2)}</span><span><strong>{row.user.name}</strong><small>{row.user.email}</small></span></div></td>
      <td>{row.vehicleType ?? '—'}<small>{row.vehiclePlate ?? '—'}</small></td>
      <td className="mono">{row.nationalIdLast4 ? `•••• ${row.nationalIdLast4}` : '—'}</td>
      <td className="amount">{money(row.user.wallet?.balance ?? 0)}</td>
      <td><Status value={row.status} /></td>
      <td><Link className="text-link" to={`/captains/${row.user.id}`}><Eye size={14} /> Review</Link></td>
    </tr>)}</tbody></table></div>{!captains.error && filtered.length === 0 && <div className="empty-inline">{captains.isPending ? 'Loading…' : 'No captains match this filter.'}</div>}</section></>
}
function ClientsPage() {
  const cache = useQueryClient()
  const clients = useData<Client[]>('clients', '/admin/clients')
  const [actionError, setActionError] = useState('')
  const suspension = useMutation({ mutationFn: ({ id, suspended }: { id: string; suspended: boolean }) => api(`/admin/users/${id}/suspension`, { method: 'PATCH', body: JSON.stringify({ suspended }) }), onSuccess: () => { setActionError(''); cache.invalidateQueries({ queryKey: ['clients'] }) }, onError: (error) => setActionError(error.message) })
  const [search, setSearch] = useState('')
  const editable = Boolean(localStorage.getItem('wasalny-admin-token'))
  const rows = (clients.data ?? []).filter((row) => `${row.name} ${row.email}`.toLowerCase().includes(search.toLowerCase()))
  return <><Heading eyebrow="CUSTOMER DIRECTORY" title="Clients" description="Manage shipment senders and their account activity." /><QueryError error={clients.error} retry={clients.refetch} /><QueryError error={actionError ? { message: actionError } : null} retry={() => setActionError('')} /><section className="panel table-panel"><Toolbar value={search} setValue={setSearch} placeholder="Search clients" /><div className="table-scroll"><table><thead><tr><th>CLIENT</th><th>PHONE</th><th>ORDERS</th><th>ACCOUNT</th><th>ACTIONS</th></tr></thead><tbody>{rows.map((row) => <tr key={row.id}><td><div className="person-cell"><span className="person-avatar client-avatar">{row.name.slice(0, 2).toUpperCase()}</span><span><strong>{row.name}</strong><small>{row.email}</small></span></div></td><td>{row.phone ?? '—'}</td><td>{row._count?.clientOrders ?? 0}</td><td><Status value={row.suspendedAt ? 'SUSPENDED' : 'ACTIVE'} /></td><td><button className="text-action" disabled={!editable || suspension.isPending} onClick={() => suspension.mutate({ id: row.id, suspended: !row.suspendedAt })}>{row.suspendedAt ? 'Restore' : 'Suspend'}</button></td></tr>)}</tbody></table></div>{!clients.error && rows.length === 0 && <div className="empty-inline">{clients.isPending ? 'Loading…' : 'No clients match this search.'}</div>}</section></>
}
function PricingPage() {
  const cache = useQueryClient()
  const defaults: Pricing = { basePrice: 30, pricePerKm: 8, commissionPercent: 10, minimumWalletBalance: 0 }
  const pricing = useData<Pricing>('pricing', '/admin/pricing')
  const [form, setForm] = useState<Pricing>(defaults)
  const [saved, setSaved] = useState(false)
  const [saveError, setSaveError] = useState('')
  useEffect(() => { if (pricing.data) setForm(pricing.data) }, [pricing.data])
  const mutation = useMutation({ mutationFn: () => { if (!pricing.data) return Promise.reject(new Error('Pricing has not loaded from the API yet.')); return api('/admin/pricing', { method: 'PATCH', body: JSON.stringify(form) }) }, onSuccess: () => { setSaved(true); setSaveError(''); cache.invalidateQueries({ queryKey: ['pricing'] }) }, onError: (error) => setSaveError(error.message) })
  return <><Heading eyebrow="COMMERCIAL RULES" title="Pricing & commission" description="Set transparent, automatic rates for ready-shipment deliveries." /><QueryError error={pricing.error} retry={pricing.refetch} /><QueryError error={saveError ? { message: saveError } : null} retry={() => setSaveError('')} /><div className="settings-grid"><section className="panel settings-panel"><div className="panel-heading"><div><div className="panel-kicker">DELIVERY RATE</div><h2>Price calculation</h2></div><span className="settings-icon"><CircleDollarSign size={18} /></span></div><p className="settings-copy">Each order is priced from its pickup-to-dropoff distance. Clients see the final amount before confirming.</p><div className="field-grid"><label>Base price<span className="money-input"><span>{CURRENCY}</span><input type="number" min="0" value={form.basePrice} onChange={(event) => setForm({ ...form, basePrice: Number(event.target.value) })} /></span></label><label>Price per kilometre<span className="money-input"><span>{CURRENCY}</span><input type="number" min="0" value={form.pricePerKm} onChange={(event) => setForm({ ...form, pricePerKm: Number(event.target.value) })} /></span></label></div><div className="formula-note"><span>RATE FORMULA</span><strong>Base price + (distance × per km rate)</strong></div></section><section className="panel settings-panel"><div className="panel-heading"><div><div className="panel-kicker">CAPTAIN EARNINGS</div><h2>Commission & wallet</h2></div><span className="settings-icon orange-icon"><WalletCards size={18} /></span></div><p className="settings-copy">Commission is reserved from a captain's wallet when an order is accepted.</p><div className="field-grid"><label>Company commission<span className="money-input"><input type="number" min="0" max="100" value={form.commissionPercent} onChange={(event) => setForm({ ...form, commissionPercent: Number(event.target.value) })} /><span>%</span></span></label><label>Minimum wallet balance<span className="money-input"><span>{CURRENCY}</span><input type="number" min="0" value={form.minimumWalletBalance} onChange={(event) => setForm({ ...form, minimumWalletBalance: Number(event.target.value) })} /></span></label></div><div className="formula-note"><span>DEFAULT COMMISSION</span><strong>{form.commissionPercent}% per delivery</strong></div></section><div className="settings-save"><span>{saved ? 'Pricing changes saved.' : 'Changes apply to new orders only.'}</span><button className="button button-primary" onClick={() => mutation.mutate()} disabled={mutation.isPending}><Check size={15} />{mutation.isPending ? 'Saving…' : 'Save changes'}</button></div></div></>
}
function WalletsPage() {
  const wallets = useData<WalletRecord[]>('wallets', '/admin/wallets')
  const data = wallets.data ?? []
  const totalBalance = data.reduce((sum, row) => sum + Number(row.wallet?.balance ?? 0), 0)
  const transactions = data.flatMap((row) => row.walletTransactions.map((transaction) => ({ ...transaction, captain: row.name }))).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 100)
  return <><Heading eyebrow="CAPTAIN FINANCES" title="Wallets & transactions" description="Monitor captain balances, commission reservations, and top-ups." /><QueryError error={wallets.error} retry={wallets.refetch} /><section className="metric-grid report-metrics"><Metric label="Captain wallets" value={String(data.length)} change="Active accounts" icon={Bike} /><Metric label="Total available balance" value={money(totalBalance)} change="Across all captains" icon={WalletCards} tone="blue" /></section><section className="panel table-panel"><div className="panel-heading table-heading"><div><div className="panel-kicker">WALLET LEDGER</div><h2>Recent transactions</h2></div></div><div className="table-scroll"><table><thead><tr><th>CAPTAIN</th><th>TYPE</th><th>DETAIL</th><th>DATE</th><th>AMOUNT</th></tr></thead><tbody>{transactions.map((transaction) => <tr key={transaction.id}><td>{transaction.captain}</td><td>{transaction.type.replaceAll('_', ' ')}</td><td>{transaction.note ?? '—'}</td><td>{new Date(transaction.createdAt).toLocaleString()}</td><td className="amount">{money(transaction.amount)}</td></tr>)}</tbody></table></div>{!wallets.error && transactions.length === 0 && <div className="empty-inline">{wallets.isPending ? 'Loading…' : 'No wallet transactions recorded yet.'}</div>}</section></>
}
function ReportsPage() {
  const reports = useData<DashboardData>('dashboard', '/admin/dashboard')
  const data = reports.data
  return <><Heading eyebrow="BUSINESS INTELLIGENCE" title="Reports" description="A clear read on completed deliveries and company earnings." action={<button className="button button-outline" onClick={() => window.print()}><Download size={15} /> Export report</button>} /><QueryError error={reports.error} retry={reports.refetch} /><section className="metric-grid report-metrics"><Metric label="Completed deliveries" value={Number(data?.completedOrders ?? 0).toLocaleString()} icon={Check} /><Metric label="Gross delivery value" value={money(data?.revenue ?? 0)} icon={ArrowUpRight} tone="blue" /><Metric label="Company commission" value={money(data?.commission ?? 0)} icon={CircleDollarSign} tone="orange" /></section><section className="panel activity-panel report-chart"><div className="panel-heading"><div><div className="panel-kicker">WEEKLY PERFORMANCE</div><h2>Delivery value</h2></div><span className="select-control">This week</span></div><RevenueChart data={data?.weeklyRevenue} /></section></>
}
function SettingsPage() {
  const token = localStorage.getItem('wasalny-admin-token')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState('')
  const login = useMutation({ mutationFn: () => api<{ accessToken: string }>('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) }), onSuccess: (data) => { localStorage.setItem('wasalny-admin-token', data.accessToken); window.location.assign('/') }, onError: (error) => setMessage(error.message) })
  return <><Heading eyebrow="WORKSPACE CONFIGURATION" title="Settings" description="Manage administrator access and service connectivity." /><div className="settings-grid"><section className="panel settings-panel"><div className="panel-heading"><div><div className="panel-kicker">ADMINISTRATOR ACCESS</div><h2>{token ? 'Connected session' : 'Connect your account'}</h2></div><span className="settings-icon"><ShieldCheck size={18} /></span></div>{token ? <><p className="settings-copy">This browser has an administrator access token.</p><button className="button button-outline" onClick={() => { localStorage.removeItem('wasalny-admin-token'); window.location.reload() }}>Sign out</button></> : <form className="access-form" onSubmit={(event) => { event.preventDefault(); login.mutate() }}><label>Admin email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="admin@wasalny.app" /></label><label>Password<input type="password" required value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" /></label><button className="button button-primary" disabled={login.isPending}>{login.isPending ? 'Connecting…' : 'Connect administrator'}</button>{message && <p className="form-message">{message}</p>}</form>}</section><section className="panel settings-panel"><div className="panel-heading"><div><div className="panel-kicker">SERVICE STATUS</div><h2>Connected services</h2></div><span className="settings-icon"><Activity size={18} /></span></div><div className="service-list"><div><span><i /> API endpoint</span><code>{import.meta.env.VITE_API_URL ?? 'http://localhost:3000/api/v1'}</code></div><div><span><i /> Payment processing</span><small>Ready for Kashier integration</small></div><div><span><i /> Push notifications</span><small>Firebase credentials required</small></div></div></section></div></>
}
function AuthPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState('')
  const navigate = useNavigate()
  const login = useMutation({ mutationFn: () => api<{ accessToken: string }>('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) }), onSuccess: (data) => { localStorage.setItem('wasalny-admin-token', data.accessToken); navigate('/', { replace: true }) }, onError: (error) => setMessage(error.message) })
  return <div className="login-shell"><span className="login-mark"><Boxes size={23} /></span><div className="eyebrow">WASALNY ORDERS</div><h1>Administrator sign in</h1><p>Sign in to review captain applications and live operations.</p><form className="access-form login-form" onSubmit={(event) => { event.preventDefault(); login.mutate() }}><label>Admin email<input type="email" required autoComplete="username" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="admin@wasalny.app" /></label><label>Password<input type="password" required autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" /></label><button className="button button-primary" disabled={login.isPending}>{login.isPending ? 'Signing in…' : 'Sign in'}</button>{message && <p className="form-message">{message}</p>}</form></div>
}

export default function Dashboard() {
  return <Routes><Route path="/login" element={<AuthPage />} /><Route element={<Frame />}><Route index element={<Overview />} /><Route path="orders" element={<OrdersPage />} /><Route path="captains" element={<CaptainsPage />} /><Route path="captains/:userId" element={<CaptainReviewPage />} /><Route path="clients" element={<ClientsPage />} /><Route path="wallets" element={<WalletsPage />} /><Route path="topups" element={<TopUpsPage />} /><Route path="reports" element={<ReportsPage />} /><Route path="pricing" element={<PricingPage />} /><Route path="settings" element={<SettingsPage />} /><Route path="*" element={<Navigate to="/login" replace />} /></Route></Routes>
}