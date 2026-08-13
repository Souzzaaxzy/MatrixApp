import { prisma } from '../../config/prisma.js';
import { ApiError } from '../../utils/errors.js';

// Toggle like: if the user has already liked the post, remove the like;
// otherwise create it. Returns the resulting state + updated count.
export async function toggleLike(userId: string, postId: string): Promise<{ liked: boolean; likeCount: number }> {
  const post = await prisma.post.findUnique({ where: { id: postId }, select: { id: true } });
  if (!post) throw ApiError.notFound('Publicação não encontrada.');

  const existing = await prisma.like.findUnique({
    where: { userId_postId: { userId, postId } },
    select: { userId: true },
  });

  if (existing) {
    await prisma.like.delete({ where: { userId_postId: { userId, postId } } });
  } else {
    await prisma.like.create({ data: { userId, postId } });
  }

  const likeCount = await prisma.like.count({ where: { postId } });
  return { liked: !existing, likeCount };
}
