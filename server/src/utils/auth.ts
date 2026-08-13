import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import ms from 'ms';
import { env } from '../config/env.js';
import { prisma } from '../config/prisma.js';
import type { Session, User } from '../generated/index.js';

const BCRYPT_ROUNDS = 12;

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, BCRYPT_ROUNDS);
}

export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}

export interface AccessTokenPayload {
  sub: string;
  username: string;
}

// Convert human-readable expiry strings ("15m", "30d") to seconds so the
// jsonwebtoken typings accept them without branded-string coupling.
function toSeconds(value: string): number {
  return Math.floor((ms as unknown as (v: string) => number)(value) / 1000);
}

export function signAccessToken(user: Pick<User, 'id' | 'username'>): string {
  return jwt.sign({ sub: user.id, username: user.username }, env.jwt.secret, {
    expiresIn: toSeconds(env.jwt.accessExpiresIn),
  });
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  return jwt.verify(token, env.jwt.secret) as AccessTokenPayload;
}

// Refresh tokens are opaque random strings; only their hash is stored.
import { createHash, randomBytes } from 'node:crypto';

export function generateRefreshToken(): string {
  return randomBytes(48).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export async function createSession(userId: string): Promise<{ refreshToken: string; session: Session }> {
  const refreshToken = generateRefreshToken();
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30d
  const session = await prisma.session.create({
    data: {
      userId,
      refreshTokenHash: hashToken(refreshToken),
      expiresAt,
    },
  });
  return { refreshToken, session };
}

export async function rotateRefreshToken(oldToken: string): Promise<
  { userId: string; refreshToken: string } | null
> {
  const session = await prisma.session.findUnique({
    where: { refreshTokenHash: hashToken(oldToken) },
  });
  if (!session) return null;
  if (session.revokedAt || session.expiresAt < new Date()) return null;

  await prisma.session.update({
    where: { id: session.id },
    data: { revokedAt: new Date() },
  });

  const next = await createSession(session.userId);
  return { userId: session.userId, refreshToken: next.refreshToken };
}

export async function revokeSession(token: string): Promise<void> {
  try {
    await prisma.session.update({
      where: { refreshTokenHash: hashToken(token) },
      data: { revokedAt: new Date() },
    });
  } catch {
    // Token may already be revoked or unknown — silently ignore.
  }
}

export async function revokeAllUserSessions(userId: string): Promise<void> {
  await prisma.session.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}
