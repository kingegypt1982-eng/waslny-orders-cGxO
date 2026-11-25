import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { ChatService } from './chat.service';
import { OrderStatus } from '@prisma/client';
import { Database } from 'firebase-admin/database';
import { FirebaseService } from './firebase.service';

const mockPrisma = {
  order: {
    findUnique: jest.fn(),
  },
};

const mockConfig = {
  get: jest.fn(),
};

let mockDatabase: any;

jest.mock('firebase-admin/app', () => ({
  initializeApp: jest.fn(),
  cert: jest.fn(),
  getApp: jest.fn(),
}));

jest.mock('firebase-admin/database', () => ({
  getDatabase: jest.fn(),
  Database: jest.fn(),
}));

// Initialize after mocks
mockDatabase = {
  ref: jest.fn().mockReturnThis(),
  child: jest.fn().mockReturnThis(),
  set: jest.fn().mockResolvedValue(undefined),
  once: jest.fn().mockResolvedValue({ exists: () => false, val: () => null, forEach: () => false }),
  remove: jest.fn().mockResolvedValue(undefined),
  orderByChild: jest.fn().mockReturnThis(),
  endAt: jest.fn().mockReturnThis(),
  limitToLast: jest.fn().mockReturnThis(),
};

describe('ChatService', () => {
  let service: ChatService;
  let prismaService: PrismaService;
  let mockFirebaseService: Partial<FirebaseService>;

  beforeEach(async () => {
    jest.clearAllMocks();

    mockConfig.get.mockImplementation((key: string) => {
      if (key === 'CHAT_CLEANUP_DAYS') return 7;
      if (key === 'FIREBASE_DATABASE_URL') return 'https://test.firebaseio.com';
      if (key === 'CHAT_ENABLED') return true;
      return undefined;
    });

    mockPrisma.order.findUnique.mockReset();
    mockDatabase.ref.mockReturnValue(mockDatabase);
    mockDatabase.child.mockReturnValue(mockDatabase);
    mockDatabase.set.mockResolvedValue(undefined);
    mockDatabase.once.mockResolvedValue({ exists: () => false, val: () => null, forEach: () => false });
    mockDatabase.remove.mockResolvedValue(undefined);
    mockDatabase.orderByChild.mockReturnValue(mockDatabase);
    mockDatabase.endAt.mockReturnValue(mockDatabase);
    mockDatabase.limitToLast.mockReturnValue(mockDatabase);

    mockFirebaseService = {
      getDatabase: jest.fn().mockReturnValue(mockDatabase),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatService,
        { provide: ConfigService, useValue: mockConfig },
        { provide: PrismaService, useValue: mockPrisma },
        { provide: FirebaseService, useValue: mockFirebaseService },
      ],
    }).compile();

    service = module.get<ChatService>(ChatService);
    prismaService = module.get<PrismaService>(PrismaService);
    // Initialize the database by calling onModuleInit
    await service.onModuleInit();
  });

  describe('createChatForOrder', () => {
    it('should create chat meta when order is ACCEPTED', async () => {
      mockPrisma.order.findUnique.mockResolvedValue({
        id: 'order-1',
        clientId: 'client-1',
        captainId: 'captain-1',
        status: OrderStatus.ACCEPTED,
      });

      await service.createChatForOrder('order-1');

      expect(mockDatabase.child).toHaveBeenCalledWith('meta');
      expect(mockDatabase.child).toHaveBeenCalledWith('order-1');
      expect(mockDatabase.set).toHaveBeenCalledWith(expect.objectContaining({
        orderId: 'order-1',
        clientId: 'client-1',
        captainId: 'captain-1',
        status: 'ACTIVE',
      }));
    });

    it('should not create chat when order not found', async () => {
      mockPrisma.order.findUnique.mockResolvedValue(null);

      await service.createChatForOrder('order-1');

      expect(mockDatabase.set).not.toHaveBeenCalled();
    });

    it('should not create chat when order not ACCEPTED', async () => {
      mockPrisma.order.findUnique.mockResolvedValue({
        id: 'order-1',
        clientId: 'client-1',
        captainId: 'captain-1',
        status: OrderStatus.PENDING,
      });

      await service.createChatForOrder('order-1');

      expect(mockDatabase.set).not.toHaveBeenCalled();
    });
  });

  describe('closeChatForOrder', () => {
    it('should close active chat', async () => {
      mockDatabase.once.mockResolvedValueOnce({
        exists: () => true,
        val: () => ({
          orderId: 'order-1',
          clientId: 'client-1',
          captainId: 'captain-1',
          status: 'ACTIVE',
          createdAt: Date.now(),
        }),
      });

      await service.closeChatForOrder('order-1', 'COMPLETED');

      expect(mockDatabase.set).toHaveBeenCalledWith(expect.objectContaining({
        status: 'CLOSED',
        closeReason: 'COMPLETED',
      }));
    });

    it('should not close already closed chat', async () => {
      mockDatabase.once.mockResolvedValueOnce({
        exists: () => true,
        val: () => ({
          orderId: 'order-1',
          status: 'CLOSED',
        }),
      });

      await service.closeChatForOrder('order-1', 'COMPLETED');

      expect(mockDatabase.set).not.toHaveBeenCalled();
    });
  });

  describe('reassignChat', () => {
    it('should reassign active chat to new captain', async () => {
      mockDatabase.once.mockResolvedValueOnce({
        exists: () => true,
        val: () => ({
          orderId: 'order-1',
          clientId: 'client-1',
          captainId: 'captain-1',
          status: 'ACTIVE',
        }),
      });

      await service.reassignChat('order-1', 'captain-2');

      expect(mockDatabase.set).toHaveBeenCalledWith(expect.objectContaining({
        captainId: 'captain-2',
      }));
    });
  });

  describe('cleanupOldChats', () => {
    it('should clean up old closed chats', async () => {
      const oldClosedAt = Date.now() - 8 * 24 * 60 * 60 * 1000; // 8 days ago
      mockDatabase.once.mockResolvedValueOnce({
        exists: () => true,
        forEach: (callback: (child: any) => void) => {
          callback({ key: 'order-1', val: () => ({ status: 'CLOSED', closedAt: oldClosedAt }) });
        },
      });

      const result = await service.cleanupOldChats();

      expect(result.deleted).toBe(1);
      expect(mockDatabase.remove).toHaveBeenCalledTimes(2); // messages + meta
    });
  });
});