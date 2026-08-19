import { Controller, Get, Header, ServiceUnavailableException } from '@nestjs/common';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { AppConfig } from './config.js';

@Controller('/v1')
export class RuntimeController {
  constructor(private readonly config: AppConfig) {}

  @Get('appcast.xml')
  @Header('Content-Type', 'application/rss+xml; charset=utf-8')
  async appcast(): Promise<string> { return readFile(join(process.cwd(), 'manifests', 'appcast.xml'), 'utf8').catch(() => '<rss version="2.0"><channel><title>Portside</title><link>https://example.invalid</link><description>Portside updates</description></channel></rss>'); }

  @Get('runtime/manifest')
  async manifest(): Promise<unknown> {
    const path = join(process.cwd(), 'manifests', 'runtime-manifest.json');
    try { return JSON.parse(await readFile(path, 'utf8')); } catch { throw new ServiceUnavailableException('production runtime manifest is not published'); }
  }
}
