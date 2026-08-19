import "reflect-metadata";
import { ValidationPipe } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import helmet from "helmet";
import { AppModule } from "./app.module.js";
import { AppConfig } from "./core/app-config.js";

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.use(helmet());
  app.enableShutdownHooks();
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  const config = app.get(AppConfig);
  config.validateProduction();
  await app.listen(config.port, "0.0.0.0");
}

bootstrap().catch((error) => {
  console.error(
    JSON.stringify({
      level: "fatal",
      message: error instanceof Error ? error.message : String(error),
    }),
  );
  process.exit(1);
});
