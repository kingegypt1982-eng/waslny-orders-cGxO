/**
 * Shared contracts for Wasalny Orders.
 * Single source of truth for order lifecycle, roles, and pricing rules.
 * Backend (Prisma enums), admin dashboard, and mobile app must stay aligned.
 */

export const UserRole = {
  CLIENT: 'CLIENT',
  CAPTAIN: 'CAPTAIN',
  ADMIN: 'ADMIN',
} as const;
export type UserRole = (typeof UserRole)[keyof typeof UserRole];

export const CaptainStatus = {
  PENDING: 'PENDING',
  ACTIVE: 'ACTIVE',
  REJECTED: 'REJECTED',
  SUSPENDED: 'SUSPENDED',
} as const;
export type CaptainStatus = (typeof CaptainStatus)[keyof typeof CaptainStatus];

export const OrderStatus = {
  PENDING: 'PENDING',
  SEARCHING_CAPTAIN: 'SEARCHING_CAPTAIN',
  ACCEPTED: 'ACCEPTED',
  ARRIVED_AT_PICKUP: 'ARRIVED_AT_PICKUP',
  PICKED_UP: 'PICKED_UP',
  ON_THE_WAY: 'ON_THE_WAY',
  DELIVERED: 'DELIVERED',
  COMPLETED: 'COMPLETED',
  CANCELLED: 'CANCELLED',
} as const;
export type OrderStatus = (typeof OrderStatus)[keyof typeof OrderStatus];

/** Captain-only forward transitions in trip order. */
export const ORDER_TRANSITIONS: Record<string, string[]> = {
  [OrderStatus.ACCEPTED]: [OrderStatus.ARRIVED_AT_PICKUP],
  [OrderStatus.ARRIVED_AT_PICKUP]: [OrderStatus.PICKED_UP],
  [OrderStatus.PICKED_UP]: [OrderStatus.ON_THE_WAY],
  [OrderStatus.ON_THE_WAY]: [OrderStatus.DELIVERED],
};

export const ShipmentCategory = {
  PAPERS: 'PAPERS',
  MATERIALS: 'MATERIALS',
  GOODS: 'GOODS',
  SPARE_PARTS: 'SPARE_PARTS',
  PACKAGE: 'PACKAGE',
  OTHER: 'OTHER',
} as const;
export type ShipmentCategory = (typeof ShipmentCategory)[keyof typeof ShipmentCategory];

export const WalletTransactionType = {
  TOP_UP: 'TOP_UP',
  ORDER_COMMISSION: 'ORDER_COMMISSION',
  COMMISSION_REFUND: 'COMMISSION_REFUND',
  ADJUSTMENT: 'ADJUSTMENT',
} as const;
export type WalletTransactionType =
  (typeof WalletTransactionType)[keyof typeof WalletTransactionType];

export const PaymentStatus = {
  PENDING: 'PENDING',
  SUCCEEDED: 'SUCCEEDED',
  FAILED: 'FAILED',
  REFUNDED: 'REFUNDED',
} as const;
export type PaymentStatus = (typeof PaymentStatus)[keyof typeof PaymentStatus];

export const DEFAULT_PRICING = {
  basePrice: 30,
  pricePerKm: 8,
  commissionPercent: 10,
  minimumWalletBalance: 0,
  currency: 'EGP',
} as const;

/** Price = base + distanceKm * perKm. Commission = price * commission%. */
export function quotePrice(
  distanceKm: number,
  pricing: {
    basePrice: number;
    pricePerKm: number;
    commissionPercent: number;
  } = DEFAULT_PRICING,
): { distanceKm: number; price: number; commission: number } {
  const distance = Math.round(distanceKm * 100) / 100;
  const price = Number((pricing.basePrice + distance * pricing.pricePerKm).toFixed(2));
  const commission = Number(((price * pricing.commissionPercent) / 100).toFixed(2));
  return { distanceKm: distance, price, commission };
}

export const API_ROUTES = {
  register: '/auth/register',
  login: '/auth/login',
  quote: '/orders/quote',
  orders: '/orders',
  availableOrders: '/orders/available',
  captainProfile: '/captains/me',
  captainLocation: '/captains/location',
  captainWallet: '/captains/wallet',
  adminDashboard: '/admin/dashboard',
  adminOrders: '/admin/orders',
  adminCaptains: '/admin/captains',
  adminClients: '/admin/clients',
  adminWallets: '/admin/wallets',
  adminPricing: '/admin/pricing',
} as const;
