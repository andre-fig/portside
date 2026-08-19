import { Channel } from "@prisma/client";

export type SyncRequest = {
  component: string;
  version: string;
  channel: Channel;
  sourceURL: string;
  sourceRepository?: string;
  sourceCommitOrTag?: string;
  license: string;
  fileName: string;
  expectedSHA256: string;
  signature?: string;
  signatureKeyId?: string;
  idempotencyKey: string;
};
