import { Test, TestingModule } from '@nestjs/testing';
import { ThrottlerGuard } from '@nestjs/throttler';
import { ConfigService } from '@nestjs/config';
import { FirebaseController } from './firebase.controller';
import { FirebaseService } from './firebase.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Mock FirebaseService to avoid importing firebase-admin
const mockFirebaseService = {
  isInitialized: jest.fn(),
  createCustomToken: jest.fn(),
};

const mockConfigService = {
  get: jest.fn(),
};

const mockReq = {
  user: { sub: 'user-1', role: 'CLIENT' },
};

describe('FirebaseController', () => {
  let controller: FirebaseController;
  let configService: ConfigService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      controllers: [FirebaseController],
      providers: [
        { provide: ConfigService, useValue: mockConfigService },
        { provide: FirebaseService, useValue: mockFirebaseService },
      ],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({ canActivate: () => true })
      .overrideGuard(ThrottlerGuard)
      .useValue({ canActivate: () => true })
      .compile();

    controller = module.get<FirebaseController>(FirebaseController);
    configService = module.get<ConfigService>(ConfigService);
  });

  describe('createCustomToken', () => {
    it('should return error when chat is disabled', async () => {
      mockConfigService.get.mockReturnValue(false);

      const result = await controller.createCustomToken(mockReq as any);

      expect(result).toEqual({ error: 'Chat feature is currently disabled', code: 'CHAT_DISABLED' });
    });

    it('should return error when firebase not initialized', async () => {
      mockConfigService.get.mockReturnValue(true);
      mockFirebaseService.isInitialized.mockReturnValue(false);

      const result = await controller.createCustomToken(mockReq as any);

      expect(result).toEqual({ error: 'Firebase is not configured on the server', code: 'FIREBASE_NOT_CONFIGURED' });
    });

    it('should return custom token when everything is configured', async () => {
      mockConfigService.get.mockReturnValue(true);
      mockFirebaseService.isInitialized.mockReturnValue(true);
      mockFirebaseService.createCustomToken.mockResolvedValue('custom-token-123');

      const result = await controller.createCustomToken(mockReq as any);

      expect(result).toEqual({ customToken: 'custom-token-123' });
      expect(mockFirebaseService.createCustomToken).toHaveBeenCalledWith('user-1', {
        role: 'CLIENT',
      });
    });
  });

  describe('health', () => {
    it('should return health status', async () => {
      mockConfigService.get.mockReturnValue(true);
      mockFirebaseService.isInitialized.mockReturnValue(true);

      const result = controller.health();

      expect(result).toEqual({ initialized: true, chatEnabled: true });
    });
  });
});