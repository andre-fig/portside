import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from "@nestjs/common";
import { LicenseStatus, ActivationStatus } from "@prisma/client";
import { createPublicKey, createVerify, verify } from "node:crypto";
import { AppConfig } from "../../core/app-config.js";
import { PrismaService } from "../../database/prisma.service.js";
import {
  hmacHex,
  randomToken,
  sha256Hex,
  signLicenseToken,
  signedTokenInput,
} from "../../common/security/security.js";

export type LicenseTokenPayload = {
  licenseId: string;
  deviceId: string;
  plan: string;
  issuedAt: number;
  expiresAt: number;
  offlineUntil: number;
  keyId: string;
};

function keyParts(value: string): { prefix: string; hmacInput: string } {
  const normalized = value.trim().toUpperCase();
  if (!/^PORT-[A-Z0-9]{8}(?:-[A-Z0-9]{8}){3}$/.test(normalized))
    throw new UnauthorizedException("invalid license key");
  return { prefix: normalized.slice(0, 13), hmacInput: normalized };
}

@Injectable()
export class LicenseService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfig,
  ) {}

  async activate(input: {
    licenseKey: string;
    publicKey: string;
  }): Promise<{ token: string; deviceId: string; offlineUntil: string }> {
    const parts = keyParts(input.licenseKey);
    // Validate the device key before touching the database. Activation must
    // only ever bind a real P-256 public key that the client can later prove
    // possession of during challenge validation.
    this.spkiForRawP256(input.publicKey);
    const keyHmac = hmacHex(this.config.licenseHMACSecret(), parts.hmacInput);
    const keyHash = sha256Hex(input.publicKey);
    const result = await this.prisma.$transaction(async (tx) => {
      const license = await tx.license.findUnique({ where: { keyHmac } });
      if (license?.status !== LicenseStatus.active)
        throw new UnauthorizedException("license is not active");
      const device = await tx.device.upsert({
        where: { publicKeyHash: keyHash },
        update: { publicKey: input.publicKey, lastSeenAt: new Date() },
        create: { publicKey: input.publicKey, publicKeyHash: keyHash },
      });
      const current = await tx.activation.findFirst({
        where: { licenseId: license.id, status: ActivationStatus.active },
      });
      if (current && current.deviceId !== device.id)
        throw new ConflictException(
          "license is already active on another device",
        );
      const activation = await tx.activation.upsert({
        where: {
          licenseId_deviceId: { licenseId: license.id, deviceId: device.id },
        },
        update: {
          status: ActivationStatus.active,
          deactivatedAt: null,
          lastValidatedAt: new Date(),
        },
        create: { licenseId: license.id, deviceId: device.id },
      });
      return { license, activation };
    });
    const { license, activation } = result;
    const now = Math.floor(Date.now() / 1000);
    const offlineUntil = now + license.offlineGraceDays * 86400;
    const payload: LicenseTokenPayload = {
      licenseId: license.id,
      deviceId: activation.deviceId,
      plan: license.plan,
      issuedAt: now,
      expiresAt: offlineUntil,
      offlineUntil,
      keyId: this.config.licenseKeyId(),
    };
    return {
      token: signLicenseToken(payload, this.config.licensePrivateKey()),
      deviceId: activation.deviceId,
      offlineUntil: new Date(offlineUntil * 1000).toISOString(),
    };
  }

  async challenge(input: {
    licenseId: string;
    deviceId: string;
  }): Promise<{ challenge: string; expiresAt: string }> {
    const license = await this.prisma.license.findUnique({
      where: { id: input.licenseId },
    });
    if (license?.status !== LicenseStatus.active)
      throw new UnauthorizedException("license is not active");
    const activation = await this.prisma.activation.findUnique({
      where: {
        licenseId_deviceId: { licenseId: license.id, deviceId: input.deviceId },
      },
    });
    if (activation?.status !== ActivationStatus.active)
      throw new UnauthorizedException("device is not active for this license");
    const challenge = randomToken(32);
    const expiresAt = new Date(Date.now() + 120_000);
    await this.prisma.activationChallenge.create({
      data: {
        licenseId: license.id,
        deviceId: input.deviceId,
        nonceHash: sha256Hex(challenge),
        expiresAt,
      },
    });
    return { challenge, expiresAt: expiresAt.toISOString() };
  }

  async validate(input: {
    token: string;
    challenge: string;
    signature: string;
  }): Promise<{ valid: true; token: string; offlineUntil: string }> {
    const parts = input.token.split(".");
    if (parts.length !== 3) throw new UnauthorizedException("invalid token");
    let payload: LicenseTokenPayload;
    try {
      payload = JSON.parse(
        Buffer.from(parts[1], "base64url").toString(),
      ) as LicenseTokenPayload;
    } catch {
      throw new UnauthorizedException("invalid token payload");
    }
    if (
      !payload.licenseId ||
      !payload.deviceId ||
      !payload.plan ||
      payload.keyId !== this.config.licenseKeyId()
    )
      throw new UnauthorizedException("invalid token payload");
    if (
      !verify(
        null,
        signedTokenInput(input.token),
        this.config.licensePublicKey(),
        Buffer.from(parts[2], "base64url"),
      )
    )
      throw new UnauthorizedException("invalid token signature");
    const verifier = createVerify("SHA256");
    verifier.update(Buffer.from(input.challenge));
    const publicKey = createPublicKey({
      key: this.spkiForRawP256(await this.devicePublicKey(payload.deviceId)),
      format: "der",
      type: "spki",
    });
    if (
      !verifier.verify(
        { key: publicKey, dsaEncoding: "der" },
        Buffer.from(input.signature, "base64url"),
      )
    )
      throw new UnauthorizedException("invalid challenge signature");
    const challenge = await this.prisma.activationChallenge.findFirst({
      where: {
        nonceHash: sha256Hex(input.challenge),
        licenseId: payload.licenseId,
        deviceId: payload.deviceId,
        usedAt: null,
      },
    });
    if (!challenge || challenge.expiresAt.getTime() <= Date.now())
      throw new UnauthorizedException("challenge expired or already used");
    const consumed = await this.prisma.activationChallenge.updateMany({
      where: { id: challenge.id, usedAt: null },
      data: { usedAt: new Date() },
    });
    if (consumed.count !== 1)
      throw new UnauthorizedException("challenge expired or already used");
    const license = await this.prisma.license.findUnique({
      where: { id: payload.licenseId },
    });
    if (license?.status !== LicenseStatus.active)
      throw new UnauthorizedException("license token is not valid");
    await this.prisma.activation.update({
      where: {
        licenseId_deviceId: {
          licenseId: license.id,
          deviceId: payload.deviceId,
        },
      },
      data: { lastValidatedAt: new Date() },
    });
    const now = Math.floor(Date.now() / 1000);
    const offlineUntil = now + license.offlineGraceDays * 86400;
    const refreshed: LicenseTokenPayload = {
      licenseId: license.id,
      deviceId: payload.deviceId,
      plan: license.plan,
      issuedAt: now,
      expiresAt: offlineUntil,
      offlineUntil,
      keyId: this.config.licenseKeyId(),
    };
    return {
      valid: true,
      token: signLicenseToken(refreshed, this.config.licensePrivateKey()),
      offlineUntil: new Date(offlineUntil * 1000).toISOString(),
    };
  }

  async deactivate(input: {
    licenseKey: string;
    deviceId: string;
  }): Promise<{ deactivated: true }> {
    const { hmacInput } = keyParts(input.licenseKey);
    const license = await this.prisma.license.findUnique({
      where: { keyHmac: hmacHex(this.config.licenseHMACSecret(), hmacInput) },
    });
    if (!license) throw new NotFoundException("license not found");
    await this.prisma.activation.updateMany({
      where: {
        licenseId: license.id,
        deviceId: input.deviceId,
        status: ActivationStatus.active,
      },
      data: { status: ActivationStatus.deactivated, deactivatedAt: new Date() },
    });
    return { deactivated: true };
  }

  private async devicePublicKey(deviceId: string): Promise<string> {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: { publicKey: true },
    });
    if (!device) throw new UnauthorizedException("device not found");
    return device.publicKey;
  }

  private spkiForRawP256(publicKeyBase64: string): Buffer {
    const raw = Buffer.from(publicKeyBase64, "base64");
    if (raw.length !== 65 || raw[0] !== 0x04)
      throw new UnauthorizedException("invalid device public key");
    const spki = Buffer.concat([
      Buffer.from(
        "3059301306072a8648ce3d020106082a8648ce3d030107034200",
        "hex",
      ),
      raw,
    ]);
    try {
      createPublicKey({ key: spki, format: "der", type: "spki" });
    } catch {
      throw new UnauthorizedException("invalid device public key");
    }
    return spki;
  }
}
