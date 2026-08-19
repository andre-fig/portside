import { Module } from "@nestjs/common";
import { AppConfig } from "./app-config.js";
import { PrismaService } from "../database/prisma.service.js";

@Module({
  providers: [AppConfig, PrismaService],
  exports: [AppConfig, PrismaService],
})
export class CoreModule {}
