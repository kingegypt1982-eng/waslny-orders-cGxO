import { Body, Controller, Patch, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from './auth.decorators';
import { JwtAuthGuard } from './jwt-auth.guard';
import { ProfileUpdateDto } from './dto/profile-update.dto';
import { ProfileService } from './profile.service';

@ApiTags('Profile')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('auth')
export class ProfileController {
  constructor(private readonly profile: ProfileService) {}

  @Patch('profile')
  update(@CurrentUser() user: { id: string }, @Body() body: ProfileUpdateDto) {
    return this.profile.update(user.id, body);
  }
}