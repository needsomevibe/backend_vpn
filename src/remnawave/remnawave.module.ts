import { HttpModule } from '@nestjs/axios';
import { Module } from '@nestjs/common';
import { RemnawaveService } from './remnawave.service';

@Module({
  imports: [
    HttpModule.register({
      timeout: 15_000,
      maxRedirects: 3,
    }),
  ],
  providers: [RemnawaveService],
  exports: [RemnawaveService],
})
export class RemnawaveModule {}
