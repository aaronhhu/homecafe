insert into option_groups (name, min_select, max_select) values
  ('milk',  1, 1),
  ('top',   0, 1),
  ('puree', 0, 1);

insert into options (group_id, name, price_cents)
select g.id, v.name, v.price_cents
from (values
  ('milk',  'Whole milk',            0),
  ('milk',  'Soy milk',              0),
  ('top',   'Cream top',           100),
  ('top',   'Tofu top',            100),
  ('puree', 'Mangosteen puree',    100),
  ('puree', 'Passion fruit puree', 100)
) as v(group_name, name, price_cents)
join option_groups g on g.name = v.group_name;

insert into products (name, base_price_cents, sort_order) values
  ('Tofu tea',                              600, 1),
  ('Matcha with mangosteen puree',          600, 2),
  ('Matcha with passion fruit + cream top', 600, 3),
  ('Build your own matcha',                 500, 4);

insert into product_option_groups (product_id, group_id)
select p.id, g.id
from products p
cross join option_groups g
where g.name = 'milk'
union all
select p.id, g.id
from products p
join option_groups g on g.name in ('top', 'puree')
where p.name = 'Build your own matcha';