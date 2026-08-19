import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AppConfig } from './config.js';
import { PrismaService } from './prisma.service.js';
import { HealthController } from './health.controller.js';
import { AdminGuard } from './admin.guard.js';
import { ArtifactService } from './artifact.service.js';
import { ArtifactController } from './artifact.controller.js';
import { LicenseService } from './license.service.js';
import { LicenseController } from './license.controller.js';
import { RuntimeController } from './runtime.controller.js';
import { AdminController } from './admin.controller.js';
import { SyncService } from './sync.service.js';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true }), ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }])],
  controllers: [HealthController, ArtifactController, LicenseController, RuntimeController, AdminController],
  providers: [AppConfig, PrismaService, AdminGuard, ArtifactService, LicenseService, SyncService, { provide: APP_GUARD, useClass: ThrottlerGuard }]
})
export class AppModule {}
