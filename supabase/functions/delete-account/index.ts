import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

async function listOwnedObjects(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const result: string[] = [];

  async function walk(path: string): Promise<void> {
    let offset = 0;
    const limit = 100;
    while (true) {
      const { data, error } = await admin.storage.from(bucket).list(path, {
        limit,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (error) throw error;
      const entries = data ?? [];
      for (const entry of entries) {
        const fullPath = path ? `${path}/${entry.name}` : entry.name;
        if (entry.id == null && entry.metadata == null) {
          await walk(fullPath);
        } else {
          result.push(fullPath);
        }
      }
      if (entries.length < limit) break;
      offset += limit;
    }
  }

  await walk(prefix);
  return result;
}

async function removeOwnedObjects(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  const paths = await listOwnedObjects(admin, bucket, userId);
  for (let index = 0; index < paths.length; index += 500) {
    const batch = paths.slice(index, index + 500);
    if (batch.length === 0) continue;
    const { error } = await admin.storage.from(bucket).remove(batch);
    if (error) throw error;
  }
}

async function revokeRefreshSessions(
  supabaseUrl: string,
  anonKey: string,
  authorization: string,
): Promise<void> {
  const response = await fetch(`${supabaseUrl}/auth/v1/logout?scope=global`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: authorization,
      "Cache-Control": "no-store",
    },
  });
  if (!response.ok) {
    throw new Error(`global_signout_failed:${response.status}`);
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 503,
      headers: jsonHeaders,
    });
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  const user = userData.user;
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  let payload: Record<string, unknown> = {};
  try {
    payload = await request.json();
  } catch (_) {
    payload = {};
  }
  if (payload.confirm !== "DELETE") {
    return new Response(JSON.stringify({ error: "confirmation_required" }), {
      status: 400,
      headers: jsonHeaders,
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    // Auth deletion is blocked while the user owns Storage objects.
    await removeOwnedObjects(admin, "chat-media", user.id);
    await removeOwnedObjects(admin, "status-media", user.id);

    // Supabase JWT access tokens live until exp; global sign-out revokes all
    // refresh sessions first so a deleted account cannot mint replacement
    // access tokens on another device while deletion is completing.
    await revokeRefreshSessions(supabaseUrl, anonKey, authorization);

    const { error: deleteError } = await admin.auth.admin.deleteUser(
      user.id,
      false,
    );
    if (deleteError) throw deleteError;

    return new Response(JSON.stringify({ deleted: true }), {
      status: 200,
      headers: jsonHeaders,
    });
  } catch (error) {
    console.error("Chaty account deletion failed", error);
    return new Response(JSON.stringify({ error: "delete_failed" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }
});
