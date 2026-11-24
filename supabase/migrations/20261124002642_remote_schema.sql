SET local check_function_bodies = off;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "service_role";

CREATE TABLE "public"."option_groups" (
  "id"         bigint  GENERATED ALWAYS AS IDENTITY NOT NULL,
  "name"       text    NOT NULL,
  "min_select" integer NOT NULL DEFAULT 0,
  "max_select" integer NOT NULL,
  CONSTRAINT "option_groups_check" CHECK ((max_select >= min_select)),
  CONSTRAINT "option_groups_min_select_check" CHECK ((min_select >= 0)),
  CONSTRAINT "option_groups_name_key" UNIQUE (name),
  CONSTRAINT "option_groups_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."option_groups"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."options" (
  "id"          bigint  GENERATED ALWAYS AS IDENTITY NOT NULL,
  "group_id"    bigint  NOT NULL,
  "name"        text    NOT NULL,
  "price_cents" integer NOT NULL DEFAULT 0,
  "available"   boolean NOT NULL DEFAULT true,
  CONSTRAINT "options_group_id_name_key" UNIQUE (group_id, name),
  CONSTRAINT "options_pkey" PRIMARY KEY (id),
  CONSTRAINT "options_price_cents_check" CHECK ((price_cents >= 0))
);

ALTER TABLE "public"."options"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."order_item_options" (
  "order_item_id" bigint  NOT NULL,
  "option_id"     bigint  NOT NULL,
  "option_name"   text    NOT NULL,
  "price_cents"   integer NOT NULL,
  CONSTRAINT "order_item_options_pkey" PRIMARY KEY (order_item_id, option_id),
  CONSTRAINT "order_item_options_price_cents_check" CHECK ((price_cents >= 0))
);

ALTER TABLE "public"."order_item_options"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."order_items" (
  "id"               bigint  GENERATED ALWAYS AS IDENTITY NOT NULL,
  "order_id"         uuid    NOT NULL,
  "product_id"       bigint  NOT NULL,
  "product_name"     text    NOT NULL,
  "quantity"         integer NOT NULL,
  "unit_price_cents" integer NOT NULL,
  CONSTRAINT "order_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "order_items_quantity_check" CHECK (((quantity >= 1) AND (quantity <= 20))),
  CONSTRAINT "order_items_unit_price_cents_check" CHECK ((unit_price_cents >= 0))
);

ALTER TABLE "public"."order_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."orders" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "order_number"  bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "customer_name" text                     NOT NULL,
  "status"        text                     NOT NULL DEFAULT 'awaiting_payment'::text,
  "total_cents"   integer                  NOT NULL,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "paid_at"       timestamp with time zone,
  CONSTRAINT "orders_check" CHECK (((status = ANY (ARRAY['awaiting_payment'::text, 'cancelled'::text])) OR (paid_at IS NOT NULL))),
  CONSTRAINT "orders_customer_name_check" CHECK (((char_length(TRIM(BOTH FROM customer_name)) >= 1) AND (char_length(TRIM(BOTH FROM customer_name)) <= 40))),
  CONSTRAINT "orders_order_number_key" UNIQUE (order_number),
  CONSTRAINT "orders_pkey" PRIMARY KEY (id),
  CONSTRAINT "orders_status_check" CHECK ((status = ANY (ARRAY['awaiting_payment'::text, 'paid'::text, 'preparing'::text, 'ready'::text, 'picked_up'::text, 'cancelled'::text]))),
  CONSTRAINT "orders_total_cents_check" CHECK ((total_cents >= 0))
);

ALTER TABLE "public"."orders"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."product_option_groups" (
  "product_id" bigint NOT NULL,
  "group_id"   bigint NOT NULL,
  CONSTRAINT "product_option_groups_pkey" PRIMARY KEY (product_id, group_id)
);

ALTER TABLE "public"."product_option_groups"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."products" (
  "id"               bigint  GENERATED ALWAYS AS IDENTITY NOT NULL,
  "name"             text    NOT NULL,
  "base_price_cents" integer NOT NULL,
  "available"        boolean NOT NULL DEFAULT true,
  "sort_order"       integer NOT NULL DEFAULT 0,
  CONSTRAINT "products_base_price_cents_check" CHECK ((base_price_cents >= 0)),
  CONSTRAINT "products_name_key" UNIQUE (name),
  CONSTRAINT "products_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."products"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON SEQUENCE "public"."option_groups_id_seq" FROM "anon";

REVOKE ALL ON SEQUENCE "public"."option_groups_id_seq" FROM "authenticated";

REVOKE ALL ON SEQUENCE "public"."option_groups_id_seq" FROM "service_role";

REVOKE ALL ON SEQUENCE "public"."options_id_seq" FROM "anon";

REVOKE ALL ON SEQUENCE "public"."options_id_seq" FROM "authenticated";

REVOKE ALL ON SEQUENCE "public"."options_id_seq" FROM "service_role";

REVOKE ALL ON SEQUENCE "public"."order_items_id_seq" FROM "anon";

REVOKE ALL ON SEQUENCE "public"."order_items_id_seq" FROM "authenticated";

REVOKE ALL ON SEQUENCE "public"."order_items_id_seq" FROM "service_role";

REVOKE ALL ON SEQUENCE "public"."orders_order_number_seq" FROM "anon";

REVOKE ALL ON SEQUENCE "public"."orders_order_number_seq" FROM "authenticated";

REVOKE ALL ON SEQUENCE "public"."orders_order_number_seq" FROM "service_role";

REVOKE ALL ON SEQUENCE "public"."products_id_seq" FROM "anon";

REVOKE ALL ON SEQUENCE "public"."products_id_seq" FROM "authenticated";

REVOKE ALL ON SEQUENCE "public"."products_id_seq" FROM "service_role";

CREATE OR REPLACE FUNCTION public.create_order (
  p_customer_name text,
  p_items         jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order_id uuid;
  v_order_number bigint;
  v_item jsonb;
  v_product_id bigint;
  v_quantity int;
  v_base_price int;
  v_product_name text;
  v_total int := 0;
  v_option_ids bigint[];
  v_option_id bigint;
  v_option_price int;
  v_unit_price int;
  v_order_item_id bigint;
  v_group record;
begin
  if p_customer_name is null or trim(p_customer_name) = '' then
    raise exception 'Name is required';
  end if;

  if char_length(trim(p_customer_name)) > 40 then
    raise exception 'Name must be 40 characters or less';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must have at least one drink';
  end if;

  insert into public.orders (customer_name, total_cents)
  values (trim(p_customer_name), 0)
  returning id, order_number into v_order_id, v_order_number;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::bigint;
    v_quantity := (v_item->>'quantity')::int;

    select base_price_cents, name into v_base_price, v_product_name
    from public.products
    where id = v_product_id and available;

    if not found then
      raise exception 'Product % is not available', v_product_id;
    end if;

    v_option_ids := array(
      select jsonb_array_elements_text(v_item->'option_ids')::bigint
    );

    if cardinality(v_option_ids) <>
       (select count(distinct x) from unnest(v_option_ids) as x) then
      raise exception 'A drink cannot have the same option twice';
    end if;

    v_unit_price := v_base_price;

    foreach v_option_id in array v_option_ids loop
      select o.price_cents into v_option_price
      from public.options o
      join public.product_option_groups pog
        on pog.group_id = o.group_id
       and pog.product_id = v_product_id
      where o.id = v_option_id and o.available;

      if not found then
        raise exception 'Option % is not available for this drink', v_option_id;
      end if;

      v_unit_price := v_unit_price + v_option_price;
    end loop;

    for v_group in
      select g.name,
             g.min_select,
             g.max_select,
             (select count(*)
              from public.options o
              where o.group_id = g.id
                and o.id = any(v_option_ids)) as picked
      from public.product_option_groups pog
      join public.option_groups g on g.id = pog.group_id
      where pog.product_id = v_product_id
    loop
      if v_group.picked < v_group.min_select then
        raise exception 'Choose a % for %', v_group.name, v_product_name;
      end if;

      if v_group.picked > v_group.max_select then
        raise exception 'Only % % allowed per drink', v_group.max_select, v_group.name;
      end if;
    end loop;

    insert into public.order_items
      (order_id, product_id, product_name, quantity, unit_price_cents)
    values
      (v_order_id, v_product_id, v_product_name, v_quantity, v_unit_price)
    returning id into v_order_item_id;

    insert into public.order_item_options
      (order_item_id, option_id, option_name, price_cents)
    select v_order_item_id, o.id, o.name, o.price_cents
    from public.options o
    where o.id = any(v_option_ids);

    v_total := v_total + v_unit_price * v_quantity;
  end loop;

  update public.orders
  set total_cents = v_total
  where id = v_order_id;

  return jsonb_build_object(
    'id', v_order_id,
    'order_number', v_order_number,
    'total_cents', v_total
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."create_order"(text, jsonb) FROM "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'pg_catalog'
  AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "anon", "authenticated", "service_role";

ALTER TABLE "public"."options"
  ADD CONSTRAINT "options_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.option_groups(id) ON DELETE RESTRICT;

ALTER TABLE "public"."order_item_options"
  ADD CONSTRAINT "order_item_options_option_id_fkey" FOREIGN KEY (option_id) REFERENCES public.options(id) ON DELETE RESTRICT;

ALTER TABLE "public"."order_item_options"
  ADD CONSTRAINT "order_item_options_order_item_id_fkey" FOREIGN KEY (order_item_id) REFERENCES public.order_items(id) ON DELETE CASCADE;

ALTER TABLE "public"."order_items"
  ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

ALTER TABLE "public"."product_option_groups"
  ADD CONSTRAINT "product_option_groups_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.option_groups(id) ON DELETE RESTRICT;

ALTER TABLE "public"."order_items"
  ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;

ALTER TABLE "public"."product_option_groups"
  ADD CONSTRAINT "product_option_groups_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

CREATE INDEX order_items_order_id_idx ON public.order_items USING btree (order_id);

CREATE EVENT TRIGGER "ensure_rls"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION "public"."rls_auto_enable"();

GRANT EXECUTE ON FUNCTION "public"."create_order"(text, jsonb) TO PUBLIC;

REVOKE ALL ON FUNCTION "public"."create_order"(text, jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."create_order"(text, jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO PUBLIC;

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO "postgres";

REVOKE ALL ON TABLE "public"."option_groups" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."option_groups" TO "anon";

REVOKE ALL ON TABLE "public"."option_groups" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."option_groups" TO "authenticated";

REVOKE ALL ON TABLE "public"."option_groups" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."option_groups" TO "postgres";

REVOKE ALL ON TABLE "public"."option_groups" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."option_groups" TO "service_role";

REVOKE ALL ON TABLE "public"."options" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."options" TO "anon";

REVOKE ALL ON TABLE "public"."options" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."options" TO "authenticated";

REVOKE ALL ON TABLE "public"."options" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."options" TO "postgres";

REVOKE ALL ON TABLE "public"."options" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."options" TO "service_role";

REVOKE ALL ON TABLE "public"."order_item_options" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."order_item_options" TO "anon";

REVOKE ALL ON TABLE "public"."order_item_options" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."order_item_options" TO "authenticated";

REVOKE ALL ON TABLE "public"."order_item_options" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."order_item_options" TO "postgres";

REVOKE ALL ON TABLE "public"."order_item_options" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."order_item_options" TO "service_role";

REVOKE ALL ON TABLE "public"."order_items" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."order_items" TO "anon";

REVOKE ALL ON TABLE "public"."order_items" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."order_items" TO "authenticated";

REVOKE ALL ON TABLE "public"."order_items" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."order_items" TO "postgres";

REVOKE ALL ON TABLE "public"."order_items" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."order_items" TO "service_role";

REVOKE ALL ON TABLE "public"."orders" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."orders" TO "anon";

REVOKE ALL ON TABLE "public"."orders" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."orders" TO "authenticated";

REVOKE ALL ON TABLE "public"."orders" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."orders" TO "postgres";

REVOKE ALL ON TABLE "public"."orders" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."orders" TO "service_role";

REVOKE ALL ON TABLE "public"."product_option_groups" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."product_option_groups" TO "anon";

REVOKE ALL ON TABLE "public"."product_option_groups" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."product_option_groups" TO "authenticated";

REVOKE ALL ON TABLE "public"."product_option_groups" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."product_option_groups" TO "postgres";

REVOKE ALL ON TABLE "public"."product_option_groups" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."product_option_groups" TO "service_role";

REVOKE ALL ON TABLE "public"."products" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."products" TO "anon";

REVOKE ALL ON TABLE "public"."products" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."products" TO "authenticated";

REVOKE ALL ON TABLE "public"."products" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."products" TO "postgres";

REVOKE ALL ON TABLE "public"."products" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."products" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLES TO "service_role";

