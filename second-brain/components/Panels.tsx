import { Agent, CalendarData, MarkdownEntry, Person, TaskBoard } from "@/lib/data";
import { formatTimestamp } from "@/lib/data";

export function MemoryPanel({ entries, conversationSync }: { entries: MarkdownEntry[]; conversationSync?: { count?: number; lastUpdatedLabel: string; relativeLabel?: string; note?: string; }; }) {
  return (
    <section className="grid gap-4 rounded-2xl bg-white/5 p-4 text-white shadow-2xl shadow-purple-900/20">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-violet-400">Memory</p>
          <h2 className="text-xl font-semibold">Long-Term + Daily Journal</h2>
        </div>
        {conversationSync && (
          <div className="rounded-2xl border border-white/10 bg-black/30 px-4 py-3 text-right">
            <p className="text-[10px] uppercase tracking-[0.3em] text-slate-400">Conversations</p>
            <p className="text-sm font-semibold text-white">
              {conversationSync.count ?? "—"} synced
            </p>
            <p className="text-xs text-slate-400">
              {conversationSync.relativeLabel ?? conversationSync.lastUpdatedLabel}
            </p>
          </div>
        )}
      </header>
      <div className="grid gap-3 md:grid-cols-[220px_1fr]">
        <div className="rounded-xl bg-white/5 p-3">
          <p className="text-xs text-slate-400">Recent Entries</p>
          <div className="mt-3 space-y-2">
            {entries.map((entry) => (
              <div key={entry.slug} className="rounded-lg bg-black/40 px-3 py-2">
                <p className="text-sm font-semibold">{entry.title}</p>
                {entry.tag && <p className="text-[10px] uppercase text-violet-300">{entry.tag}</p>}
                <p className="text-[11px] text-slate-400">{formatTimestamp(entry.updated)}</p>
              </div>
            ))}
          </div>
        </div>
        <div className="space-y-6 overflow-y-auto pr-1 text-sm">
          {entries.slice(0, 3).map((entry) => (
            <article key={entry.slug} className="rounded-2xl border border-white/5 bg-black/30 p-4">
              <h3 className="text-lg font-semibold">{entry.title}</h3>
              <p className="text-[11px] text-slate-400">{formatTimestamp(entry.updated)}</p>
              <div
                className="mt-3 space-y-2 text-sm leading-relaxed text-slate-200"
                dangerouslySetInnerHTML={{ __html: entry.content.replace(/\n/g, "<br/>") }}
              />
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

export function DocsPanel({ entries }: { entries: MarkdownEntry[] }) {
  return (
    <section className="rounded-2xl bg-white/5 p-4 text-white shadow-2xl shadow-slate-900/30">
      <header className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-cyan-400">Docs</p>
          <h2 className="text-xl font-semibold">Knowledge Base</h2>
        </div>
        <input
          placeholder="Search documents..."
          className="rounded-full border border-white/10 bg-black/40 px-4 py-2 text-sm placeholder:text-slate-500 focus:outline-none"
        />
      </header>
      <div className="mt-4 grid gap-4 md:grid-cols-[240px_1fr]">
        <div className="space-y-2">
          {entries.map((entry) => (
            <div key={entry.slug} className="rounded-xl border border-white/5 bg-black/30 px-4 py-3">
              <p className="text-sm font-semibold">{entry.title}</p>
              <p className="text-[11px] text-slate-400">{entry.tag}</p>
              <p className="text-[11px] text-slate-500">{formatTimestamp(entry.updated)}</p>
            </div>
          ))}
        </div>
        <div className="rounded-2xl border border-white/5 bg-black/20 p-5">
          {entries[0] ? (
            <>
              <h3 className="text-lg font-semibold">{entries[0].title}</h3>
              <div
                className="mt-4 space-y-3 text-sm leading-relaxed text-slate-200"
                dangerouslySetInnerHTML={{ __html: entries[0].content.replace(/\n/g, "<br/>") }}
              />
            </>
          ) : (
            <p className="text-slate-500">No documents yet.</p>
          )}
        </div>
      </div>
    </section>
  );
}

export function TasksPanel({ board }: { board: TaskBoard | null }) {
  if (!board) {
    return (
      <section className="rounded-2xl border border-white/5 bg-black/20 p-6 text-white">
        <p>No task data yet. Drop a tasks.json file into content/.</p>
      </section>
    );
  }

  return (
    <section className="rounded-2xl bg-white/5 p-5 text-white shadow-2xl shadow-emerald-900/20">
      <header className="flex flex-wrap items-center gap-4">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-emerald-300">Tasks</p>
          <h2 className="text-xl font-semibold">Mission Board</h2>
        </div>
        <div className="flex gap-6 text-sm text-slate-300">
          <div>
            <p className="text-[11px] uppercase text-slate-500">This week</p>
            <p className="text-lg font-semibold">{board.stats.thisWeek}</p>
          </div>
          <div>
            <p className="text-[11px] uppercase text-slate-500">In progress</p>
            <p className="text-lg font-semibold">{board.stats.inProgress}</p>
          </div>
          <div>
            <p className="text-[11px] uppercase text-slate-500">Completion</p>
            <p className="text-lg font-semibold">{Math.round(board.stats.completion * 100)}%</p>
          </div>
        </div>
      </header>
      <div className="mt-5 grid gap-4 lg:grid-cols-[2fr_260px]">
        <div className="grid gap-4 md:grid-cols-3">
          {board.lanes.map((lane) => (
            <div key={lane.id} className="rounded-2xl border border-white/5 bg-black/30 p-4">
              <div className="flex items-center justify-between text-sm text-slate-400">
                <p className="font-semibold text-white">{lane.title}</p>
                <span>{lane.cards.length}</span>
              </div>
              <div className="mt-3 space-y-3">
                {lane.cards.map((card) => (
                  <div key={card.id} className="rounded-xl border border-white/5 bg-gradient-to-br from-white/5 to-white/0 p-3">
                    <p className="text-sm font-semibold">{card.title}</p>
                    <div className="mt-1 flex items-center justify-between text-[11px] text-slate-400">
                      <span>{card.tags.join(", ")}</span>
                      <span>{card.age}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
        <div className="rounded-2xl border border-white/5 bg-black/30 p-4">
          <p className="text-sm font-semibold">Live Activity</p>
          <div className="mt-3 space-y-3 text-sm">
            {board.activity.map((item) => (
              <div key={item.id} className="rounded-xl bg-white/5 p-3">
                <p className="text-white">{item.text}</p>
                <p className="text-[11px] text-slate-400">{item.user} · {item.time} ago</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

export function AgentsPanel({ agents }: { agents: Agent[] }) {
  if (!agents.length) return null;

  const statusTone: Record<string, string> = {
    online: "bg-emerald-400/15 text-emerald-200 border border-emerald-400/30",
    deploying: "bg-amber-400/15 text-amber-200 border border-amber-400/30",
    idle: "bg-slate-400/10 text-slate-200 border border-slate-500/30",
  };

  const getStatusStyle = (status?: string) => {
    if (!status) return "bg-white/5 text-slate-200 border border-white/10";
    const key = status.toLowerCase();
    return statusTone[key] ?? "bg-white/5 text-slate-200 border border-white/10";
  };

  return (
    <section className="rounded-2xl bg-white/5 p-5 text-white shadow-2xl shadow-indigo-900/20">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-indigo-300">Agents</p>
          <h2 className="text-xl font-semibold">Mission Specialists on Deck</h2>
        </div>
        <p className="text-sm text-slate-400">{agents.length} active sub-agent{agents.length === 1 ? "" : "s"}</p>
      </header>
      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        {agents.map((agent) => (
          <article key={agent.name} className="rounded-2xl border border-white/5 bg-black/25 p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-lg font-semibold">{agent.name}</p>
                {agent.codename && (
                  <p className="text-xs uppercase tracking-[0.3em] text-violet-300">Codename · {agent.codename}</p>
                )}
              </div>
              <span className={`rounded-full px-3 py-1 text-xs font-semibold ${getStatusStyle(agent.status)}`}>
                {agent.status ?? "active"}
              </span>
            </div>
            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-xs uppercase tracking-[0.3em] text-slate-500">Assigned Task</dt>
                <dd className="text-slate-100">{agent.task}</dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-[0.3em] text-slate-500">Permissions</dt>
                <dd className="text-slate-200">{agent.permissions}</dd>
              </div>
              <div className="grid gap-2 md:grid-cols-2">
                <div>
                  <dt className="text-xs uppercase tracking-[0.3em] text-slate-500">Cadence</dt>
                  <dd className="text-slate-200">{agent.cadence}</dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-[0.3em] text-slate-500">Last Report</dt>
                  <dd className="text-slate-200">{formatTimestamp(agent.lastReport) || "–"}</dd>
                </div>
              </div>
              {agent.channel && (
                <div>
                  <dt className="text-xs uppercase tracking-[0.3em] text-slate-500">Channel</dt>
                  <dd className="text-slate-200">{agent.channel}</dd>
                </div>
              )}
            </dl>
            {agent.notes?.length ? (
              <div className="mt-4">
                <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Reporting Notes</p>
                <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-slate-200">
                  {agent.notes.map((note) => (
                    <li key={note} className="rounded-lg bg-white/5 px-3 py-1">{note}</li>
                  ))}
                </ul>
              </div>
            ) : null}
          </article>
        ))}
      </div>
    </section>
  );
}

export function PeoplePanel({ people }: { people: Person[] }) {
  if (!people.length) return null;

  return (
    <section className="rounded-2xl bg-white/5 p-5 text-white shadow-2xl shadow-slate-900/30">
      <header className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-pink-300">People</p>
          <h2 className="text-xl font-semibold">Allies & Owners</h2>
        </div>
      </header>
      <div className="mt-4 grid gap-4 md:grid-cols-[240px_1fr]">
        <div className="space-y-2">
          {people.map((person) => (
            <div key={person.name} className="rounded-2xl border border-white/5 bg-black/30 p-4">
              <p className="text-sm font-semibold">{person.name}</p>
              <p className="text-[11px] uppercase text-slate-400">{person.role}</p>
              {person.codename && (
                <p className="text-[11px] text-violet-300">Codename: {person.codename}</p>
              )}
              {person.lastContact && (
                <p className="text-[11px] text-slate-500 mt-1">Last touch · {formatTimestamp(person.lastContact)}</p>
              )}
            </div>
          ))}
        </div>
        <div className="space-y-4">
          {people.map((person) => (
            <article key={`${person.name}-detail`} className="rounded-2xl border border-white/5 bg-black/20 p-5">
              <h3 className="text-lg font-semibold">{person.name}</h3>
              <p className="text-sm text-slate-400">{person.role}</p>
              <div className="mt-3">
                <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Focus</p>
                <ul className="mt-1 list-disc space-y-1 pl-5 text-sm text-slate-200">
                  {person.focus.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </div>
              <div className="mt-3">
                <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Notes</p>
                <ul className="mt-1 space-y-1 text-sm text-slate-200">
                  {person.notes.map((note) => (
                    <li key={note} className="rounded-lg bg-white/5 px-3 py-1">{note}</li>
                  ))}
                </ul>
              </div>
              <div className="mt-3">
                <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Open items</p>
                <ul className="mt-1 list-disc space-y-1 pl-5 text-sm text-amber-200">
                  {person.openItems.map((task) => (
                    <li key={task}>{task}</li>
                  ))}
                </ul>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

const COLOR_MAP: Record<string, string> = {
  purple: "from-purple-500/20",
  amber: "from-amber-500/20",
  blue: "from-sky-500/20",
  rose: "from-rose-500/20",
  emerald: "from-emerald-500/20",
  violet: "from-violet-500/20",
  cyan: "from-cyan-500/20",
  orange: "from-orange-500/20",
  slate: "from-slate-500/20",
};

export function CalendarPanel({ calendar }: { calendar: CalendarData | null }) {
  if (!calendar) return null;

  return (
    <section className="rounded-2xl bg-white/5 p-5 text-white shadow-2xl shadow-blue-900/20">
      <header className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-blue-300">Calendar</p>
          <h2 className="text-xl font-semibold">Scheduled Routines</h2>
        </div>
        <div className="text-sm text-slate-400">{calendar.week}</div>
      </header>
      <div className="mt-4 grid gap-3 md:grid-cols-7">
        {calendar.blocks.map((day) => (
          <div key={day.day} className="rounded-2xl border border-white/5 bg-black/30 p-3">
            <p className="text-xs uppercase tracking-[0.3em] text-slate-500">{day.day}</p>
            <p className="text-lg font-semibold">{day.date.split("-").slice(1).join("/")}</p>
            <div className="mt-3 space-y-2 text-sm">
              {day.slots.map((slot) => (
                <div
                  key={slot.title}
                  className={`rounded-xl border border-white/5 bg-gradient-to-br ${COLOR_MAP[slot.color] ?? "from-white/10"} to-transparent p-2`}
                >
                  <p className="text-xs uppercase tracking-[0.2em] text-slate-300">{slot.tag}</p>
                  <p className="text-sm font-semibold">{slot.title}</p>
                  <p className="text-[11px] text-slate-400">{slot.time}</p>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="mt-5 rounded-2xl border border-white/5 bg-black/20 p-4">
        <p className="text-sm font-semibold">Next up</p>
        <div className="mt-2 space-y-1 text-sm text-slate-300">
          {calendar.nextUp.map((item) => (
            <div key={item.title} className="flex items-center justify-between rounded-xl bg-white/5 px-3 py-2">
              <span>{item.title}</span>
              <span className="text-xs text-amber-200">{item.dueIn}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
