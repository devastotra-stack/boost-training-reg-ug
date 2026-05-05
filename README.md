# BOOST Instrument Training — Registration site

Static landing page + form for a hands-on training on **Kjeldahl protein
analysis, Soxhlet fat extraction and dietary fibre estimation (AOAC 991.43)**.
Hosted free on **GitHub Pages**. Submissions stream into a **Google Sheet**
via a **Google Apps Script** Web App. The training is free for participants;
the organisers vet each registration in the Sheet and email seat confirmation.

No paid services. No server to maintain. ₹0/month operating cost.

---

## File map

```
boost-training-reg/
├── index.html          ← landing page + registration form
├── style.css           ← Dribbble-inspired styling, mobile-responsive
├── app.js              ← form validation + POST to Apps Script
├── Code.gs             ← paste this into Apps Script editor (NOT served)
├── assets/
│   ├── kjeldahl.jpg          ← Borosil instrument photo
│   ├── fat-analyser.png      ← Borosil instrument photo
│   ├── fibre-analyser.jpg    ← Borosil instrument photo
│   └── nutrition-banner.jpg  ← Borosil nutrition lab banner
├── .github/workflows/
│   └── pages.yml       ← auto-deploy to GitHub Pages on push
├── .gitignore
└── README.md           ← this file
```

---

## Placeholders to replace before going live

Search for `REPLACE_ME` across the repo. Hits are in:

| File | Token | Meaning |
|---|---|---|
| `index.html` | `REPLACE_ME_INSTITUTE_SHORT` | short brand text in topbar (e.g. "BOOST Lab") |
| `index.html` | `REPLACE_ME_INSTITUTE` | full institute name |
| `index.html` | `REPLACE_ME_DEPARTMENT` | department |
| `index.html` | `REPLACE_ME_ADDRESS` | postal address (footer) |
| `index.html` | `REPLACE_ME_DATES` | training dates, e.g. "12–14 June 2026" |
| `index.html` | `REPLACE_ME_VENUE` | venue line |
| `index.html` | `REPLACE_ME_CONTACT_EMAIL` | queries email |
| `index.html` | `REPLACE_ME_CONTACT_PHONE` | queries phone |
| `app.js`     | `REPLACE_ME_DEPLOYMENT_ID` | Apps Script `/exec` URL (step 3) |
| `app.js`     | `REPLACE_ME_DATES` | repeated in thank-you panel |
| `Code.gs`    | `REPLACE_ME_SPREADSHEET_ID` | Sheet ID (step 2) |
| `Code.gs`    | `REPLACE_ME_ORGANISER_EMAIL` | who gets registration alerts |
| `Code.gs`    | `REPLACE_ME_DATES`, `REPLACE_ME_VENUE` | shown in confirmation email |

---

## Deploy in 6 steps

### 1. Create the Google Sheet
- Open Google Drive → **New → Google Sheets**
- Name it `BOOST Training Registrations`
- Copy the Sheet ID from the URL: `docs.google.com/spreadsheets/d/`**`<THIS_PART>`**`/edit`

### Quick path: one-shot automation

```bash
# Pre-req (one-time, in browser):
# https://script.google.com/home/usersettings → toggle Apps Script API ON
bash scripts/deploy_backend.sh
# Follow the prompt for clasp login (browser OAuth), then click Run > setup_ in
# the script editor URL it prints. Done — backend wired, app.js patched, pushed.
```

### 2. Set up Apps Script backend (manual path — only if automation fails)
- In the Sheet: **Extensions → Apps Script**
- Delete the default `Code.gs` content; paste the contents of this repo's `Code.gs`
- Edit the CONFIG block at the top:
  - `SHEET_ID` ← paste the ID from step 1
  - `NOTIFY_EMAIL` ← your email (or `""` to disable)
  - `TRAINING_DATES`, `TRAINING_VENUE` ← match what you put in `index.html`
- Click **Save** (disk icon)
- (Optional) run the `setup_` function once to pre-create the headers row;
  it will ask for permissions — approve them.

### 3. Deploy as a Web App
- In Apps Script editor: **Deploy → New deployment**
- Type: **Web app**
- Description: `boost-training-v1`
- Execute as: **Me**
- Who has access: **Anyone**
- Click **Deploy**, copy the **Web app URL** (ends in `/exec`)
- Paste that URL into `app.js` → `APPS_SCRIPT_URL`

If you later edit `Code.gs`, click **Deploy → Manage deployments → pencil icon
→ New version → Deploy** so the changes go live.

### 4. Push to GitHub
```bash
cd "C:/Users/Devastotra Poddar/Downloads/boost-training-reg"
git init
git add .
git commit -m "feat: initial BOOST training registration site"
git branch -M main
gh repo create boost-training-reg --public --source=. --push
```
(Or create the repo on github.com and push manually.)

### 5. Enable GitHub Pages
- Repo → **Settings → Pages**
- Source: **GitHub Actions**
- The included `.github/workflows/pages.yml` will deploy automatically on push.
- After ~1 minute, your site is live at
  `https://<your-username>.github.io/boost-training-reg/`

### 6. Test end-to-end
- Open the live URL in incognito
- Fill the form with dummy data, submit
- Confirm a row appears in the Sheet
- Confirm the registrant + organiser emails arrive

---

## Operations (post-launch)

- **Vet registrations:** open the Sheet; default `status` is `REGISTERED`.
  Change to `CONFIRMED` once you decide to allot a seat, or `WAITLIST` /
  `REJECTED` as needed. Email a confirmation manually or via mail-merge.
- **Cap registrations:** when the Sheet shows 25 confirmed rows, edit
  `index.html` hero CTA to "Closed — see you next batch".
- **Export attendance list:** Sheet → **File → Download → CSV**.
- **Spam protection:** Apps Script anonymous web app is rate-limited by
  Google. For extra safety you can add a hidden `honeypot` field in the
  form and reject in `Code.gs` if filled.

---

## Local preview

```bash
cd boost-training-reg
python -m http.server 8000
# open http://localhost:8000
```

The form will show "Backend URL not configured yet" until you complete step 3.

---

## Why Google Sheets and not [other backend]?

| Option | Free | Setup | Ops cost | Picked? |
|---|---|---|---|---|
| Google Sheets via Apps Script | unlimited | 5 min | spreadsheet you already use | ✅ |
| Formspree / Getform | 50/mo cap | 2 min | paid above 50 | ✗ |
| Firebase / Supabase | generous | 15 min | API key in client, more code | ✗ |
| Self-hosted Flask/FastAPI | free | 1 hour | server to maintain | ✗ |

Google Sheets wins on team collaboration: co-organisers can mark
payment status, add a "remarks" column, sort by city for car-pooling,
filter for vegetarian count for catering — all without touching code.
