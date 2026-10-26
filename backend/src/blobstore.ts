import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { decryptBlob, encryptBlob, randomToken, sha256Hex } from './crypto.ts';

/** Private object storage. Callers never see paths; keys are opaque. */
export interface BlobStore {
  put(key: string, data: Buffer): Promise<void>;
  get(key: string): Promise<Buffer>;
  /** Returns whether anything was removed. */
  delete(key: string): Promise<boolean>;
}

/**
 * Local-disk store with AES-256-GCM at rest. The file name is a hash of the
 * key (no path traversal), files are written 0600 via an atomic rename, and the
 * key is bound into the ciphertext so a file cannot be swapped between records.
 * Production should use object storage with a managed KMS; this is the same
 * interface.
 */
export class FileBlobStore implements BlobStore {
  private readonly dir: string;
  private readonly key: Buffer;

  constructor(dir: string, key: Buffer) {
    this.dir = dir;
    this.key = key;
  }

  private pathFor(key: string): { dir: string; file: string } {
    const h = sha256Hex(key);
    const dir = join(this.dir, h.slice(0, 2));
    return { dir, file: join(dir, h) };
  }

  async put(key: string, data: Buffer): Promise<void> {
    const { dir, file } = this.pathFor(key);
    await mkdir(dir, { recursive: true, mode: 0o700 });
    const tmp = `${file}.${randomToken(6)}.tmp`;
    await writeFile(tmp, encryptBlob(this.key, data, key), { mode: 0o600 });
    await rename(tmp, file);
  }

  async get(key: string): Promise<Buffer> {
    return decryptBlob(this.key, await readFile(this.pathFor(key).file), key);
  }

  async delete(key: string): Promise<boolean> {
    try {
      await rm(this.pathFor(key).file);
      return true;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return false;
      throw err;
    }
  }
}
