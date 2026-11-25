import { TopUpsService } from './topups.service';
import { TopupsScheduler } from './topups.scheduler';

describe('TopupsScheduler', () => {
  it('never overlaps two reconciliation cycles', async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const topUps = { reconcilePendingBatch: jest.fn(() => gate.then(() => ({ checked: 1, charged: 0 }))) };
    const scheduler = new TopupsScheduler(topUps as unknown as TopUpsService);

    const first = scheduler.reconcile();
    const second = scheduler.reconcile();
    release();
    await Promise.all([first, second]);

    expect(topUps.reconcilePendingBatch).toHaveBeenCalledTimes(1);
  });
});
