# Email Support AI Agent

**English** | [বাংলা](README.bn.md)

An AI-powered email support agent built with n8n. When a customer email arrives in Gmail, the agent understands it, classifies it, drafts a reply using your company knowledge base, and sends it (with owner approval where needed). It can also book, reschedule and cancel meetings.

**Tech stack:** n8n, Gmail, Google Drive, Google Calendar, OpenAI, Pinecone (RAG), Supabase (Postgres), Slack

---

## What is in this repo

| File | Purpose |
|---|---|
| `schema.sql` | SQL that creates the 5 Supabase tables |
| `gmail-intake.json` | **Workflow 1:** picks up new Gmail emails, filters them, and hands them to the processor |
| `email-support-processor.json` | **Workflow 2:** classifies emails, drafts AI replies, handles approvals, daily reports and errors |

---

## How it works

### Workflow 1: Gmail Intake (`gmail-intake.json`)
1. **Gmail Trigger** checks the inbox every minute for unread emails (promotions, social, no-reply and your own emails are excluded).
2. **Security + Duplicate Guard** checks each email: detects prompt-injection attempts, flags sensitive words (refund, legal, password, etc.), and skips auto-replies and duplicates.
3. **New Email Only?** lets only new emails through.
4. **1 email at a time** sends emails one by one to **Workflow 2**, with a 3-second pause between them to keep the load low.

### Workflow 2: Email Support Processor (`email-support-processor.json`)
1. Personal data is **masked** (emails, card numbers, passwords/tokens) before the email is saved to Supabase `email_logs`.
2. A **Text Classifier** puts the email into one of 9 categories:

| Category | Handled by |
|---|---|
| Company info request | Company info agent |
| Product or service inquiry | Product or service inquiry agent |
| Pricing request | Pricing agent (**owner approval required**) |
| Technical support | Technical support agent |
| Complaint | Complaint agent (**owner approval required**) |
| Payment or refund | **No AI reply.** Owner gets an alert email only |
| Sales lead | Sales lead agent |
| Meeting request | Meeting request agent (book / reschedule / cancel) |
| Other | No reply is sent |

3. Each agent searches the **Pinecone knowledge base** before answering. If the information is not there, it does not make anything up. It says a team member will confirm.
4. The reply is cleaned up and wrapped in a styled HTML email.
5. **Approval gate:** normal replies are sent automatically. Pricing, Complaint, or suspected prompt-injection emails send an **Approve / Reject** request to the owner first.
6. A **daily report** is emailed to the owner every day at 8 PM (Asia/Dhaka).
7. Any error is reported to **Slack + Gmail + Supabase**.
8. A separate branch watches a Google Drive folder and **uploads new documents to Pinecone** (embeddings) to keep the knowledge base up to date.

---

## Prerequisites

- [n8n](https://n8n.io) (cloud or self-hosted)
- A Gmail account (where customer emails arrive)
- Google Drive and Google Calendar access
- An [OpenAI](https://platform.openai.com) API key
- A [Pinecone](https://www.pinecone.io) account (the free plan works)
- A [Supabase](https://supabase.com) project
- A Slack workspace (for error alerts)

---

## Setup (step by step)

### Step 1: Set up Supabase

1. Create a new Supabase project.
2. Go to **SQL Editor > New query**.
3. Paste the full contents of `schema.sql` and click **Run**.
4. A result table should appear listing 5 tables:
   `booking_events` (9 columns), `daily_reports` (13), `email_logs` (13), `error_logs` (7), `n8n_chat_histories` (3)
5. From **Project Settings > API**, copy:
   - **Project URL**
   - **service_role key** (keep it secret, never share it)
6. From **Project Settings > Database**, copy the Postgres connection details (host, port, user, password). You need these for the Postgres Chat Memory and Daily Stats nodes.

> Row Level Security is enabled on all tables, so the n8n Supabase credential **must use the `service_role` key**. The `anon` key will not work.

### Step 2: Set up Pinecone

1. Create a new **Index** named `emal-rag` (or your own name).
2. The **dimension** must match your embedding model:
   - `text-embedding-3-small` → **1536**
   - `text-embedding-3-large` → **3072**
3. Copy your Pinecone API key.

### Step 3: Create your knowledge base documents

1. Create a folder in Google Drive (for example `email-rag`).
2. Add **Google Docs** with your company information. Important topics:
   - Company overview, address, team
   - **Office hours** (very important: the meeting agent uses them to offer times)
   - Services and products
   - Pricing or packages (if any)
   - Policies, FAQs, technical support steps
3. The clearer and more accurate your documents are, the better the replies. The agent will not state anything that is not in the documents.

### Step 4: Import the workflows into n8n

1. In n8n, go to **Workflows > Add workflow > Import from file**.
2. Import `email-support-processor.json` **first**.
3. Then import `gmail-intake.json`.

### Step 5: Add credentials

Create these in n8n **Credentials**, then select them in the matching nodes:

| Credential | Used by |
|---|---|
| Gmail OAuth2 | Gmail Trigger, Reply, Send and Wait, Owner Alert, Daily Report, Error Alert |
| Google Drive OAuth2 | New file in email-rag, Download Google Doc as PDF |
| Google Calendar OAuth2 | Check Availability, Find / Create / Reschedule / Cancel Meeting |
| OpenAI API | OpenAI Chat Model, Embeddings OpenAI |
| Pinecone API | Both Pinecone Vector Store nodes |
| Supabase API (**service_role key**) | All `Supabase:` nodes and Log Booking Action |
| Postgres | Postgres Chat Memory, Postgres: Daily Stats |
| Slack | Slack: Error Alert |

> Tip: open the workflow and click through the nodes with a red or warning icon to find where a credential is still missing.

### Step 6: Replace the `YOUR_` placeholders

Personal details were removed from the JSON and replaced with placeholders. Put your own values in:

| Placeholder | What to put | Where |
|---|---|---|
| `YOUR_EMAIL@example.com` | Owner's email address | Gmail: Send Daily Report, Gmail: Error Alert |
| `YOUR_SLACK_CHANNEL_ID` | Slack channel ID | Slack: Error Alert |
| `YOUR_CALENDAR_ID` | Google Calendar ID | The 5 meeting Calendar nodes |
| `YOUR_PROCESSOR_WORKFLOW_ID` | ID of Workflow 2 | "Run Processor" node in `gmail-intake` |

**Easy way:** instead of editing text, open each node and pick the value from its dropdown (Calendar, Slack channel and Workflow all appear in dropdowns).

### Step 7: Fill in settings that are empty in the JSON

These are always blank after import and must be selected manually:

1. **OpenAI Chat Model:** choose a model (for example `gpt-4o-mini`).
2. **New file in email-rag (Google Drive Trigger):** select your knowledge base folder.
3. **Pinecone Vector Store (insert mode):** select your index and set **Pinecone Namespace** to `company_knowledge_v2` in Options.
4. **Pinecone Vector Store1 (retrieve mode):** same index and the same namespace `company_knowledge_v2`.
5. **Check Availability (Calendar):** select your calendar.
6. **Read PDF and attach source ID:** make sure the Text Splitter is connected (chunk size 900, overlap 150).

> **Warning:** if the insert and retrieve nodes use different namespaces, the agent will find nothing.

### Step 8: Test the knowledge base upload

1. Open the `email-support-processor` workflow.
2. Execute the Drive trigger once, then create a new Google Doc in your Drive folder.
3. Check Pinecone to confirm vectors were added to the index.

### Step 9: Enable error handling

1. Open the **Settings** of the `email-support-processor` workflow.
2. Set **Error workflow** to this same workflow so the Error Trigger works.
3. Save.

### Step 10: Test everything

1. Switch both workflows to **Active**.
2. From another email address, send test emails to your Gmail, for example:
   - "What are your office hours?" (Company info)
   - "What services do you offer?" (Product inquiry)
   - "I'd like to book a meeting tomorrow at 3 PM" (Meeting)
   - "I want a refund" (Refund: only the owner gets an alert)
3. Check that rows appear in the Supabase `email_logs` table.
4. Check the n8n **Executions** tab for red errors.

> Test carefully: with auto-send on, normal emails get a real reply.

---

## Built-in safety features

- **Prompt-injection detection:** text like "ignore previous instructions" disables auto-send and requires owner approval.
- **PII masking:** emails, card numbers and passwords/API keys are masked in logs.
- **Payment/refund stays with the owner:** the AI never replies to these customers.
- **Human approval for Pricing and Complaint:** the AI drafts, the owner approves before anything is sent.
- **Duplicate protection:** the same email is never processed twice.
- **Auto-reply filter:** prevents reply loops with other bots.
- **Agent rules:** emails and knowledge base text are treated as data, not instructions. The agent never invents prices, policies or hours.

---

## Customize it

| What to change | Where |
|---|---|
| Company name and brand color | CONFIG section of the `Collect Final Draft` node (`COMPANY_NAME`, `BRAND`) |
| Sign-off name | `SIGN_NAME` in `Collect Final Draft` and `SIGN_OFF` in the `Polish:` nodes |
| Agent behavior | System Message of each Agent node |
| Categories | Categories in the `Text Classifier` node (a new category also needs a new output branch) |
| Which categories auto-send | The `autoSendEligible` line in `Collect Final Draft` |
| Report time and timezone | `Schedule Trigger` (default 8 PM) and `Asia/Dhaka` in `Build Report Email` |
| How often Gmail is checked | Poll time in `Gmail Trigger` |
| Meeting calendar | The meeting Calendar nodes |

---

## Troubleshooting

| Problem | Likely cause and fix |
|---|---|
| Supabase node shows "permission denied" or empty results | You used the `anon` key. Use the `service_role` key. |
| Unique index error when running `schema.sql` | Old duplicate rows exist in `email_logs`. Delete them and run again. |
| AI can't answer company questions | No data in Pinecone, or insert and retrieve nodes use different namespace/index, or the dimension doesn't match. |
| Gmail trigger picks up nothing | Check that the email is unread. The filter excludes promotions/updates categories. |
| Same email got two replies | Check both workflows are not duplicated and that duplicate protection is working. |
| Meetings are not being booked | Check the Calendar credential, Calendar ID, and that office hours are in the knowledge base. |
| Approval email does not arrive | Check the Gmail credential and the recipient on the `Send message and wait for response` node. |
| Postgres Memory error | Check the Supabase connection details and that SSL is enabled. |
| Error alerts not arriving | Check the Error workflow is set in Workflow Settings. |
| Daily report not arriving | Check the workflow is Active, the `Postgres: Daily Stats` credential, and the n8n timezone setting. |

---

## Supabase tables

| Table | Purpose |
|---|---|
| `email_logs` | Record of every email: category, AI reply, status |
| `booking_events` | Log of booked / rescheduled / cancelled meetings |
| `error_logs` | Workflow error records |
| `daily_reports` | Summary of each daily report |
| `n8n_chat_histories` | Agent conversation memory (per email thread) |

**`email_logs` statuses:** `received`, `awaiting_approval`, `auto_sending`, `replied`, `rejected`, `owner_only`, `no_reply_needed`

---

## Important notes

- This repo contains no API keys or passwords. Add your own credentials in n8n.
- Never upload your own `service_role key`, API keys or personal email to GitHub.
- Test thoroughly before using in production, because auto-send emails real customers.

## License

MIT License. Free to use for learning and in your own projects.
