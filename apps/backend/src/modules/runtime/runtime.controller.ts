import {
  Controller,
  Get,
  Header,
} from "@nestjs/common";
import { RuntimeService } from "./runtime.service.js";

@Controller("/v1")
export class RuntimeController {
  constructor(private readonly runtimeService: RuntimeService) {}

  @Get("appcast.xml")
  @Header("Content-Type", "application/rss+xml; charset=utf-8")
  appcast(): Promise<string> {
    return this.runtimeService.appcast();
  }

  @Get("runtime/manifest")
  manifest(): Promise<unknown> {
    return this.runtimeService.manifest();
  }
}
