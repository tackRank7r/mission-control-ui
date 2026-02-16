import { Home, Calendar, FileText, Notebook, Brain, Users, CheckSquare, Bot } from "lucide-react";
import clsx from "clsx";

const NAV_ITEMS = [
  { icon: CheckSquare, label: "Tasks" },
  { icon: FileText, label: "Content" },
  { icon: Notebook, label: "Docs" },
  { icon: Brain, label: "Memory" },
  { icon: Calendar, label: "Calendar" },
  { icon: Users, label: "People" },
  { icon: Bot, label: "Agents" },
];

export function Sidebar() {
  return (
    <aside className="hidden md:flex w-60 flex-col bg-[#0b0c10] text-slate-200 border-r border-white/5">
      <div className="flex items-center gap-2 px-5 py-6 text-lg font-semibold">
        <Home className="h-5 w-5 text-violet-300" />
        Mission Control
      </div>
      <nav className="flex-1 space-y-1 px-3">
        {NAV_ITEMS.map((item, index) => (
          <button
            key={item.label}
            className={clsx(
              "w-full flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition",
              index === 0 ? "bg-white/10 text-white" : "text-slate-400 hover:bg-white/5 hover:text-white"
            )}
          >
            <item.icon className="h-4 w-4" />
            {item.label}
          </button>
        ))}
      </nav>
      <div className="px-5 py-4 text-xs text-slate-500">v0.1 — Mission Control</div>
    </aside>
  );
}
