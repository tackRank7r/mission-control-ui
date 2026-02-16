import sgMail from "@sendgrid/mail";

const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY;
const FROM_EMAIL = process.env.SENDGRID_FROM_EMAIL;
const FROM_NAME = process.env.SENDGRID_FROM_NAME || "Mission Control";

if (SENDGRID_API_KEY) {
  sgMail.setApiKey(SENDGRID_API_KEY);
}

export async function sendOtpEmail(to: string, code: string, expiresAt: Date) {
  if (!SENDGRID_API_KEY || !FROM_EMAIL) {
    console.warn("SendGrid is not configured. OTP code:", code);
    return;
  }

  await sgMail.send({
    to,
    from: {
      email: FROM_EMAIL,
      name: FROM_NAME,
    },
    subject: "Your Mission Control login code",
    text: `Use the code ${code} to finish signing in. It expires at ${expiresAt.toLocaleTimeString()}.`,
    html: `
      <p>Hello,</p>
      <p>Your Mission Control login code is <strong style="font-size: 20px; letter-spacing: 0.2em;">${code}</strong>.</p>
      <p>This code expires at <strong>${expiresAt.toLocaleTimeString()}</strong>. If you didn\'t request it, you can safely ignore this message.</p>
    `,
  });
}
