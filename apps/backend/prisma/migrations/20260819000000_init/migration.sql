-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "LicenseStatus" AS ENUM ('active', 'suspended', 'revoked', 'expired');

-- CreateEnum
CREATE TYPE "ActivationStatus" AS ENUM ('active', 'deactivated', 'revoked');

-- CreateEnum
CREATE TYPE "ArtifactStatus" AS ENUM ('discovered', 'downloading', 'quarantined', 'verified', 'testing', 'approved', 'production', 'rejected', 'deprecated');

-- CreateEnum
CREATE TYPE "Channel" AS ENUM ('staging', 'production');

-- CreateEnum
CREATE TYPE "SyncStatus" AS ENUM ('running', 'succeeded', 'failed', 'skipped');

-- CreateEnum
CREATE TYPE "AuditAction" AS ENUM ('activation', 'deactivation', 'revocation', 'artifact_sync', 'artifact_promote', 'artifact_rollback', 'manifest_publish', 'admin_login');

-- CreateTable
CREATE TABLE "Customer" (
    "id" TEXT NOT NULL,
    "email" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Customer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Purchase" (
    "id" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "providerRef" TEXT NOT NULL,
    "amountCents" INTEGER,
    "currency" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Purchase_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "License" (
    "id" TEXT NOT NULL,
    "customerId" TEXT,
    "purchaseId" TEXT,
    "keyPrefix" TEXT NOT NULL,
    "keyHmac" TEXT NOT NULL,
    "plan" TEXT NOT NULL,
    "status" "LicenseStatus" NOT NULL DEFAULT 'active',
    "offlineGraceDays" INTEGER NOT NULL DEFAULT 14,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "License_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Device" (
    "id" TEXT NOT NULL,
    "publicKey" TEXT NOT NULL,
    "publicKeyHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3),

    CONSTRAINT "Device_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Activation" (
    "id" TEXT NOT NULL,
    "licenseId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "status" "ActivationStatus" NOT NULL DEFAULT 'active',
    "activatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deactivatedAt" TIMESTAMP(3),
    "lastValidatedAt" TIMESTAMP(3),

    CONSTRAINT "Activation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ActivationChallenge" (
    "id" TEXT NOT NULL,
    "licenseId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "nonceHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ActivationChallenge_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Artifact" (
    "id" TEXT NOT NULL,
    "component" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "channel" "Channel" NOT NULL,
    "sourceURL" TEXT NOT NULL,
    "sourceRepository" TEXT,
    "sourceCommitOrTag" TEXT,
    "license" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "size" BIGINT NOT NULL,
    "sha256" TEXT NOT NULL,
    "signature" TEXT,
    "storageKey" TEXT NOT NULL,
    "status" "ArtifactStatus" NOT NULL DEFAULT 'discovered',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "verifiedAt" TIMESTAMP(3),
    "promotedAt" TIMESTAMP(3),

    CONSTRAINT "Artifact_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ArtifactVersion" (
    "id" TEXT NOT NULL,
    "artifactId" TEXT NOT NULL,
    "metadata" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ArtifactVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UpdateChannel" (
    "id" TEXT NOT NULL,
    "channel" "Channel" NOT NULL,
    "appcastURL" TEXT NOT NULL,
    "manifestURL" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UpdateChannel_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RuntimeManifest" (
    "id" TEXT NOT NULL,
    "channel" "Channel" NOT NULL,
    "manifestVersion" TEXT NOT NULL,
    "minimumPortsideVersion" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "signature" TEXT NOT NULL,
    "signatureKeyId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RuntimeManifest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UpstreamSource" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "repository" TEXT NOT NULL,
    "allowlisted" BOOLEAN NOT NULL DEFAULT true,
    "license" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UpstreamSource_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncExecution" (
    "id" TEXT NOT NULL,
    "sourceId" TEXT,
    "status" "SyncStatus" NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "discovered" INTEGER NOT NULL DEFAULT 0,
    "verified" INTEGER NOT NULL DEFAULT 0,
    "errorCode" TEXT,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finishedAt" TIMESTAMP(3),

    CONSTRAINT "SyncExecution_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" TEXT NOT NULL,
    "action" "AuditAction" NOT NULL,
    "actor" TEXT NOT NULL,
    "subjectType" TEXT NOT NULL,
    "subjectId" TEXT,
    "metadata" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Revocation" (
    "id" TEXT NOT NULL,
    "licenseId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "actor" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Revocation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Customer_email_idx" ON "Customer"("email");

-- CreateIndex
CREATE INDEX "Purchase_customerId_createdAt_idx" ON "Purchase"("customerId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Purchase_provider_providerRef_key" ON "Purchase"("provider", "providerRef");

-- CreateIndex
CREATE UNIQUE INDEX "License_keyHmac_key" ON "License"("keyHmac");

-- CreateIndex
CREATE INDEX "License_status_createdAt_idx" ON "License"("status", "createdAt");

-- CreateIndex
CREATE INDEX "License_keyPrefix_idx" ON "License"("keyPrefix");

-- CreateIndex
CREATE UNIQUE INDEX "Device_publicKeyHash_key" ON "Device"("publicKeyHash");

-- CreateIndex
CREATE INDEX "Device_lastSeenAt_idx" ON "Device"("lastSeenAt");

-- CreateIndex
CREATE INDEX "Activation_licenseId_status_idx" ON "Activation"("licenseId", "status");

-- CreateIndex
CREATE INDEX "Activation_deviceId_status_idx" ON "Activation"("deviceId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "Activation_licenseId_deviceId_key" ON "Activation"("licenseId", "deviceId");

-- A license may have at most one active device while retaining deactivation history.
CREATE UNIQUE INDEX "Activation_one_active_license_idx" ON "Activation"("licenseId") WHERE "status" = 'active';

-- CreateIndex
CREATE UNIQUE INDEX "ActivationChallenge_nonceHash_key" ON "ActivationChallenge"("nonceHash");

-- CreateIndex
CREATE INDEX "ActivationChallenge_licenseId_deviceId_expiresAt_idx" ON "ActivationChallenge"("licenseId", "deviceId", "expiresAt");

-- CreateIndex
CREATE INDEX "Artifact_component_channel_status_idx" ON "Artifact"("component", "channel", "status");

-- CreateIndex
CREATE INDEX "Artifact_sha256_idx" ON "Artifact"("sha256");

-- CreateIndex
CREATE UNIQUE INDEX "Artifact_component_version_channel_key" ON "Artifact"("component", "version", "channel");

-- CreateIndex
CREATE INDEX "ArtifactVersion_artifactId_createdAt_idx" ON "ArtifactVersion"("artifactId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "UpdateChannel_channel_key" ON "UpdateChannel"("channel");

-- CreateIndex
CREATE INDEX "RuntimeManifest_channel_status_publishedAt_idx" ON "RuntimeManifest"("channel", "status", "publishedAt");

-- CreateIndex
CREATE UNIQUE INDEX "RuntimeManifest_channel_manifestVersion_key" ON "RuntimeManifest"("channel", "manifestVersion");

-- CreateIndex
CREATE UNIQUE INDEX "UpstreamSource_name_key" ON "UpstreamSource"("name");

-- CreateIndex
CREATE UNIQUE INDEX "SyncExecution_idempotencyKey_key" ON "SyncExecution"("idempotencyKey");

-- CreateIndex
CREATE INDEX "SyncExecution_sourceId_startedAt_idx" ON "SyncExecution"("sourceId", "startedAt");

-- CreateIndex
CREATE INDEX "AuditEvent_action_createdAt_idx" ON "AuditEvent"("action", "createdAt");

-- CreateIndex
CREATE INDEX "AuditEvent_subjectType_subjectId_createdAt_idx" ON "AuditEvent"("subjectType", "subjectId", "createdAt");

-- CreateIndex
CREATE INDEX "Revocation_licenseId_createdAt_idx" ON "Revocation"("licenseId", "createdAt");

-- AddForeignKey
ALTER TABLE "Purchase" ADD CONSTRAINT "Purchase_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "License" ADD CONSTRAINT "License_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "License" ADD CONSTRAINT "License_purchaseId_fkey" FOREIGN KEY ("purchaseId") REFERENCES "Purchase"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Activation" ADD CONSTRAINT "Activation_licenseId_fkey" FOREIGN KEY ("licenseId") REFERENCES "License"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Activation" ADD CONSTRAINT "Activation_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ActivationChallenge" ADD CONSTRAINT "ActivationChallenge_licenseId_fkey" FOREIGN KEY ("licenseId") REFERENCES "License"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ActivationChallenge" ADD CONSTRAINT "ActivationChallenge_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ArtifactVersion" ADD CONSTRAINT "ArtifactVersion_artifactId_fkey" FOREIGN KEY ("artifactId") REFERENCES "Artifact"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncExecution" ADD CONSTRAINT "SyncExecution_sourceId_fkey" FOREIGN KEY ("sourceId") REFERENCES "UpstreamSource"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Revocation" ADD CONSTRAINT "Revocation_licenseId_fkey" FOREIGN KEY ("licenseId") REFERENCES "License"("id") ON DELETE CASCADE ON UPDATE CASCADE;

