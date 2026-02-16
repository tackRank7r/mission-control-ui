import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { randomBytes } from "crypto";

import { prisma } from "./prisma";
import { SESSION_COOKIE_NAME, SESSION_TTL_DAYS } from "./config";

const MS_IN_DAY = 24 * 60 * 60 * 1000;

function getExpiryDate() {
  return new Date(Date.now() + SESSION_TTL_DAYS * MS_IN_DAY);
}

export async function createSession(userId: string) {
  const token = randomBytes(32).toString("hex");
  const expiresAt = getExpiryDate();
  await prisma.session.create({ data: { userId, token, expiresAt } });
  return { token, expiresAt };
}

export async function deleteSessionByToken(token: string) {
  await prisma.session.deleteMany({ where: { token } });
}

export async function getSessionUser() {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!token) return null;

  const session = await prisma.session.findUnique({ where: { token }, include: { user: true } });
  if (!session) {
    return null;
  }
  if (session.expiresAt.getTime() < Date.now()) {
    await prisma.session.delete({ where: { id: session.id } }).catch(() => undefined);
    return null;
  }
  return session.user;
}

export async function requireUser() {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  return user;
}
