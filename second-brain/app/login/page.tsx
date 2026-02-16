import { redirect } from "next/navigation";

import { LoginForm } from "@/components/LoginForm";
import { getSessionUser } from "@/lib/auth";

export const metadata = {
  title: "Mission Control — Login",
};

export default async function LoginPage() {
  const user = await getSessionUser();
  if (user) {
    redirect("/");
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#02030a] via-[#050812] to-[#03050b] text-white">
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-12 px-4 py-16 md:flex-row md:justify-between">
        <div className="max-w-xl space-y-4">
          <p className="text-xs uppercase tracking-[0.6em] text-violet-300">Mission Control</p>
          <h1 className="text-4xl font-semibold">One-time code login</h1>
          <p className="text-sm text-slate-300">
            Enter your trusted email address and we&apos;ll send a secure six-digit code. Codes expire quickly, so have
            your inbox open.
          </p>
          <ul className="space-y-2 text-sm text-slate-400">
            <li>• Codes are single-use and expire in minutes.</li>
            <li>• Sign in on any device Bill uses — no password to remember.</li>
            <li>• Hotline sync tools remain protected behind this gate.</li>
          </ul>
        </div>
        <LoginForm />
      </div>
    </div>
  );
}
