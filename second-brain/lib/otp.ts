import { randomInt, createHash } from "crypto";

const OTP_LENGTH = parseInt(process.env.OTP_LENGTH || "6", 10);
const OTP_HASH_SECRET = process.env.OTP_HASH_SECRET || "mission-control-secret";

export function generateOtpCode(length: number = OTP_LENGTH) {
  let code = "";
  for (let i = 0; i < length; i += 1) {
    code += randomInt(0, 10).toString();
  }
  return code;
}

export function hashOtpCode(email: string, code: string) {
  const normalizedEmail = email.trim().toLowerCase();
  return createHash("sha256").update(`${normalizedEmail}:${code}:${OTP_HASH_SECRET}`).digest("hex");
}
