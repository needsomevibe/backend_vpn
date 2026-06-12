import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { JwtUser } from '../common/types/jwt-user.type';
import { UsersService } from './users.service';

@ApiTags('User')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('me')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  me(@CurrentUser() user: JwtUser) {
    return this.usersService.getMe(user.sub);
  }
}
