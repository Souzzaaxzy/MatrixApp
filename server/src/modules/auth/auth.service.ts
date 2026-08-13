import { prisma } from '../../config/prisma.js';
import { ApiError } from '../../utils/errors.js';
import { normalizeEmail, normalizeUsername } from '../../utils/normalize.js';
import {
  createSession,
  hashPassword,
  rotateRefreshToken,
  revokeSession,
  signAccessToken,
  verifyPassword,
} from '../../utils/auth.js';
import type { RegisterInput, LoginInput } from './auth.schema.js';

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  user: ReturnType<typeof serializeUser>;
}

function serializeUser(user: {
  id: string;
  name: string;
  username: string;
  email: string;
  avatarUrl: string | null;
  bio: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: user.id,
    name: user.name,
    username: user.username,
    email: user.email,
    avatarUrl: user.avatarUrl,
    bio: user.bio,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}

export async function register(input: RegisterInput): Promise<AuthResult> {
  const email = normalizeEmail(input.email);
  const username = normalizeUsername(input.username);

  const existing = await prisma.user.findFirst({
    where: { OR: [{ email }, { username }] },
    select: { id: true },
  });
  if (existing) {
    // Generic message — do not reveal which field collided.
    throw ApiError.conflict('Usuário ou e-mail já cadastrado.');
  }

  const passwordHash = await hashPassword(input.password);
  const user = await prisma.user.create({
    data: {
      name: input.name.trim(),
      username,
      email,
      passwordHash,
      bio: '',
    },
  });

  const { refreshToken } = await createSession(user.id);
  const accessToken = signAccessToken(user);

  return {
    accessToken,
    refreshToken,
    user: serializeUser(user),
  };
}

export async function login(input: LoginInput): Promise<AuthResult> {
  const identifier = input.identifier.trim();
  const isEmail = identifier.includes('@');
  const user = isEmail
    ? await prisma.user.findUnique({ where: { email: normalizeEmail(identifier) } })
    : await prisma.user.findUnique({ where: { username: normalizeUsername(identifier) } });

  // Always perform a hash compare to keep timing roughly constant even when
  // the user does not exist, mitigating user enumeration via timing.
  const dummyHash = '$2a$12$abcdefghijklmnopqrstuv';
  const ok = user ? await verifyPassword(input.password, user.passwordHash) : await verifyPassword(input.password, dummyHash);

  if (!user || !ok) {
    // Generic error — never reveal whether the account exists.
    throw ApiError.unauthorized('Credenciais inválidas.');
  }

  const { refreshToken } = await createSession(user.id);
  const accessToken = signAccessToken(user);

  return {
    accessToken,
    refreshToken,
    user: serializeUser(user),
  };
}

export async function refresh(refreshToken: string): Promise<AuthResult> {
  const rotated = await rotateRefreshToken(refreshToken);
  if (!rotated) {
    throw ApiError.unauthorized('Sessão expirada.');
  }
  const user = await prisma.user.findUnique({ where: { id: rotated.userId } });
  if (!user) throw ApiError.unauthorized();

  return {
    accessToken: signAccessToken(user),
    refreshToken: rotated.refreshToken,
    user: serializeUser(user),
  };
}

export async function logout(refreshToken: string): Promise<void> {
  await revokeSession(refreshToken);
}

export async function getCurrentUser(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw ApiError.unauthorized();
  return serializeUser(user);
}
