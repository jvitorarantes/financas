import { test } from "node:test";
import assert from "node:assert/strict";
import { validateAdminAction } from "../_shared/admin.ts";

const ID = "5e550000-0000-4000-8000-000000000001";

test("criar usuário: valida e normaliza", () => {
  const r = validateAdminAction({ action: "create", email: " Bia@Teste.com ", password: "senha-forte-1", full_name: " Bia " });
  assert.deepEqual(r, { ok: true, value: { action: "create", email: "bia@teste.com", password: "senha-forte-1", full_name: "Bia" } });
});

test("criar usuário: recusa dados ruins", () => {
  assert.equal(validateAdminAction({ action: "create", email: "bia", password: "senha-forte-1", full_name: "Bia" }).ok, false);
  assert.equal(validateAdminAction({ action: "create", email: "bia@teste.com", password: "123", full_name: "Bia" }).ok, false);
  assert.equal(validateAdminAction({ action: "create", email: "bia@teste.com", password: "senha-forte-1", full_name: " " }).ok, false);
});

test("senha e exclusão exigem usuário válido", () => {
  assert.equal(validateAdminAction({ action: "set_password", user_id: ID, password: "nova-senha-1" }).ok, true);
  assert.equal(validateAdminAction({ action: "set_password", user_id: "x", password: "nova-senha-1" }).ok, false);
  assert.equal(validateAdminAction({ action: "delete", user_id: ID }).ok, true);
  assert.equal(validateAdminAction({ action: "delete", user_id: "1; drop table" }).ok, false);
});

test("ação desconhecida ou corpo vazio", () => {
  assert.equal(validateAdminAction(null).ok, false);
  assert.equal(validateAdminAction({ action: "promote" }).ok, false);
  assert.deepEqual(validateAdminAction({ action: "list" }), { ok: true, value: { action: "list" } });
});
