import { formatDistanceToNow } from "date-fns";

import { Sidebar } from "@/components/Sidebar";
import { AgentsPanel, CalendarPanel, DocsPanel, MemoryPanel, PeoplePanel, TasksPanel } from "@/components/Panels";
import { CurrentContextPanel } from "@/components/CurrentContextPanel";
import { CommandBar, type CommandItem } from "@/components/CommandBar";
import { SyncButton } from "@/components/SyncButton";
import { LogoutButton } from "@/components/LogoutButton";
import { requireUser } from "@/lib/auth";
import {
  formatTimestamp,
  getAgents,
  getCalendar,
  getContextStatus,
  getDocEntries,
  getMemoryEntries,
  getPeople,
  getTaskBoard,
} from "@/lib/data";

function summarize(text: string) {
  const clean = text.replace(/\n+/g, " ").trim();
  if (clean.length <= 120) return clean;
  return `${clean.slice(0, 117)}…`;
}

function parseSyncCount(content: string | undefined) {
  if (!content) return undefined;
  const match = content.match(/Synced\s+(\d+)\s+sessions/i);
  return match ? Number(match[1]) : undefined;
}

function formatRelativeLabel(dateInput?: string) {
  if (!dateInput) return undefined;
  const date = new Date(dateInput);
  if (Number.isNaN(date.getTime())) return undefined;
  return formatDistanceToNow(date, { addSuffix: true });
}

export default async function Home() {
  const user = await requireUser();

  const [memoryEntriesRaw, docEntries, taskBoard, people, calendar, agents, contextStatus] = await Promise.all([
    getMemoryEntries(),
    getDocEntries(),
    getTaskBoard(),
    getPeople(),
    getCalendar(),
    getAgents(),
    getContextStatus(),
  ]);

  const conversationSyncEntry = memoryEntriesRaw.find((entry) => entry.slug === "conversation-sync");
  const memoryEntries = conversationSyncEntry
    ? [conversationSyncEntry, ...memoryEntriesRaw.filter((entry) => entry.slug !== "conversation-sync")]
    : memoryEntriesRaw;

  const memorySyncMeta = conversationSyncEntry
    ? {
        count: parseSyncCount(conversationSyncEntry.content),
        lastUpdatedLabel: conversationSyncEntry.updated ? formatTimestamp(conversationSyncEntry.updated) : "Recently synced",
        relativeLabel: formatRelativeLabel(conversationSyncEntry.updated),
      }
    : contextStatus?.sync?.lastRun
    ? {
        count: undefined,
        lastUpdatedLabel: formatTimestamp(contextStatus.sync.lastRun),
        relativeLabel: formatRelativeLabel(contextStatus.sync.lastRun),
      }
    : undefined;

  const syncCard = conversationSyncEntry
    ? {
        headline: `${memorySyncMeta?.count ?? "Fresh"} session${memorySyncMeta?.count === 1 ? "" : "s"} ingested`,
        byline: memorySyncMeta?.lastUpdatedLabel,
        meta: memorySyncMeta?.relativeLabel,
      }
    : contextStatus?.sync
    ? {
        headline: contextStatus.sync.status,
        byline: contextStatus.sync.note,
        meta: contextStatus.sync.lastRun ? formatRelativeLabel(contextStatus.sync.lastRun) : undefined,
      }
    : {
        headline: "No sync data yet",
        byline: "Trigger a hotline sync to populate the conversation log.",
      };

  const inProgressLane = taskBoard?.lanes.find((lane) => lane.id === "in-progress" || lane.title.toLowerCase().includes("progress"))
    ?? taskBoard?.lanes[0];
  const activeTasks = inProgressLane
    ? inProgressLane.cards.slice(0, 3).map((card) => ({
        id: card.id,
        title: card.title,
        owner: card.owner,
        tags: card.tags,
        age: card.age,
      }))
    : [];

  const hotlineCard = {
    status: contextStatus?.hotline?.status ?? "Awaiting signal",
    number: contextStatus?.hotline?.number,
    note: contextStatus?.hotline?.note ?? "Run hotline diagnostics to verify routing.",
    lastCheckedLabel: contextStatus?.hotline?.lastChecked ? formatRelativeLabel(contextStatus.hotline.lastChecked) : undefined,
    incidents: contextStatus?.hotline?.incidents,
  };

  const commandItems: CommandItem[] = [
    ...memoryEntries.map((entry) => ({
      id: `memory-${entry.slug}`,
      title: entry.title,
      type: entry.tag || "Memory",
      detail: summarize(entry.content),
    })),
    ...docEntries.map((entry) => ({
      id: `doc-${entry.slug}`,
      title: entry.title,
      type: entry.tag || "Doc",
      detail: summarize(entry.content),
    })),
    ...(taskBoard
      ? taskBoard.lanes.flatMap((lane) =>
          lane.cards.map((card) => ({
            id: `task-${card.id}`,
            title: card.title,
            type: lane.title,
            detail: `${card.tags.join(", ")} · ${card.age}`,
          }))
        )
      : []),
  ];

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#02030a] via-[#050812] to-[#03050b] text-white">
      <div className="flex max-w-7xl mx-auto px-4 md:px-8 py-10 gap-6">
        <Sidebar />
        <main className="flex-1 space-y-8">
          <header className="flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-white/5 bg-white/5 p-6 backdrop-blur">
            <div>
              <p className="text-xs uppercase tracking-[0.4em] text-slate-300">Mission Log</p>
              <h1 className="text-3xl font-semibold">Mission Control</h1>
            </div>
            <div className="flex flex-wrap items-center gap-4">
              <div className="flex items-center gap-3 rounded-2xl border border-white/10 bg-black/30 px-4 py-2 text-left">
                <div>
                  <p className="text-[10px] uppercase tracking-[0.3em] text-slate-400">Signed in</p>
                  <p className="text-sm font-semibold text-white">{user.email}</p>
                </div>
                <LogoutButton />
              </div>
              <SyncButton />
              <CommandBar items={commandItems} />
              <button className="rounded-full bg-white/90 px-4 py-2 text-sm font-semibold text-black shadow-lg shadow-white/20">
                Ping Hotline
              </button>
            </div>
          </header>

          <CurrentContextPanel sync={syncCard} tasks={activeTasks} hotline={hotlineCard} />
          <MemoryPanel entries={memoryEntries} conversationSync={memorySyncMeta} />
          <DocsPanel entries={docEntries} />
          <AgentsPanel agents={agents} />
          <PeoplePanel people={people} />
          <CalendarPanel calendar={calendar} />
          <TasksPanel board={taskBoard} />
        </main>
      </div>
    </div>
  );
}
