import { NextResponse } from "next/server";

import { prisma } from "@/lib/prisma";
import { ALLOWED_LOGIN_EMAILS, OTP_EXPIRATION_MINUTES } from "@/lib/config";
import { generateOtpCode, hashOtpCode } from "@/lib/otp";
import { sendOtpEmail } from "@/lib/email";

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function isAllowedEmail(email: string) {
  if (!ALLOWED_LOGIN_EMAILS.length) return true;
  return ALLOWED_LOGIN_EMAILS.includes(email);
}

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const rawEmail = typeof body.email === "string" ? body.email : "";
    const email = normalizeEmail(rawEmail);

    if (!email || !isValidEmail(email)) {
      return NextResponse.json({ error: "A valid email is required." }, { status: 400 });
    }

    if (!isAllowedEmail(email)) {
      return NextResponse.json({ error: "This email is not allowed to access Mission Control." }, { status: 403 });
    }

    const user = await prisma.user.upsert({
      where: { email },
      update: {},
      create: {
        email,
        name: email.split("@")[0],
      },
    });

    const existingRecentOtp = await prisma.otpRequest.findFirst({
      where: {
        userId: user.id,
        createdAt: {
          gt: new Date(Date.now() - 60 * 1000),
        },
      },
      orderBy: { createdAt: "desc" },
    });

    if (existingRecentOtp) {
      return NextResponse.json({ ok: true, throttled: true });
    }

    const code = generateOtpCode();
    const codeHash = hashOtpCode(email, code);
    const expiresAt = new Date(Date.now() + OTP_EXPIRATION_MINUTES * 60 * 1000);

    await prisma.otpRequest.create({
      data: {
        userId: user.id,
        codeHash,
        expiresAt,
      },
    });

    await prisma.otpRequest.deleteMany({
      where: {
        userId: user.id,
        AND: [{ expiresAt: { lt: new Date() } }],
      },
    });

    await sendOtpEmail(email, code, expiresAt);

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("request-otp failed", error);
    return NextResponse.json({ error: "Unable to send code right now." }, { status: 500 });
  }
}
