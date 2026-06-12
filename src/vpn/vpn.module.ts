import { Module } from '@nestjs/common';
import { RemnawaveModule } from '../remnawave/remnawave.module';
import { VpnController } from './vpn.controller';
import { VpnService } from './vpn.service';

@Module({
  imports: [RemnawaveModule],
  controllers: [VpnController],
  providers: [VpnService],
  exports: [VpnService],
})
export class VpnModule {}
