"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function LoginForm() {
  const router = useRouter();
  const [step, setStep] = useState<"email" | "code">("email");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [message, setMessage] = useState<string>("");
  const [error, setError] = useState<string>("");
  const [loading, setLoading] = useState(false);

  const normalizedEmail = email.trim().toLowerCase();

  function handleError(msg: string) {
    setError(msg);
    setMessage("");
    setLoading(false);
  }

  async function requestCode() {
    if (!isValidEmail(normalizedEmail)) {
      handleError("Enter a valid email.");
      return;
    }
    setLoading(true);
    setError("");
    setMessage("Sending code…");
    try {
      const res = await fetch("/api/auth/request-otp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: normalizedEmail }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        handleError(body.error || "Could not send the code.");
        return;
      }
      setMessage("Code sent. Check your inbox and paste it below.");
      setStep("code");
    } catch (err) {
      handleError((err as Error).message);
      return;
    } finally {
      setLoading(false);
    }
  }

  async function verifyCode() {
    if (!code.trim()) {
      handleError("Enter the 6-digit code.");
      return;
    }
    setLoading(true);
    setError("");
    setMessage("Verifying…");
    try {
      const res = await fetch("/api/auth/verify-otp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: normalizedEmail, code }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        handleError(body.error || "Invalid code.");
        return;
      }
      setMessage("Success! Redirecting…");
      router.replace("/");
      router.refresh();
    } catch (err) {
      handleError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="w-full max-w-md rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl">
      <div className="space-y-1 text-center">
        <p className="text-xs uppercase tracking-[0.5em] text-slate-400">Mission Control</p>
        <h1 className="text-2xl font-semibold text-white">Secure sign-in</h1>
        <p className="text-sm text-slate-400">We will send a one-time code to your inbox.</p>
      </div>

      <div className="mt-6 space-y-3">
        <label className="block text-xs font-semibold uppercase tracking-[0.3em] text-slate-400">
          Email address
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            className="mt-2 w-full rounded-2xl border border-white/10 bg-black/30 px-4 py-3 text-sm text-white placeholder:text-slate-500 focus:border-white/30 focus:outline-none"
            placeholder="bill@mission.co"
            disabled={step === "code"}
          />
        </label>
        {step === "code" && (
          <label className="block text-xs font-semibold uppercase tracking-[0.3em] text-slate-400">
            6-digit code
            <input
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/[^0-9]/g, "").slice(0, 6))}
              className="mt-2 w-full rounded-2xl border border-emerald-400/30 bg-black/30 px-4 py-3 text-center text-2xl tracking-[0.3em] text-white placeholder:text-slate-500 focus:border-emerald-400/70 focus:outline-none"
              placeholder="000000"
              autoComplete="one-time-code"
            />
          </label>
        )}
      </div>

      {error && <p className="mt-4 rounded-2xl bg-rose-500/20 px-4 py-2 text-sm text-rose-200">{error}</p>}
      {message && !error && <p className="mt-4 rounded-2xl bg-emerald-500/10 px-4 py-2 text-sm text-emerald-200">{message}</p>}

      <div className="mt-6 space-y-3">
        {step === "email" ? (
          <button
            onClick={requestCode}
            disabled={loading}
            className="w-full rounded-full bg-white/90 px-4 py-3 text-sm font-semibold text-black shadow-lg shadow-white/20 disabled:opacity-60"
          >
            {loading ? "Sending…" : "Send code"}
          </button>
        ) : (
          <>
            <button
              onClick={verifyCode}
              disabled={loading}
              className="w-full rounded-full bg-emerald-400 px-4 py-3 text-sm font-semibold text-black shadow-lg shadow-emerald-500/30 disabled:opacity-60"
            >
              {loading ? "Verifying…" : "Verify & enter"}
            </button>
            <button
              onClick={requestCode}
              type="button"
              disabled={loading}
              className="w-full rounded-full border border-white/20 px-4 py-2 text-sm font-semibold text-white"
            >
              Resend code
            </button>
          </>
        )}
      </div>
    </div>
  );
}
