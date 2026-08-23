# Northflank free tier — what the product actually offers

Established 2026-08-23 by reading the live, signed-in Northflank web UI
on the owner's own account, plus the vendor's public pricing page and
documentation. Every claim below is labelled with how it was obtained.

- **Observed** — read off the live product for this account.
- **Primary source** — vendor's own public page.
- **Arithmetic** — derived from observed numbers; no measurement.
- **Not measured** — stated as open, never as fact.

---

## 1. The free tier cannot deploy to Asia — this is the headline

**Observed.** On *Create a project → Which region do you want to deploy
in? → All (17)*, exactly **two** of seventeen regions are selectable on
the current plan. The other fifteen carry the label
`Upgrade to pay as you go to use this region`.

| Identifier | City | Free tier |
|---|---|---|
| `us-central` | Council Bluffs, US | **selectable** |
| `europe-west` | London, UK | **selectable** |
| `southamerica-east` | Osasco, BR | upgrade required |
| `canada-central` | Toronto, CA | upgrade required |
| `us-east1` | Ashburn, US | upgrade required |
| `us-west` | The Dalles, US | upgrade required |
| `us-west-california` | Los Angeles, US | upgrade required |
| `us-east-ohio` | Columbus, US | upgrade required |
| `europe-west-zurich` | Zurich, CH | upgrade required |
| `europe-west-frankfurt` | Frankfurt, DE | upgrade required |
| `europe-west-netherlands` | Eemshaven, NL | upgrade required |
| `africa-south` | Johannesburg, ZA | upgrade required |
| `australia-southeast` | Melbourne, AU | upgrade required |
| `asia-east` | Hong Kong | upgrade required |
| `asia-south-delhi` | Delhi, IN | upgrade required |
| `asia-northeast` | **Tokyo, JP** | upgrade required |
| `asia-southeast` | Jurong West, SG | upgrade required |

### This falsifies a statement in ARCHITECTURE.md

`docs/ARCHITECTURE.md` currently reads:

> The provisional platform is **Northflank's free Sandbox tier**, in its
> Japan region, with its managed Postgres addon.

That combination does not exist. `asia-northeast` (Tokyo) is
pay-as-you-go only. The free tier is Iowa or London, and nothing else.
The architecture document needs a correction; this file does not make
it, because the choice that follows from it is the owner's.

### What it costs in latency

**Measured previously on this machine:** Tokyo 33 ms, Singapore 93 ms.

**Not measured:** Council Bluffs and London. Both are a different order
of distance from Taiwan than Tokyo, so the free tier's real latency is
an open number, not "33 ms". Do not carry the Tokyo figure forward into
any free-tier reasoning — it belongs to a region the free tier cannot
use.

This lands directly on the third of the three decisions that
`CLAUDE.md` marks as expensive to undo: *region is fixed; app and
database never split across regions*. Choosing a region is therefore
gated, and creating the free project **is** choosing one.

---

## 2. Region identifiers name the city

**Observed.** Every region row shows `identifier · City`, e.g.
`us-central · Council Bluffs`, `asia-northeast · Tokyo`. The city is not
hidden behind the identifier, so the irreversible choice can be made
with the physical location in view. Question settled.

---

## 3. Plan and quotas

**Observed**, Billing → Overview:

- Current plan: **Developer Sandbox ($0.00/mo)**.

**Primary source**, Northflank docs (*Billing → Pricing on Northflank*),
free tier allowance:

- 2 services
- 2 jobs
- 1 addon
- up to 1 BYOC cluster

**Observed**, on the create-project page:

> You can create one free project hosted on Northflank's managed cloud,
> and one on a self-hosted BYOC provider.

The docs also warn the free plan "should not be used for production
applications".

### The one number that is genuinely unpublished

**vCPU and RAM per free container are not published anywhere.** The
public pricing page has no free-tier section at all — it is pure
usage-based pricing with no free column. The docs page states the object
counts above and nothing about compute size.

The only way to obtain it is to create the free project and open a
service's compute-plan selector. **That was not done**, because creating
the project fixes the region (§1) and that is the owner's call.

---

## 4. Paid compute plans — needed for the graduation arithmetic

**Primary source**, northflank.com/pricing, *Services/Addons* tab:

| Plan | vCPU | Memory | Price per container |
|---|---|---|---|
| `nf-compute-10` | 0.1 shared | 256 MB | $2.70/mo ($0.0038/hr) |
| `nf-compute-20` | 0.2 shared | 512 MB | $5.40/mo ($0.0075/hr) |
| `nf-compute-50` | 0.5 shared | 1024 MB | $12.00/mo ($0.0167/hr) |
| `nf-compute-100-1` | 1 dedicated | 1024 MB | $18.00/mo ($0.0250/hr) |
| `nf-compute-100-2` | 1 dedicated | 2048 MB | $24.00/mo ($0.0333/hr) |
| `nf-compute-100-4` | 1 dedicated | 4096 MB | $36.00/mo ($0.0500/hr) |
| `nf-compute-200` | 2 dedicated | 4096 MB | $48.00/mo ($0.0667/hr) |
| `nf-compute-200-8` | 2 dedicated | 8192 MB | $72.00/mo ($0.1000/hr) |
| `nf-compute-400` | 4 dedicated | 8192 MB | $96.00/mo ($0.1333/hr) |

Unit pricing behind the plans: CPU **$0.01667 / vCPU / hour**, memory
**$0.00833 / GB / hour**, network egress **$0.06 / GB**, disk
**$0.15 / GB / month**.

### Budget arithmetic, not a measurement

A default Rails 8.1 production boot was **measured** on this machine at
**205.2 MiB RSS** (web + SolidQueue in one Puma process). Against that:

- `nf-compute-10` (256 MB) leaves ~50 MB of headroom for request
  handling, job execution and GC slack. Not viable.
- `nf-compute-20` (512 MB, $5.40/mo) is the realistic floor **for the
  app container alone** — before the Postgres addon, before disk, before
  the domain and mailbox.

The owner's ceiling is **US$10/month including domain and mailbox**. So
"run in Tokyo on Northflank" is not obviously inside the budget, and the
gap is not small enough to hand-wave. This is arithmetic over observed
prices; it is not a quote, and the Postgres addon's price was not
looked up.

---

## 5. Billing exposure — and a vendor widget that lies

**Observed**, Billing → Payment methods:

> No payment methods added.

**Observed**, Billing → Overview, the *Billing health* card:

> No issues. Payment method active.

**These two contradict each other, and the table is the authoritative
one** — it is the actual list of stored cards, while the health card is
a derived summary. An earlier view of the team dashboard had shown a
third wording, "No default payment method / Add a payment method to your
team to enable billing".

Treat the *Billing health* card as unreliable. Any future check of
"can this account be charged?" must read **Billing → Payment methods**,
not a summary widget.

Also observed on Billing → Overview:

- Usage this period **$0.00 of $50.00 billing limit**, described as
  "$50.00 until your next invoice, or at the end of the month —
  whichever comes first".
- Credits $0.00.
- A *Manage alerts* control exists next to Billing health.

With no card stored, the free tier remains the mechanical guarantee that
nothing can be charged — which is exactly why `CLAUDE.md` bans clicking
*Upgrade to Pay As You Go*. Note that the create-project page and the
region list both dangle that upgrade prominently; the region rows
themselves are the bait.

---

## Still open

| # | Question | Why it is still open |
|---|---|---|
| N1 | Free-tier vCPU / RAM per container | Unpublished; only visible after creating the free project, which fixes a region |
| N2 | Whether `CREATE DATABASE` is permitted on the free Postgres addon | Needs a real addon. Rails 8.1 production expects four databases (primary/cache/queue/cable) |
| N4 | Whether a paid service can coexist with the free DB addon | Not answerable without a paid resource |
| N5b | Whether free-tier workloads idle/sleep | Not stated in the docs pages read |

N2 matters more than its size suggests: a stock Rails 8.1 `database.yml`
in production declares **four** databases and supplies no `host:`, so
the app needs `DATABASE_URL`, `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`
and `CABLE_DATABASE_URL`. If the managed addon refuses `CREATE
DATABASE`, that has to be resolved before the first deploy, not after.

## Method note

The Claude browser extension was attached to a Chrome profile that was
not signed in to Northflank and had no visible window, so this session
drove a separate Chrome window at the OS level (Win32 focus + synthetic
input + full-screen capture) in the profile that *was* signed in. Worth
recording only because the same obstacle will recur: **a browser
automation tool being "connected" says nothing about which browser
profile's session it holds.**
