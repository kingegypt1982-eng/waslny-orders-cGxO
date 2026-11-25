import { describe, expect, it } from 'vitest'
import {
  TOP_UP_FILTERS,
  buildTopUpsPath,
  isTopUpStatus,
  topUpDate,
  topUpStatusLabel,
  topUpSummary,
  type TopUpRow,
} from './topups-view'

const row = (overrides: Partial<TopUpRow> = {}): TopUpRow => ({
  id: 't1',
  status: 'PENDING',
  amount: 100,
  creditAmount: 100,
  chargeAmount: 102.56,
  feeAmount: 2.56,
  currency: 'EGP',
  createdAt: '2026-11-20T10:00:00.000Z',
  ...overrides,
})

describe('top-up status filters', () => {
  it('offers exactly the server-supported statuses plus "all"', () => {
    expect(TOP_UP_FILTERS.map((filter) => filter.value)).toEqual([
      '', 'PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED',
    ])
    expect(isTopUpStatus('SUCCEEDED')).toBe(true)
    expect(isTopUpStatus('REFUNDED')).toBe(false)
  })

  it('only sends known statuses to GET /admin/topups', () => {
    expect(buildTopUpsPath('')).toBe('/admin/topups?take=100')
    expect(buildTopUpsPath('SUCCEEDED')).toBe('/admin/topups?status=SUCCEEDED&take=100')
    expect(buildTopUpsPath('DROP TABLE')).toBe('/admin/topups?take=100')
    expect(buildTopUpsPath('FAILED', 500)).toBe('/admin/topups?status=FAILED&take=200')
  })

  it('uses human labels and falls back to the raw status', () => {
    expect(topUpStatusLabel('SUCCEEDED')).toBe('Succeeded')
    expect(topUpStatusLabel('UNKNOWN')).toBe('UNKNOWN')
  })
})

describe('topUpSummary', () => {
  it('counts statuses and sums only succeeded net credits', () => {
    const summary = topUpSummary([
      row({ id: 'a', status: 'SUCCEEDED', creditAmount: 100 }),
      row({ id: 'b', status: 'SUCCEEDED', creditAmount: '50.50' }),
      row({ id: 'c', status: 'PENDING' }),
      row({ id: 'd', status: 'FAILED' }),
      row({ id: 'e', status: 'EXPIRED' }),
    ])
    expect(summary).toEqual({ total: 5, succeeded: 2, pending: 1, failed: 2, credited: 150.5 })
  })

  it('handles an empty result while loading', () => {
    expect(topUpSummary([])).toEqual({ total: 0, succeeded: 0, pending: 0, failed: 0, credited: 0 })
  })
})

describe('topUpDate', () => {
  it('shows a placeholder for missing or invalid dates', () => {
    expect(topUpDate(null)).toBe('—')
    expect(topUpDate('not-a-date')).toBe('—')
    expect(topUpDate('2026-11-20T10:00:00.000Z')).not.toBe('—')
  })
})
