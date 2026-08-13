import type { FastifyInstance } from 'fastify';
import { buildServer } from '../src/app.js';
import { prisma } from '../src/config/prisma.js';
import bcrypt from 'bcryptjs';

export let app: FastifyInstance;

export async function buildTestServer() {
  app = await buildServer();
  await app.ready();
  return app;
}

export async function closeTestServer() {
  if (app) await app.close();
}

export interface SeedUser {
  id: string;
  username: string;
  email: string;
  password: string;
  accessToken: string;
  refreshToken: string;
}

export async function createUser(overrides: Partial<{
  name: string;
  username: string;
  email: string;
  password: string;
  bio: string;
}> = {}): Promise<{ id: string; username: string; email: string; passwordHash: string }> {
  const username = overrides.username ?? `user_${Math.random().toString(36).slice(2, 8)}`;
  const password = overrides.password ?? 'Password123';
  const passwordHash = await bcrypt.hash(password, 4); // low cost for test speed
  const user = await prisma.user.create({
    data: {
      name: overrides.name ?? 'Test User',
      username,
      email: overrides.email ?? `${username}@matrix.app`,
      passwordHash,
      bio: overrides.bio ?? '',
    },
  });
  return user;
}

export async function login(server: FastifyInstance, username: string, password: string) {
  const res = await server.inject({
    method: 'POST',
    url: '/auth/login',
    payload: { identifier: username, password },
  });
  return JSON.parse(res.payload);
}

export async function createAndLoginUser(
  server: FastifyInstance,
  overrides: Parameters<typeof createUser>[0] = {},
): Promise<SeedUser> {
  const password = overrides.password ?? 'Password123';
  const username = overrides.username ?? `user_${Math.random().toString(36).slice(2, 8)}`;
  const email = overrides.email ?? `${username}@matrix.app`;
  const dbUser = await createUser({ ...overrides, username, email, password });
  const auth = await login(server, username, password);
  return {
    id: dbUser.id,
    username,
    email,
    password,
    accessToken: auth.accessToken,
    refreshToken: auth.refreshToken,
  };
}
