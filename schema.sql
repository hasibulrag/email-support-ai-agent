-- =====================================================================
-- Email Support AI Agent: ALL Supabase tables (5 tables)
-- Run this whole file once in Supabase > SQL Editor > New query > Run.
-- Safe to run again: it only creates what is missing.
-- Columns were derived from the n8n workflow (every field the nodes read/write).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) email_logs: one row per customer email
--    status values used by the workflow:
--    received, awaiting_approval, auto_sending, replied, rejected,
--    owner_only, no_reply_needed
-- ---------------------------------------------------------------------
create table if not exists public.email_logs (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);

alter table public.email_logs
  add column if not exists message_id           text,
  add column if not exists thread_id            text,
  add column if not exists from_email           text,
  add column if not exists subject              text,
  add column if not exists body_masked          text,
  add column if not exists category             text,
  add column if not exists agent_name           text,
  add column if not exists ai_reply             text,
  add column if not exists status               text    default 'received',
  add column if not exists needs_owner_approval boolean default false,
  add column if not exists reply_sent_at        timestamptz;

-- message_id must be unique: the workflow updates rows "where message_id = ..."
-- (if this line errors, old test rows are duplicated: delete them and run again)
create unique index if not exists email_logs_message_id_uidx on public.email_logs (message_id);
create index        if not exists email_logs_created_at_idx  on public.email_logs (created_at);
create index        if not exists email_logs_status_idx      on public.email_logs (status);

-- ---------------------------------------------------------------------
-- 2) booking_events: one row per booked / rescheduled / cancelled meeting
--    start_time / end_time are text on purpose: the AI sends ISO strings,
--    and an empty value for cancelled meetings would break a timestamp column.
-- ---------------------------------------------------------------------
create table if not exists public.booking_events (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);

alter table public.booking_events
  add column if not exists message_id        text,
  add column if not exists action            text,   -- booked | rescheduled | cancelled
  add column if not exists calendar_event_id text,
  add column if not exists customer_email    text,
  add column if not exists start_time        text,
  add column if not exists end_time          text,
  add column if not exists notes             text;

create index if not exists booking_events_created_at_idx on public.booking_events (created_at);
create index if not exists booking_events_action_idx     on public.booking_events (action);

-- ---------------------------------------------------------------------
-- 3) error_logs: written by the Error Trigger branch
-- ---------------------------------------------------------------------
create table if not exists public.error_logs (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);

alter table public.error_logs
  add column if not exists workflow_name text,
  add column if not exists failed_node   text,
  add column if not exists error_message text,
  add column if not exists execution_id  text,
  add column if not exists execution_url text;

create index if not exists error_logs_created_at_idx on public.error_logs (created_at);

-- ---------------------------------------------------------------------
-- 4) daily_reports: one row per daily report (8 PM)
--    by_category_json is text because the workflow sends JSON.stringify(...)
-- ---------------------------------------------------------------------
create table if not exists public.daily_reports (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);

alter table public.daily_reports
  add column if not exists report_date          date,
  add column if not exists total_emails         integer default 0,
  add column if not exists replied              integer default 0,
  add column if not exists awaiting_approval    integer default 0,
  add column if not exists rejected             integer default 0,
  add column if not exists owner_only           integer default 0,
  add column if not exists bookings_made        integer default 0,
  add column if not exists bookings_rescheduled integer default 0,
  add column if not exists bookings_cancelled   integer default 0,
  add column if not exists errors               integer default 0,
  add column if not exists by_category_json     text;

-- ---------------------------------------------------------------------
-- 5) n8n_chat_histories: memory of the Postgres Chat Memory node
--    (the node can create it by itself, but we create it up front)
-- ---------------------------------------------------------------------
create table if not exists public.n8n_chat_histories (
  id         serial primary key,
  session_id varchar(255) not null,
  message    jsonb not null
);

create index if not exists n8n_chat_histories_session_idx on public.n8n_chat_histories (session_id);

-- ---------------------------------------------------------------------
-- 6) Security: block public (anon) access to these tables.
--    The n8n Supabase credential must use the service_role key,
--    which bypasses RLS, so the workflow keeps working.
-- ---------------------------------------------------------------------
alter table public.email_logs         enable row level security;
alter table public.booking_events     enable row level security;
alter table public.error_logs         enable row level security;
alter table public.daily_reports      enable row level security;
alter table public.n8n_chat_histories enable row level security;

-- ---------------------------------------------------------------------
-- 7) Check: you should see 5 rows with these column counts
--    booking_events 9, daily_reports 13, email_logs 13,
--    error_logs 7, n8n_chat_histories 3
-- ---------------------------------------------------------------------
select table_name, count(*) as columns
from information_schema.columns
where table_schema = 'public'
  and table_name in ('email_logs','booking_events','error_logs','daily_reports','n8n_chat_histories')
group by table_name
order by table_name;

