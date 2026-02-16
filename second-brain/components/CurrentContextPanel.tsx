type SyncCard = {
  headline: string;
  byline?: string;
  meta?: string;
};

type TaskSummary = {
  id: string;
  title: string;
  owner?: string;
  age?: string;
  tags?: string[];
};

type HotlineCard = {
  status: string;
  number?: string;
  lastCheckedLabel?: string;
  note?: string;
  incidents?: string[];
};

export function CurrentContextPanel({
  sync,
  tasks,
  hotline,
}: {
  sync: SyncCard;
  tasks: TaskSummary[];
  hotline: HotlineCard;
}) {
  return (
    <section className="rounded-3xl border border-white/5 bg-white/5 p-5 text-white shadow-2xl shadow-cyan-900/20">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-cyan-300">Current Context</p>
          <h2 className="text-xl font-semibold">Live mission signal</h2>
        </div>
      </header>
      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl border border-white/10 bg-gradient-to-br from-cyan-500/10 to-white/5 p-4">
          <p className="text-xs uppercase tracking-[0.3em] text-cyan-200">Conversation Sync</p>
          <p className="mt-2 text-lg font-semibold leading-tight">{sync.headline}</p>
          {sync.byline && <p className="mt-1 text-sm text-slate-200">{sync.byline}</p>}
          {sync.meta && <p className="mt-2 text-xs text-slate-400">{sync.meta}</p>}
        </div>

        <div className="rounded-2xl border border-white/10 bg-black/25 p-4">
          <div className="flex items-center justify-between">
            <p className="text-xs uppercase tracking-[0.3em] text-emerald-200">Active Tasks</p>
            <span className="text-xs text-slate-400">{tasks.length} open</span>
          </div>
          <div className="mt-3 space-y-3">
            {tasks.length ? (
              tasks.map((task) => (
                <div key={task.id} className="rounded-xl border border-white/5 bg-white/5/20 p-3">
                  <p className="text-sm font-semibold text-white">{task.title}</p>
                  <div className="mt-1 flex flex-wrap gap-2 text-xs text-slate-400">
                    {task.owner && <span>{task.owner}</span>}
                    {task.tags && task.tags.length > 0 && (
                      <span className="text-slate-500">{task.tags.join(", ")}</span>
                    )}
                    {task.age && <span className="text-slate-500">· {task.age}</span>}
                  </div>
                </div>
              ))
            ) : (
              <p className="text-sm text-slate-400">No in-progress work right now.</p>
            )}
          </div>
        </div>

        <div className="rounded-2xl border border-white/10 bg-black/30 p-4">
          <p className="text-xs uppercase tracking-[0.3em] text-amber-200">Hotline</p>
          <p className="mt-2 text-lg font-semibold text-white">{hotline.status}</p>
          {hotline.number && <p className="text-sm text-slate-200">{hotline.number}</p>}
          {hotline.note && <p className="mt-2 text-sm text-slate-300">{hotline.note}</p>}
          {hotline.lastCheckedLabel && (
            <p className="mt-2 text-xs text-slate-400">Last check: {hotline.lastCheckedLabel}</p>
          )}
          {hotline.incidents && hotline.incidents.length > 0 && (
            <ul className="mt-3 list-disc space-y-1 pl-5 text-xs text-slate-300">
              {hotline.incidents.map((incident) => (
                <li key={incident}>{incident}</li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </section>
  );
}
