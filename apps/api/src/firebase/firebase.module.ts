import { Module, Global } from '@nestjs/common';
import { FirebaseService } from './firebase.service';
import { ChatService } from './chat.service';
import { ChatScheduler } from './chat.scheduler';
import { FcmService } from './fcm.service';

@Global()
@Module({
  providers: [FirebaseService, ChatService, ChatScheduler, FcmService],
  exports: [FirebaseService, ChatService, FcmService],
})
export class FirebaseModule {}