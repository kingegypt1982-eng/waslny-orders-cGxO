import { OrdersScheduler } from './orders.scheduler';
import { OrdersService } from './orders.service';

describe('OrdersScheduler', () => {
  const orders = { expireStaleSearches: jest.fn() };
  const scheduler = new OrdersScheduler(orders as unknown as OrdersService);

  beforeEach(() => jest.clearAllMocks());

  it('runs the expiry sweep', async () => {
    orders.expireStaleSearches.mockResolvedValue({ checked: 3, expired: 2 });

    await scheduler.expireSearches();

    expect(orders.expireStaleSearches).toHaveBeenCalledTimes(1);
  });

  it('does not stack overlapping cycles', async () => {
    let release: (value: unknown) => void = () => undefined;
    const pending = new Promise((resolve) => { release = resolve; });
    orders.expireStaleSearches.mockReturnValue(pending);

    const first = scheduler.expireSearches();
    await scheduler.expireSearches();
    expect(orders.expireStaleSearches).toHaveBeenCalledTimes(1);

    release({ checked: 0, expired: 0 });
    await first;
  });

  it('swallows service failures so the next cycle still runs', async () => {
    orders.expireStaleSearches.mockRejectedValue(new Error('database is down'));

    await expect(scheduler.expireSearches()).resolves.toBeUndefined();
  });
});
