create extension if not exists pg_net;

create or replace function public.notify_on_order_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  request_id bigint;
begin
  if new.status = 'accepted'
    and (tg_op = 'INSERT' or old.status is distinct from 'accepted') then
    select net.http_post(
      url := 'https://xmhbrnkukhmzizkiyyhg.supabase.co/functions/v1/send-order-accepted-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'type', TG_OP,
        'schema', TG_TABLE_SCHEMA,
        'table', TG_TABLE_NAME,
        'record', to_jsonb(new),
        'old_record', case when tg_op = 'INSERT' then null else to_jsonb(old) end
      )
    )
    into request_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_order_accepted on public.orders;
create trigger trg_notify_on_order_accepted
after insert or update on public.orders
for each row
execute function public.notify_on_order_accepted();
