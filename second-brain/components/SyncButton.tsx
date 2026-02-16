"use client";

import { useState } from "react";
import { RefreshCcw } from "lucide-react";

export function SyncButton() {
  const [status, setStatus] = useState<"idle" | "syncing" | "success" | "error">("idle");
  const [message, setMessage] = useState<string>("");

  async function handleSync() {
    setStatus("syncing");
    setMessage("");
    try {
      const res = await fetch("/api/conversations/sync", { method: "POST" });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.message || "Sync failed");
      }
      const data = await res.json();
      setStatus("success");
      setMessage(`Synced ${data.count ?? 0} sessions.`);
      setTimeout(() => setStatus("idle"), 4000);
    } catch (error) {
      setStatus("error");
      setMessage((error as Error).message);
    }
  }

  const labelMap = {
    idle: "Sync Conversations",
    syncing: "Syncing…",
    success: "Synced",
    error: "Retry Sync",
  } as const;

  return (
    <div className="flex flex-col items-start gap-1">
      <button
        onClick={handleSync}
        disabled={status === "syncing"}
        className="flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-60"
      >
        <RefreshCcw className={`h-4 w-4 ${status === "syncing" ? "animate-spin" : ""}`} />
        {labelMap[status]}
      </button>
      {message && (
        <p className={`text-xs ${status === "error" ? "text-rose-300" : "text-emerald-300"}`}>
          {message}
        </p>
      )}
    </div>
  );
}
