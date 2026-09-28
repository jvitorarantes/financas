-- O backend (Edge Functions) usa o papel service_role para gravar as análises
-- em ai_insights. Concede as permissões explicitamente para funcionar mesmo
-- com "Automatically expose new tables" desligado no projeto.
grant usage on schema public to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
