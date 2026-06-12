import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { JwtUser } from '../common/types/jwt-user.type';
import { VpnService } from './vpn.service';

@ApiTags('VPN')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('vpn')
export class VpnController {
  constructor(private readonly vpnService: VpnService) {}

  @Get('profile')
  profile(@CurrentUser() user: JwtUser) {
    return this.vpnService.getProfile(user.sub);
  }

  @Get('usage')
  usage(@CurrentUser() user: JwtUser) {
    return this.vpnService.getUsage(user.sub);
  }

  @Post('enable')
  enable(@CurrentUser() user: JwtUser) {
    return this.vpnService.enable(user.sub);
  }

  @Post('disable')
  disable(@CurrentUser() user: JwtUser) {
    return this.vpnService.disable(user.sub);
  }

  @Post('reset-traffic')
  resetTraffic(@CurrentUser() user: JwtUser) {
    return this.vpnService.resetTraffic(user.sub);
  }

  @Post('regenerate-subscription')
  regenerateSubscription(@CurrentUser() user: JwtUser) {
    return this.vpnService.regenerateSubscription(user.sub);
  }
}
