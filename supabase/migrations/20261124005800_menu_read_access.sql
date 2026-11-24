-- Menu read access for the public ordering app.
-- anon = customers (not logged in); authenticated = the host once logged in.

-- 1. Drop privileges nobody needs. TRUNCATE bypasses RLS entirely.
revoke truncate, trigger, references, maintain
  on public.products, public.option_groups, public.options,
     public.product_option_groups, public.orders,
     public.order_items, public.order_item_options
  from anon, authenticated;

-- 2. Table-level gate: allow reading the menu tables only.
grant select
  on public.products, public.option_groups, public.options,
     public.product_option_groups
  to anon, authenticated;

-- 3. Row-level gate: every menu row is visible.
create policy "menu readable by everyone"
  on public.products for select to anon, authenticated using (true);
create policy "menu readable by everyone"
  on public.option_groups for select to anon, authenticated using (true);
create policy "menu readable by everyone"
  on public.options for select to anon, authenticated using (true);
create policy "menu readable by everyone"
  on public.product_option_groups for select to anon, authenticated using (true);

-- 4. Make create_order's access explicit instead of inherited via PUBLIC.
revoke execute on function public.create_order(text, jsonb) from public;
grant execute on function public.create_order(text, jsonb) to anon, authenticated;
