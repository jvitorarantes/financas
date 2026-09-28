// POST /functions/v1/admin-users  (JSON) — só para administradores.
//   { action: "list" }
//   { action: "create", email, password, full_name }
//   { action: "set_password", user_id, password }
//   { action: "delete", user_id }
// Usa a API administrativa do Supabase (service role, só no servidor), que
// funciona mesmo com o cadastro público desligado.

import { AppError, authenticate, corsHeaders, errorResponse, json, serviceClient } from "../_shared/http.ts";
import { validateAdminAction } from "../_shared/admin.ts";

const fail = (message: string, status = 400) =>
  json({ error: { code: "admin_error", message } }, status);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse(new AppError("invalid_request", 405));
  try {
    const ctx = await authenticate(req);
    const admin = serviceClient();

    const { data: me } = await admin.from("users").select("is_admin").eq("id", ctx.user.id).maybeSingle();
    if (!me?.is_admin) return fail("Apenas o administrador pode acessar esta página.", 403);

    const parsed = validateAdminAction(await req.json().catch(() => null));
    if (!parsed.ok) return fail(parsed.message);
    const action = parsed.value;

    const { data: limit } = await admin.rpc("admin_max_users");
    const maxUsers = typeof limit === "number" ? limit : 20;

    switch (action.action) {
      case "list": {
        const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
        if (error) throw error;
        const { data: profiles } = await admin.from("users").select("id, full_name, is_admin");
        const byId = new Map((profiles ?? []).map((p) => [p.id as string, p]));
        const users = data.users.map((u) => ({
          id: u.id,
          email: u.email,
          full_name: byId.get(u.id)?.full_name ?? null,
          is_admin: byId.get(u.id)?.is_admin ?? false,
          created_at: u.created_at,
          last_sign_in_at: u.last_sign_in_at ?? null,
        })).sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));
        return json({ users, max_users: maxUsers });
      }
      case "create": {
        const { count } = await admin.from("users").select("id", { count: "exact", head: true });
        if ((count ?? 0) >= maxUsers) return fail(`Limite de ${maxUsers} contas atingido.`);
        const { data, error } = await admin.auth.admin.createUser({
          email: action.email,
          password: action.password,
          email_confirm: true,
          user_metadata: { full_name: action.full_name },
        });
        if (error) {
          const msg = error.message.toLowerCase();
          if (msg.includes("already") || msg.includes("exists")) return fail("Já existe uma conta com esse e-mail.");
          if (msg.includes("password")) return fail("Senha fraca. Use pelo menos 8 caracteres, com letras e números.");
          console.error("admin_create_error", error.message);
          return fail("Não foi possível criar a conta.");
        }
        return json({ user: { id: data.user?.id, email: data.user?.email } });
      }
      case "set_password": {
        const { error } = await admin.auth.admin.updateUserById(action.user_id, { password: action.password });
        if (error) {
          console.error("admin_password_error", error.message);
          return fail("Não foi possível alterar a senha.");
        }
        return json({ ok: true });
      }
      case "delete": {
        if (action.user_id === ctx.user.id) return fail("Você não pode excluir a própria conta de administrador.");
        const { error } = await admin.auth.admin.deleteUser(action.user_id);
        if (error) {
          console.error("admin_delete_error", error.message);
          return fail("Não foi possível excluir a conta.");
        }
        return json({ ok: true });
      }
    }
  } catch (err) {
    return errorResponse(err);
  }
});
