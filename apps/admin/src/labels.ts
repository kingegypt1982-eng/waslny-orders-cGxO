export function applicationReviewLabel(pendingCount: number): string {
  return pendingCount === 1 ? '1 application to review' : `${pendingCount} applications to review`
}

export function isDocUploaded(value: string | null | undefined): boolean {
  return Boolean(value) && value !== 'PENDING_UPLOAD'
}
