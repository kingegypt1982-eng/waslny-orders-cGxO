import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { FirebaseService } from './firebase.service';

jest.mock('firebase-admin/app', () => ({
  initializeApp: jest.fn().mockReturnValue({ name: '[DEFAULT]' }),
  cert: jest.fn(),
  getApp: jest.fn(),
  App: jest.fn(),
}));

jest.mock('firebase-admin/auth', () => ({
  getAuth: jest.fn().mockReturnValue({
    createCustomToken: jest.fn().mockResolvedValue('mock-custom-token'),
    verifyIdToken: jest.fn().mockResolvedValue({ uid: 'test-uid', role: 'CLIENT' }),
  }),
}));

jest.mock('firebase-admin/database', () => ({
  getDatabase: jest.fn().mockReturnValue({ ref: jest.fn() }),
  Database: jest.fn(),
}));

describe('FirebaseService', () => {
  let service: FirebaseService;
  let configService: ConfigService;

  const mockConfig = {
    get: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FirebaseService,
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();

    service = module.get<FirebaseService>(FirebaseService);
    configService = module.get<ConfigService>(ConfigService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('should not initialize when FIREBASE_SERVICE_ACCOUNT_PATH is not set', () => {
    mockConfig.get.mockReturnValue(undefined);
    service.onModuleInit();
    expect(service.isInitialized()).toBe(false);
  });

  it('should return null for database when not initialized', () => {
    expect(service.getDatabase()).toBeNull();
  });
});