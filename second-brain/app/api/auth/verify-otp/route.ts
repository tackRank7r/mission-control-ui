import { NextResponse } from "next/server";

import { prisma } from "@/lib/prisma";
import { createSession } from "@/lib/auth";
import { hashOtpCode } from "@/lib/otp";
import { SESSION_COOKIE_NAME } from "@/lib/config";

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const rawEmail = typeof body.email === "string" ? body.email : "";
    const code = typeof body.code === "string" ? body.code.trim() : "";
    const email = normalizeEmail(rawEmail);

    if (!email || !code) {
      return NextResponse.json({ error: "Email and code are required." }, { status: 400 });
    }

    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      return NextResponse.json({ error: "Invalid code." }, { status: 400 });
    }

    const codeHash = hashOtpCode(email, code);

    const otp = await prisma.otpRequest.findFirst({
      where: {
        userId: user.id,
        codeHash,
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: "desc" },
    });

    if (!otp) {
      return NextResponse.json({ error: "Invalid or expired code." }, { status: 400 });
    }

    await prisma.otpRequest.update({
      where: { id: otp.id },
      data: { consumedAt: new Date() },
    });

    const { token, expiresAt } = await createSession(user.id);

    const response = NextResponse.json({ ok: true });
    response.cookies.set(SESSION_COOKIE_NAME, token, {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      expires: expiresAt,
      path: "/",
    });

    return response;
  } catch (error) {
    console.error("verify-otp failed", error);
    return NextResponse.json({ error: "Unable to verify code right now." }, { status: 500 });
  }
}
