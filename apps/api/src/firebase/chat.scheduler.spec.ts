import { Test, TestingModule } from '@nestjs/testing';
import { ChatService } from './chat.service';
import { ChatScheduler } from './chat.scheduler';

describe('ChatScheduler', () => {
  let scheduler: ChatScheduler;
  let chatService: ChatService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const mockChatService = {
      cleanupOldChats: jest.fn().mockResolvedValue({ checked: 0, deleted: 0 }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatScheduler,
        { provide: ChatService, useValue: mockChatService },
      ],
    }).compile();

    scheduler = module.get<ChatScheduler>(ChatScheduler);
    chatService = module.get<ChatService>(ChatService);
  });

  it('should be defined', () => {
    expect(scheduler).toBeDefined();
  });

  it('should call cleanupOldChats on schedule', async () => {
    await scheduler.cleanupChats();
    expect(chatService.cleanupOldChats).toHaveBeenCalled();
  });

  it('should not run cleanup twice concurrently', async () => {
    // First call starts
    const promise1 = scheduler.cleanupChats();
    // Second call should skip
    await scheduler.cleanupChats();

    await promise1;
    expect(chatService.cleanupOldChats).toHaveBeenCalledTimes(1);
  });
});