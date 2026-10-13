# Email Support AI Agent

[English](README.md) | **বাংলা**

n8n দিয়ে বানানো একটি AI ইমেইল সাপোর্ট এজেন্ট। কাস্টমারের ইমেইল Gmail-এ এলে এজেন্ট নিজে ইমেইলটি বুঝে, ক্যাটাগরি অনুযায়ী উত্তর তৈরি করে, দরকার হলে মালিকের অনুমোদন নিয়ে পাঠায়। মিটিং বুকিং, রিশিডিউল ও ক্যানসেলও করতে পারে।

**ব্যবহৃত টুল:** n8n, Gmail, Google Drive, Google Calendar, OpenAI, Pinecone (RAG), Supabase (Postgres), Slack

---

## এই রিপোতে কী কী আছে

| ফাইল | কাজ |
|---|---|
| `schema.sql` | Supabase-এর ৫টা টেবিল বানানোর SQL |
| `gmail-intake.json` | **Workflow ১:** Gmail থেকে নতুন ইমেইল ধরে, ফিল্টার করে, প্রসেসরে পাঠায় |
| `email-support-processor.json` | **Workflow ২:** ইমেইল ক্যাটাগরাইজ করে, AI উত্তর বানায়, অনুমোদন নেয়, রিপোর্ট ও এরর হ্যান্ডলিং করে |

---

## সিস্টেম কীভাবে কাজ করে

### Workflow ১: Gmail Intake (`gmail-intake.json`)
1. **Gmail Trigger** প্রতি মিনিটে ইনবক্সের unread ইমেইল চেক করে (promotions, social, no-reply, নিজের পাঠানো ইমেইল বাদ)।
2. **Security + Duplicate Guard** প্রতিটা ইমেইল যাচাই করে: prompt-injection ধরে, sensitive শব্দ (refund, legal, password ইত্যাদি) ধরে, অটো-রিপ্লাই ও ডুপ্লিকেট ইমেইল বাদ দেয়।
3. **New Email Only?** শুধু নতুন ইমেইল এগিয়ে দেয়।
4. **1 email at a time** একটা একটা করে ইমেইল **Workflow ২-তে** পাঠায়, মাঝে ৩ সেকেন্ড বিরতি দেয় যাতে লোড না বাড়ে।

### Workflow ২: Email Support Processor (`email-support-processor.json`)
1. ইমেইল সংরক্ষণের আগে **ব্যক্তিগত তথ্য মাস্ক** করা হয় (ইমেইল, কার্ড নম্বর, পাসওয়ার্ড/টোকেন) এবং Supabase `email_logs`-এ সেভ হয়।
2. **Text Classifier** ইমেইলকে ৯ ক্যাটাগরির একটাতে ফেলে:

| ক্যাটাগরি | কে সামলায় |
|---|---|
| Company info request | Company info agent |
| Product or service inquiry | Product or service inquiry agent |
| Pricing request | Pricing agent (**মালিকের অনুমোদন লাগে**) |
| Technical support | Technical support agent |
| Complaint | Complaint agent (**মালিকের অনুমোদন লাগে**) |
| Payment or refund | **কোনো AI উত্তর নয়**, শুধু মালিকের কাছে অ্যালার্ট ইমেইল |
| Sales lead | Sales lead agent |
| Meeting request | Meeting request agent (বুক/রিশিডিউল/ক্যানসেল) |
| Other | কোনো উত্তর দেওয়া হয় না |

3. প্রতিটা এজেন্ট **Pinecone knowledge base** থেকে তথ্য খুঁজে উত্তর লেখে। তথ্য না পেলে বানিয়ে বলে না, বলে "টিমের কেউ নিশ্চিত করবে"।
4. উত্তর পরিষ্কার করে সুন্দর HTML ইমেইলে সাজানো হয়।
5. **Approval Gate:** সাধারণ ইমেইলের উত্তর অটো-সেন্ড হয়। কিন্তু Pricing, Complaint বা prompt-injection সন্দেহ থাকলে মালিকের ইমেইলে **Approve / Reject** অনুরোধ যায়।
6. প্রতিদিন রাত ৮টায় (Asia/Dhaka) মালিকের কাছে **ডেইলি রিপোর্ট** যায়।
7. কোনো এরর হলে **Slack + Gmail + Supabase**-এ জানানো হয়।
8. আলাদা একটা শাখা Google Drive ফোল্ডারে নতুন ফাইল এলে সেটা **Pinecone-এ আপলোড (embedding)** করে knowledge base আপডেট রাখে।

---

## শুরু করার আগে যা যা লাগবে

- [n8n](https://n8n.io) (cloud বা self-hosted)
- একটা Gmail অ্যাকাউন্ট (যেটাতে কাস্টমারের ইমেইল আসবে)
- Google Drive ও Google Calendar অ্যাকাউন্ট
- [OpenAI](https://platform.openai.com) API key
- [Pinecone](https://www.pinecone.io) অ্যাকাউন্ট (ফ্রি প্ল্যানেই চলবে)
- [Supabase](https://supabase.com) প্রজেক্ট
- Slack workspace (এরর অ্যালার্টের জন্য)

---

## সেটআপ (ধাপে ধাপে)

### ধাপ ১: Supabase সেটআপ

1. Supabase-এ নতুন প্রজেক্ট বানাও।
2. বাঁদিকের মেনু থেকে **SQL Editor > New query** এ যাও।
3. `schema.sql` এর পুরো কোড পেস্ট করে **Run** চাপো।
4. শেষে একটা রেজাল্ট টেবিল আসবে, সেখানে ৫টা টেবিল থাকতে হবে:
   `booking_events` (৯ কলাম), `daily_reports` (১৩), `email_logs` (১৩), `error_logs` (৭), `n8n_chat_histories` (৩)
5. **Project Settings > API** থেকে দুটো জিনিস কপি করে রাখো:
   - **Project URL**
   - **service_role key** (গোপন রাখবে, কাউকে দেখাবে না)
6. **Project Settings > Database** থেকে Postgres connection তথ্য (host, port, user, password) কপি করো। এটা Postgres Chat Memory ও Daily Stats নোডে লাগবে।

> সব টেবিলে Row Level Security চালু আছে। তাই n8n-এর Supabase credential-এ অবশ্যই **service_role key** দিতে হবে, `anon` key দিলে কাজ করবে না।

### ধাপ ২: Pinecone সেটআপ

1. Pinecone-এ নতুন **Index** বানাও, নাম দাও `emal-rag` (বা তোমার পছন্দের নাম)।
2. **Dimension** অবশ্যই embedding মডেলের সাথে মিলতে হবে:
   - `text-embedding-3-small` হলে **1536**
   - `text-embedding-3-large` হলে **3072**
3. Pinecone API key কপি করে রাখো।

### ধাপ ৩: Knowledge Base ডক বানাও

1. Google Drive-এ একটা নতুন ফোল্ডার বানাও (যেমন `email-rag`)।
2. ফোল্ডারে **Google Docs** ফরম্যাটে তোমার কোম্পানির তথ্য লেখো। দরকারি বিষয়:
   - কোম্পানি পরিচিতি, ঠিকানা, টিম
   - **অফিস সময় (খুবই জরুরি, মিটিং এজেন্ট এটা দেখে সময় দেয়)**
   - সার্ভিস ও প্রোডাক্টের বিবরণ
   - প্রাইসিং/প্যাকেজ (থাকলে)
   - পলিসি, FAQ, টেকনিক্যাল সাপোর্ট ধাপ
3. যত পরিষ্কার ও সঠিক তথ্য দেবে, AI-এর উত্তর তত ভালো হবে। ডকে যা নেই, এজেন্ট তা বলবে না।

### ধাপ ৪: n8n-এ Workflow Import

1. n8n-এ **Workflows > Add workflow > Import from file** এ যাও।
2. **প্রথমে** `email-support-processor.json` Import করো।
3. তারপর `gmail-intake.json` Import করো।

### ধাপ ৫: Credentials যোগ করো

n8n-এ **Credentials** থেকে এগুলো বানাও, তারপর প্রতিটা নোডে সংশ্লিষ্ট credential সিলেক্ট করো:

| Credential | কোথায় লাগে |
|---|---|
| Gmail OAuth2 | Gmail Trigger, Reply, Send and Wait, Owner Alert, Daily Report, Error Alert |
| Google Drive OAuth2 | New file in email-rag, Download Google Doc as PDF |
| Google Calendar OAuth2 | Check Availability, Find/Create/Reschedule/Cancel Meeting |
| OpenAI API | OpenAI Chat Model, Embeddings OpenAI |
| Pinecone API | দুটো Pinecone Vector Store নোড |
| Supabase API (**service_role key**) | সব `Supabase:` নোড ও Log Booking Action |
| Postgres | Postgres Chat Memory, Postgres: Daily Stats |
| Slack | Slack: Error Alert |

> টিপ: Workflow খুলে লাল/সতর্ক চিহ্নওয়ালা নোডগুলো একে একে খুললে বুঝবে কোথায় credential বাকি।

### ধাপ ৬: `YOUR_` লেখা জায়গাগুলো ঠিক করো

JSON-এ ব্যক্তিগত তথ্য সরিয়ে placeholder বসানো আছে। নিজের মান বসাও:

| Placeholder | কী বসাবে | কোথায় |
|---|---|---|
| `YOUR_EMAIL@example.com` | মালিকের ইমেইল | Gmail: Send Daily Report, Gmail: Error Alert |
| `YOUR_SLACK_CHANNEL_ID` | Slack চ্যানেলের ID | Slack: Error Alert |
| `YOUR_CALENDAR_ID` | Google Calendar-এর ID | মিটিংয়ের ৫টা Calendar নোড |
| `YOUR_PROCESSOR_WORKFLOW_ID` | Workflow ২-এর ID | `gmail-intake`-এর "Run Processor" নোড |

**সহজ উপায়:** placeholder খুঁজে কষ্ট না করে প্রতিটা নোড খুলে ড্রপডাউন থেকে সরাসরি সিলেক্ট করো (Calendar, Slack channel, Workflow সব ড্রপডাউনে আসে)।

### ধাপ ৭: নোডে খালি থাকা সেটিংস পূরণ করো

নিচের জিনিসগুলো সবসময় খালি থাকে, নিজে সিলেক্ট করতে হবে:

1. **OpenAI Chat Model:** মডেল সিলেক্ট করো (যেমন `gpt-4o-mini`)।
2. **New file in email-rag (Google Drive Trigger):** তোমার knowledge base ফোল্ডার সিলেক্ট করো।
3. **Pinecone Vector Store (insert মোড):** তোমার index সিলেক্ট করো এবং Options-এ **Pinecone Namespace** দাও `company_knowledge_v2`।
4. **Pinecone Vector Store1 (retrieve মোড):** একই index ও একই namespace `company_knowledge_v2` থাকতে হবে।
5. **Check Availability (Calendar):** তোমার Calendar সিলেক্ট করো।
6. **Read PDF and attach source ID** নোডে Text Splitter যুক্ত আছে কিনা দেখো (chunk size 900, overlap 150)।

> **সতর্কতা:** insert আর retrieve নোডের namespace আলাদা হলে এজেন্ট কিছুই খুঁজে পাবে না।

### ধাপ ৮: Knowledge Base আপলোড টেস্ট

1. `email-support-processor` workflow খোলো।
2. Drive ট্রিগার নোড থেকে একবার **Execute workflow** চালাও, তারপর Drive ফোল্ডারে একটা নতুন Google Doc বানাও।
3. Pinecone-এ index-এর ভেতরে vector এসেছে কিনা দেখো।

### ধাপ ৯: Error Handling চালু করো

1. `email-support-processor` workflow-এর **Settings** এ যাও।
2. **Error workflow** হিসেবে এই workflow নিজেকেই সিলেক্ট করো (যাতে Error Trigger কাজ করে)।
3. সেভ করো।

### ধাপ ১০: টেস্ট করো

1. দুটো workflow-তেই **Active** টগল চালু করো।
2. অন্য একটা ইমেইল থেকে তোমার Gmail-এ টেস্ট ইমেইল পাঠাও। এই ধরনের পাঠাও:
   - "আপনাদের অফিস কখন খোলা?" (Company info)
   - "আপনারা কী সার্ভিস দেন?" (Product inquiry)
   - "কাল বিকেল ৩টায় মিটিং বুক করতে চাই" (Meeting)
   - "টাকা ফেরত চাই" (Refund, শুধু মালিকের কাছে অ্যালার্ট যাবে)
3. Supabase `email_logs` টেবিলে সারি আসছে কিনা দেখো।
4. n8n-এর **Executions** ট্যাবে কোনো লাল এরর আছে কিনা দেখো।

> প্রথমে সাবধানে টেস্ট করো: অটো-সেন্ড চালু থাকলে সাধারণ ইমেইলে সত্যিকারের রিপ্লাই চলে যাবে।

---

## নিরাপত্তা ব্যবস্থা (বিল্ট-ইন)

- **Prompt injection ডিটেকশন:** "ignore previous instructions" ধরনের লেখা ধরা পড়লে অটো-সেন্ড বন্ধ, মালিকের অনুমোদন লাগে।
- **PII মাস্কিং:** লগে ইমেইল, কার্ড নম্বর, পাসওয়ার্ড/API key মাস্ক করে রাখা হয়।
- **Payment/Refund মালিকের হাতে:** এ ধরনের ইমেইলে AI কখনো কাস্টমারকে উত্তর দেয় না।
- **Pricing ও Complaint-এ মানুষের অনুমোদন:** AI ড্রাফট করে, মালিক Approve না করলে যায় না।
- **ডুপ্লিকেট প্রতিরোধ:** একই ইমেইল দুইবার প্রসেস হয় না।
- **অটো-রিপ্লাই ফিল্টার:** অন্য বটের ইমেইলে উত্তর দিয়ে লুপ তৈরি হয় না।
- **এজেন্টের নিয়ম:** ইমেইল ও knowledge base-এর লেখাকে "ডেটা" ধরা হয়, "নির্দেশ" নয়। দাম, নীতি বা সময় বানিয়ে বলে না।

---

## নিজের মতো কাস্টমাইজ করো

| কী বদলাতে চাও | কোথায় |
|---|---|
| কোম্পানির নাম ও কালার | `Collect Final Draft` নোডের CONFIG অংশ (`COMPANY_NAME`, `BRAND`) |
| সাইন-অফ নাম | `Collect Final Draft` নোডের `SIGN_NAME` এবং `Polish:` নোডগুলোর `SIGN_OFF` |
| এজেন্টের আচরণ | প্রতিটা Agent নোডের System Message |
| ক্যাটাগরি | `Text Classifier` নোডের categories (নতুন ক্যাটাগরি যোগ করলে নতুন আউটপুট শাখাও জুড়তে হবে) |
| কোন ক্যাটাগরি অটো-সেন্ড হবে | `Collect Final Draft` নোডের `autoSendEligible` লাইন |
| রিপোর্টের সময় ও টাইমজোন | `Schedule Trigger` (ডিফল্ট রাত ৮টা) এবং `Build Report Email` নোডের `Asia/Dhaka` |
| ইমেইল চেকের ফ্রিকোয়েন্সি | `Gmail Trigger` এর poll time |
| মিটিং ক্যালেন্ডার | মিটিংয়ের Calendar নোডগুলো |

---

## সমস্যা হলে (Troubleshooting)

| সমস্যা | সম্ভাব্য কারণ ও সমাধান |
|---|---|
| Supabase নোডে "permission denied" বা খালি রেজাল্ট | `anon` key দিয়েছো। `service_role` key দাও। |
| `schema.sql` চালানোর সময় unique index এরর | `email_logs`-এ পুরনো ডুপ্লিকেট সারি আছে। মুছে আবার চালাও। |
| AI কোম্পানির তথ্য বলতে পারছে না | Pinecone-এ ডাটা নেই, অথবা insert ও retrieve নোডের namespace/index আলাদা, অথবা dimension মেলেনি। |
| Gmail ট্রিগার কিছু ধরছে না | ইমেইলটি unread আছে কিনা দেখো। ফিল্টারে promotions/updates ক্যাটাগরি বাদ আছে। |
| একই ইমেইলের উত্তর দুবার গেছে | দুটো workflow-ই Active কিনা এবং ডুপ্লিকেট ডেটা কিনা দেখো। |
| মিটিং বুক হচ্ছে না | Calendar credential, Calendar ID এবং knowledge base-এ অফিস সময় আছে কিনা দেখো। |
| Approval ইমেইল আসছে না | Gmail credential ঠিক আছে কিনা এবং `Send message and wait for response` নোডে পাঠানোর ঠিকানা সেট আছে কিনা দেখো। |
| Postgres Memory এরর | Supabase-এর connection তথ্য ঠিক আছে কিনা এবং SSL চালু আছে কিনা দেখো। |
| Error অ্যালার্ট আসছে না | Workflow Settings-এ Error workflow সেট আছে কিনা দেখো। |
| ডেইলি রিপোর্ট আসছে না | Workflow Active কিনা, `Postgres: Daily Stats` credential আছে কিনা এবং n8n-এর টাইমজোন সেটিং দেখো। |

---

## Supabase টেবিল পরিচিতি

| টেবিল | কাজ |
|---|---|
| `email_logs` | প্রতিটা ইমেইলের রেকর্ড: ক্যাটাগরি, AI উত্তর, স্ট্যাটাস |
| `booking_events` | মিটিং বুক/রিশিডিউল/ক্যানসেলের লগ |
| `error_logs` | workflow-এর এরর রেকর্ড |
| `daily_reports` | প্রতিদিনের রিপোর্টের সারাংশ |
| `n8n_chat_histories` | এজেন্টের কথোপকথনের মেমোরি (থ্রেড অনুযায়ী) |

**`email_logs`-এর স্ট্যাটাস:** `received`, `awaiting_approval`, `auto_sending`, `replied`, `rejected`, `owner_only`, `no_reply_needed`

---

## গুরুত্বপূর্ণ নোট

- এই রিপোতে কোনো API key বা পাসওয়ার্ড নেই। নিজের credential নিজে n8n-এ যোগ করতে হবে।
- নিজের `service_role key`, API key বা ইমেইল কখনো GitHub-এ আপলোড করো না।
- প্রোডাকশনে ব্যবহারের আগে ভালোভাবে টেস্ট করো, কারণ অটো-সেন্ড সত্যিকারের কাস্টমারকে ইমেইল পাঠায়।

## লাইসেন্স

MIT License। শেখা ও নিজের প্রজেক্টে ব্যবহারের জন্য উন্মুক্ত।
