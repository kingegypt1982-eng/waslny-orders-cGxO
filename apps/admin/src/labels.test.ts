import { describe, expect, it } from 'vitest'
import { applicationReviewLabel, isDocUploaded } from './labels'

describe('applicationReviewLabel', () => {
  it('uses the singular form for exactly one application', () => {
    expect(applicationReviewLabel(1)).toBe('1 application to review')
  })

  it('uses the plural form for zero and for many', () => {
    expect(applicationReviewLabel(0)).toBe('0 applications to review')
    expect(applicationReviewLabel(6)).toBe('6 applications to review')
  })
})

describe('isDocUploaded', () => {
  it('treats missing values and PENDING_UPLOAD as not uploaded', () => {
    expect(isDocUploaded(undefined)).toBe(false)
    expect(isDocUploaded(null)).toBe(false)
    expect(isDocUploaded('')).toBe(false)
    expect(isDocUploaded('PENDING_UPLOAD')).toBe(false)
  })

  it('accepts stored document paths', () => {
    expect(isDocUploaded('captains/u1/a.jpg')).toBe(true)
  })
})
