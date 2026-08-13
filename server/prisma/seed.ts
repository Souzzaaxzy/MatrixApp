import { PrismaClient } from '../src/generated/index.js';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding MATRIX database…');

  // Wipe in dependency order so re-seeding is idempotent.
  await prisma.comment.deleteMany();
  await prisma.like.deleteMany();
  await prisma.post.deleteMany();
  await prisma.session.deleteMany();
  await prisma.user.deleteMany();

  const password = await bcrypt.hash('password123', 12);

  const users = await prisma.$transaction([
    prisma.user.create({
      data: {
        name: 'Leonardo Souza',
        username: 'leonardo',
        email: 'leonardo@matrix.app',
        passwordHash: password,
        bio: 'Fundador do MATRIX 💤 — construindo o futuro cronológico.',
        avatarUrl: 'https://i.pravatar.cc/300?img=12',
      },
    }),
    prisma.user.create({
      data: {
        name: 'Maria Silva',
        username: 'maria',
        email: 'maria@matrix.app',
        passwordHash: password,
        bio: 'Designer | Futurista | 💜 cyberpunk',
        avatarUrl: 'https://i.pravatar.cc/300?img=45',
      },
    }),
    prisma.user.create({
      data: {
        name: 'João Pedro',
        username: 'joao',
        email: 'joao@matrix.app',
        passwordHash: password,
        bio: 'Dev backend. Coffee-driven.',
        avatarUrl: 'https://i.pravatar.cc/300?img=33',
      },
    }),
    prisma.user.create({
      data: {
        name: 'Akame Test',
        username: 'akame',
        email: 'akame@matrix.app',
        passwordHash: password,
        bio: 'Conta de teste para o assistente Akame.',
        avatarUrl: 'https://i.pravatar.cc/300?img=60',
      },
    }),
  ]);

  const [leonardo, maria, joao, akame] = users;

  const posts = await prisma.$transaction([
    prisma.post.create({
      data: {
        userId: leonardo.id,
        text: 'Bem-vindos ao MATRIX 💤 — a rede social do futuro cronológico. Tudo aqui é persistente agora!',
        imageUrl: null,
      },
    }),
    prisma.post.create({
      data: {
        userId: maria.id,
        text: 'Adorando a estética cyberpunk dessa nova versão. 🔮✨ #matrix',
        imageUrl: null,
      },
    }),
    prisma.post.create({
      data: {
        userId: joao.id,
        text: 'Backend em Fastify + Prisma + PostgreSQL rodando liso. Migrações aplicadas, seed no ar. 🚀',
        imageUrl: null,
      },
    }),
    prisma.post.create({
      data: {
        userId: akame.id,
        text: 'Olá! Sou o Akame, assistente de testes. Pode me chamar quando quiser conversar. 👾',
        imageUrl: null,
      },
    }),
  ]);

  // Likes: spread some engagement across posts.
  await prisma.$transaction([
    prisma.like.create({ data: { userId: maria.id, postId: posts[0].id } }),
    prisma.like.create({ data: { userId: joao.id, postId: posts[0].id } }),
    prisma.like.create({ data: { userId: akame.id, postId: posts[0].id } }),
    prisma.like.create({ data: { userId: leonardo.id, postId: posts[1].id } }),
    prisma.like.create({ data: { userId: joao.id, postId: posts[1].id } }),
    prisma.like.create({ data: { userId: leonardo.id, postId: posts[2].id } }),
  ]);

  // Comments: a small thread under the welcome post.
  await prisma.$transaction([
    prisma.comment.create({
      data: { userId: maria.id, postId: posts[0].id, text: 'Ficou incrível, Leo! Parabéns. 🎉' },
    }),
    prisma.comment.create({
      data: { userId: joao.id, postId: posts[0].id, text: 'Persistência finally. Bom trabalho no backend.' },
    }),
    prisma.comment.create({
      data: { userId: akame.id, postId: posts[0].id, text: 'Estou pronto para ajudar a comunidade. 👾' },
    }),
    prisma.comment.create({
      data: { userId: leonardo.id, postId: posts[1].id, text: 'Ficou perfeito, Maria!' },
    }),
  ]);

  console.log(`✅ Seeded ${users.length} users, ${posts.length} posts, 6 likes, 4 comments.`);
  console.log('   Login with any of: leonardo / maria / joao / akame  — password: password123');
}

main()
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
