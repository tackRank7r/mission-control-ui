import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import path from "path";
import { promises as fs } from "fs";

import { getSessionUser } from "@/lib/auth";

const BACKEND_URL = process.env.MISSION_CONTROL_BACKEND_URL || "http://localhost:5000";
const BACKEND_TOKEN = process.env.MISSION_CONTROL_BACKEND_TOKEN || process.env.APP_BACKEND_BEARER || "";
const HISTORY_ENDPOINT = "/history";

type HistoryItem = {
  id: number | string;
  title?: string;
  created_at?: string;
  preview?: string;
};

async function fetchConversationHistory(): Promise<HistoryItem[]> {
  const url = new URL(HISTORY_ENDPOINT, BACKEND_URL);
  url.searchParams.set("limit", "50");

  const res = await fetch(url.toString(), {
    headers: BACKEND_TOKEN ? { Authorization: `Bearer ${BACKEND_TOKEN}` } : undefined,
    cache: "no-store",
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Backend responded with ${res.status}: ${text}`);
  }

  const data = await res.json();
  return (data?.items as HistoryItem[]) ?? [];
}

async function writeConversationFile(items: HistoryItem[]) {
  const targetDir = path.join(process.cwd(), "content", "memory");
  await fs.mkdir(targetDir, { recursive: true });

  const timestamp = new Date().toISOString();
  const header = `---\ntitle: Conversation Sync\ntag: Conversations\nupdated: ${timestamp}\n---\n\n`;
  const body = items
    .map((item) => {
      const created = item.created_at ? new Date(item.created_at).toLocaleString() : "";
      const preview = item.preview || "(no preview available)";
      return `### ${item.title || "Untitled Session"}\n- Created: ${created}\n- Preview: ${preview}\n`;
    })
    .join("\n");

  const content = `${header}Synced ${items.length} sessions on ${timestamp}.\n\n${body}`;
  const filePath = path.join(targetDir, "conversation-sync.md");
  await fs.writeFile(filePath, content, "utf-8");
  return filePath;
}

export async function POST() {
  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ status: "error", message: "Unauthorized" }, { status: 401 });
  }

  try {
    const items = await fetchConversationHistory();
    const filePath = await writeConversationFile(items);
    revalidatePath("/");
    return NextResponse.json({ status: "ok", count: items.length, filePath });
  } catch (error) {
    console.error("Conversation sync failed", error);
    return NextResponse.json({ status: "error", message: (error as Error).message }, { status: 500 });
  }
}
