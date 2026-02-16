import path from "path";
import { promises as fs } from "fs";
import matter from "gray-matter";
import { format } from "date-fns";

const CONTENT_DIR = path.join(process.cwd(), "content");

export type MarkdownEntry = {
  slug: string;
  title: string;
  tag?: string;
  wordCount?: number;
  updated?: string;
  content: string;
};

async function readMarkdownDir(dir: string): Promise<MarkdownEntry[]> {
  const directory = path.join(CONTENT_DIR, dir);
  let files: string[] = [];
  try {
    files = await fs.readdir(directory);
  } catch {
    return [];
  }

  const entries = await Promise.all(
    files
      .filter((file) => file.endsWith(".md") || file.endsWith(".mdx"))
      .map(async (file) => {
        const filePath = path.join(directory, file);
        const raw = await fs.readFile(filePath, "utf-8");
        const { data, content } = matter(raw);
        return {
          slug: file.replace(/\.mdx?$/, ""),
          title: data.title || file,
          tag: data.tag,
          wordCount: data.wordCount,
          updated: data.updated,
          content,
        } as MarkdownEntry;
      })
  );

  return entries.sort((a, b) => {
    const aDate = a.updated ? new Date(a.updated).getTime() : 0;
    const bDate = b.updated ? new Date(b.updated).getTime() : 0;
    return bDate - aDate;
  });
}

type DocSource = {
  title: string;
  tag?: string;
  path: string;
  updated?: string;
};

async function readExternalDocs(): Promise<MarkdownEntry[]> {
  try {
    const manifestPath = path.join(CONTENT_DIR, "doc-sources.json");
    const rawManifest = await fs.readFile(manifestPath, "utf-8");
    const manifest = JSON.parse(rawManifest) as DocSource[];

    const entries = await Promise.all(
      manifest.map(async (entry, index) => {
        const absolutePath = path.resolve(process.cwd(), entry.path);
        const fileRaw = await fs.readFile(absolutePath, "utf-8");
        const { data, content } = matter(fileRaw);
        return {
          slug: `${entry.title.replace(/\s+/g, "-").toLowerCase()}-${index}`,
          title: entry.title || data.title || path.basename(entry.path),
          tag: entry.tag || data.tag,
          wordCount: data.wordCount,
          updated: entry.updated || data.updated,
          content,
        } satisfies MarkdownEntry;
      })
    );

    return entries;
  } catch {
    return [];
  }
}

export async function getMemoryEntries() {
  return readMarkdownDir("memory");
}

export async function getDocEntries() {
  const [local, external] = await Promise.all([
    readMarkdownDir("docs"),
    readExternalDocs(),
  ]);
  return [...external, ...local];
}

export type TaskBoard = {
  stats: {
    thisWeek: number;
    inProgress: number;
    total: number;
    completion: number;
  };
  lanes: {
    id: string;
    title: string;
    cards: {
      id: string;
      title: string;
      tags: string[];
      owner: string;
      age: string;
    }[];
  }[];
  activity: {
    id: string;
    user: string;
    time: string;
    text: string;
  }[];
};

export type Person = {
  name: string;
  role: string;
  codename?: string;
  lastContact?: string;
  focus: string[];
  notes: string[];
  openItems: string[];
};

export type CalendarData = {
  week: string;
  blocks: {
    day: string;
    date: string;
    slots: {
      title: string;
      time: string;
      tag: string;
      color: string;
    }[];
  }[];
  nextUp: {
    title: string;
    dueIn: string;
  }[];
};

export type ContextStatus = {
  sync?: {
    status: string;
    lastRun?: string;
    note?: string;
  };
  hotline?: {
    status: string;
    number?: string;
    lastChecked?: string;
    note?: string;
    incidents?: string[];
  };
};

export type Agent = {
  name: string;
  codename?: string;
  task: string;
  permissions: string;
  cadence: string;
  status?: string;
  channel?: string;
  lastReport?: string;
  notes?: string[];
};

export async function getAgents(): Promise<Agent[]> {
  try {
    const raw = await fs.readFile(path.join(CONTENT_DIR, "agents.json"), "utf-8");
    return JSON.parse(raw) as Agent[];
  } catch {
    return [];
  }
}

export async function getTaskBoard(): Promise<TaskBoard | null> {
  try {
    const raw = await fs.readFile(path.join(CONTENT_DIR, "tasks.json"), "utf-8");
    const data = JSON.parse(raw);
    return data as TaskBoard;
  } catch {
    return null;
  }
}

export async function getPeople(): Promise<Person[]> {
  try {
    const raw = await fs.readFile(path.join(CONTENT_DIR, "people.json"), "utf-8");
    const data = JSON.parse(raw) as Person[];
    return data;
  } catch {
    return [];
  }
}

export async function getCalendar(): Promise<CalendarData | null> {
  try {
    const raw = await fs.readFile(path.join(CONTENT_DIR, "calendar.json"), "utf-8");
    return JSON.parse(raw) as CalendarData;
  } catch {
    return null;
  }
}

export async function getContextStatus(): Promise<ContextStatus | null> {
  try {
    const raw = await fs.readFile(path.join(CONTENT_DIR, "context.json"), "utf-8");
    return JSON.parse(raw) as ContextStatus;
  } catch {
    return null;
  }
}

export function formatTimestamp(input?: string) {
  if (!input) return "";
  try {
    return format(new Date(input), "PPpp");
  } catch {
    return input;
  }
}
