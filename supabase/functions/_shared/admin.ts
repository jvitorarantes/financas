// Validação das ações da página de administração (sem dependências externas,
// para ser testada no Node).

export type AdminAction =
  | { action: "list" }
  | { action: "create"; email: string; password: string; full_name: string }
  | { action: "set_password"; user_id: string; password: string }
  | { action: "delete"; user_id: string };

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AdminValidation = { ok: true; value: AdminAction } | { ok: false; message: string };

export function validatePassword(password: unknown): string | null {
  if (typeof password !== "string" || password.length < 8) return "A senha deve ter pelo menos 8 caracteres.";
  if (password.length > 72) return "A senha deve ter no máximo 72 caracteres.";
  return null;
}

export function validateAdminAction(body: unknown): AdminValidation {
  if (!body || typeof body !== "object") return { ok: false, message: "Pedido inválido." };
  const b = body as Record<string, unknown>;
  switch (b.action) {
    case "list":
      return { ok: true, value: { action: "list" } };
    case "create": {
      const email = typeof b.email === "string" ? b.email.trim().toLowerCase() : "";
      if (!EMAIL.test(email) || email.length > 254) return { ok: false, message: "E-mail inválido." };
      const pwdError = validatePassword(b.password);
      if (pwdError) return { ok: false, message: pwdError };
      const name = typeof b.full_name === "string" ? b.full_name.trim() : "";
      if (name.length === 0) return { ok: false, message: "Informe o nome." };
      if (name.length > 120) return { ok: false, message: "Nome muito longo." };
      return { ok: true, value: { action: "create", email, password: b.password as string, full_name: name } };
    }
    case "set_password": {
      if (typeof b.user_id !== "string" || !UUID.test(b.user_id)) return { ok: false, message: "Usuário inválido." };
      const pwdError = validatePassword(b.password);
      if (pwdError) return { ok: false, message: pwdError };
      return { ok: true, value: { action: "set_password", user_id: b.user_id, password: b.password as string } };
    }
    case "delete":
      if (typeof b.user_id !== "string" || !UUID.test(b.user_id)) return { ok: false, message: "Usuário inválido." };
      return { ok: true, value: { action: "delete", user_id: b.user_id } };
    default:
      return { ok: false, message: "Ação desconhecida." };
  }
}
