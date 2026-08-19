import { Module } from "@nestjs/common";
import { APP_GUARD } from "@nestjs/core";
import { ConfigModule } from "@nestjs/config";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { CoreModule } from "./core/core.module.js";
import { HealthModule } from "./modules/health/health.module.js";
import { ArtifactsModule } from "./modules/artifacts/artifacts.module.js";
import { LicensesModule } from "./modules/licenses/licenses.module.js";
import { RuntimeModule } from "./modules/runtime/runtime.module.js";
import { AdminModule } from "./modules/admin/admin.module.js";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    CoreModule,
    HealthModule,
    ArtifactsModule,
    LicensesModule,
    RuntimeModule,
    AdminModule,
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
