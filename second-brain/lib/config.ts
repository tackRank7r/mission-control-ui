const parseNumber = (value: string | undefined, fallback: number) => {
  const parsed = value ? Number(value) : Number.NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

export const SESSION_COOKIE_NAME = process.env.SESSION_COOKIE_NAME || "mission_control_session";
export const SESSION_TTL_DAYS = parseNumber(process.env.SESSION_TTL_DAYS, 14);
export const OTP_EXPIRATION_MINUTES = parseNumber(process.env.OTP_EXPIRATION_MINUTES, 10);

const allowed = process.env.MISSION_CONTROL_ALLOWED_EMAILS
  ? process.env.MISSION_CONTROL_ALLOWED_EMAILS.split(",").map((entry) => entry.trim().toLowerCase()).filter(Boolean)
  : [];

export const ALLOWED_LOGIN_EMAILS = allowed;
