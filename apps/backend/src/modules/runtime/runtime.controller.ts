import {
  Controller,
  Get,
  Header,
  Req,
  Res,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import type { Request, Response } from "express";
import { RuntimeService } from "./runtime.service.js";

@Controller("/v1")
export class RuntimeController {
  constructor(private readonly runtimeService: RuntimeService) {}

  @Get("appcast.xml")
  @Header("Content-Type", "application/rss+xml; charset=utf-8")
  async appcast(
    @Req() request?: Request,
    @Res({ passthrough: true }) response?: Response,
  ): Promise<string> {
    const body = await this.runtimeService.appcast();
    return this.cachedBody(body, request, response);
  }

  @Get("runtime/manifest")
  async manifest(
    @Req() request?: Request,
    @Res({ passthrough: true }) response?: Response,
  ): Promise<unknown> {
    const body = await this.runtimeService.manifest();
    const serialized = JSON.stringify(body);
    const etag = this.etag(serialized);
    this.setCacheHeaders(response, etag);
    if (this.matches(request, etag)) {
      response?.status(304);
      return "";
    }
    return body;
  }

  private cachedBody(
    body: string,
    request?: Request,
    response?: Response,
  ): string {
    const etag = this.etag(body);
    this.setCacheHeaders(response, etag);
    if (this.matches(request, etag)) {
      response?.status(304);
      return "";
    }
    return body;
  }

  private setCacheHeaders(response: Response | undefined, etag: string): void {
    response?.setHeader("ETag", etag);
    response?.setHeader(
      "Cache-Control",
      "public, max-age=60, stale-while-revalidate=300",
    );
  }

  private matches(request: Request | undefined, etag: string): boolean {
    const value = request?.headers["if-none-match"];
    const header = Array.isArray(value) ? value.join(",") : value;
    return header === "*" || header?.split(",").some((candidate) => candidate.trim() === etag) === true;
  }

  private etag(body: string): string {
    return `"${createHash("sha256").update(body).digest("hex")}"`;
  }
}
