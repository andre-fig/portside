import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Request } from 'express';
import { AppConfig } from './config.js';
import { safeEqualText } from './security.js';

@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly config: AppConfig) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const value = request.header('authorization') ?? '';
    const [scheme, token] = value.split(' ');
    if (scheme !== 'Bearer' || !token || !safeEqualText(this.config.adminToken(), token)) throw new UnauthorizedException();
    return true;
  }
}
