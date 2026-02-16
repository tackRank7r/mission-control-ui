"use client";

import { useEffect, useMemo, useState } from "react";
import { Search } from "lucide-react";

export type CommandItem = {
  id: string;
  title: string;
  type: string;
  detail: string;
};

export function CommandBar({ items }: { items: CommandItem[] }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen(true);
      }
      if (event.key === "Escape") {
        setOpen(false);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  const matches = useMemo(() => {
    if (!query) return items.slice(0, 5);
    const lower = query.toLowerCase();
    return items.filter((item) => item.title.toLowerCase().includes(lower) || item.detail.toLowerCase().includes(lower)).slice(0, 5);
  }, [items, query]);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="flex items-center gap-2 rounded-full border border-white/10 bg-black/30 px-4 py-2 text-sm text-slate-200"
      >
        <Search className="h-4 w-4 text-slate-400" />
        Command + K
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 px-4 py-24 backdrop-blur">
          <div className="w-full max-w-xl rounded-2xl border border-white/10 bg-[#05060d] p-4 shadow-2xl">
            <div className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/40 px-3 py-2">
              <Search className="h-4 w-4 text-slate-500" />
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search memories, docs, tasks..."
                className="flex-1 bg-transparent text-sm text-white placeholder:text-slate-500 focus:outline-none"
              />
            </div>
            <div className="mt-3 space-y-2">
              {matches.length === 0 && <p className="text-sm text-slate-500">No matches yet. Try another phrase.</p>}
              {matches.map((item) => (
                <div
                  key={item.id}
                  className="rounded-xl border border-white/5 bg-white/5 px-4 py-3 text-sm"
                >
                  <p className="font-semibold text-white">{item.title}</p>
                  <p className="text-xs uppercase tracking-[0.3em] text-slate-400">{item.type}</p>
                  <p className="text-[13px] text-slate-300">{item.detail}</p>
                </div>
              ))}
            </div>
            <div className="mt-4 flex justify-end">
              <button className="text-sm text-slate-400" onClick={() => setOpen(false)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
