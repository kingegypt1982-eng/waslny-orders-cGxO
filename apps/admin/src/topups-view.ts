// Pure view helpers for the admin Top-ups page. Keeping them separate from the
// React component lets the filter/summary rules be tested without a DOM.

export const TOP_UP_STATUSES = ['PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED'] as const
export type TopUpStatusFilter = (typeof TOP_UP_STATUSES)[number] | ''

export type TopUpRow = {
  id: string
  status: string
  amount: number | string
  creditAmount: number | string
  chargeAmount: number | string
  feeAmount: number | string
  currency: string
  createdAt: string
  paidAt?: string | null
  failureReason?: string | null
  providerOrderRef?: string | null
  user?: { id?: string; name?: string } | null
}

export const TOP_UP_FILTERS: { value: TopUpStatusFilter; label: string }[] = [
  { value: '', label: 'All statuses' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'SUCCEEDED', label: 'Succeeded' },
  { value: 'FAILED', label: 'Failed' },
  { value: 'EXPIRED', label: 'Expired' },
]

export function isTopUpStatus(value: string): value is TopUpStatusFilter {
  return value === '' || (TOP_UP_STATUSES as readonly string[]).includes(value)
}

/** Only server-supported status values are sent; unknown values are ignored. */
export function buildTopUpsPath(status: string, take = 100): string {
  const params = new URLSearchParams()
  if (isTopUpStatus(status) && status !== '') params.set('status', status)
  params.set('take', String(Math.min(Math.max(take, 1), 200)))
  return `/admin/topups?${params.toString()}`
}

export function topUpStatusLabel(status: string): string {
  return TOP_UP_FILTERS.find((filter) => filter.value === status)?.label ?? status
}

export function topUpSummary(rows: TopUpRow[]) {
  const count = (status: string) => rows.filter((row) => row.status === status).length
  return {
    total: rows.length,
    succeeded: count('SUCCEEDED'),
    pending: count('PENDING'),
    failed: count('FAILED') + count('EXPIRED'),
    credited: rows
      .filter((row) => row.status === 'SUCCEEDED')
      .reduce((sum, row) => sum + Number(row.creditAmount ?? 0), 0),
  }
}

export function topUpDate(value: string | null | undefined): string {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString()
}
