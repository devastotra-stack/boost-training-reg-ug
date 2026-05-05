/* ============================================================
   BOOST Training Registration (UG STUDENT PORTAL): Apps Script backend
   Deploy as Web App (Execute as: Me, Access: Anyone).
   Paste the resulting /exec URL into app.js APPS_SCRIPT_URL.
   This is a SEPARATE app from the Teacher / PhD portal: own Sheet,
   own deployment, own caps.
   ============================================================ */

// ---- CONFIG (edit these) ----
const SHEET_ID = "REPLACE_ME_UG_SPREADSHEET_ID"; // open the UG Sheet -> URL -> /d/<this>/edit
const SHEET_TAB = "UG_Registrations";
const NOTIFY_EMAIL = "devastotrapoddar@beldacollege.ac.in";
const SEND_USER_CONFIRMATION = true;
const TRAINING_DATES = "18-19 May 2026";
const TRAINING_VENUE = "Belda College, Paschim Medinipur";

// UG portal: single category, 50 seats.
const SEAT_CAPS = {
  "UG": 50
};

const HEADERS = [
  "submitted_at","name","email","phone","role","college_dept","year","city",
  "instruments","experience","notes",
  "consent","status",
  "user_agent"
];

// ---- Entry point ----
function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);

    // basic guard
    if (!body || !body.name || !body.email || !body.role) {
      return jsonOut({ ok: false, error: "Missing required fields" });
    }

    // category cap check
    const cap = SEAT_CAPS[body.role];
    if (typeof cap !== "number") {
      return jsonOut({ ok: false, error: "Invalid category. Only UG students can register on this portal." });
    }
    const sheet = openSheet_();
    const used = countCategory_(sheet, body.role);
    if (used >= cap) {
      const labels = { "UG":"UG student" };
      return jsonOut({ ok: false, error: `${labels[body.role]} seats are full (${cap}/${cap}). Please contact the organisers to join the waitlist.` });
    }

    const row = HEADERS.map(h => {
      if (h === "status") return "REGISTERED";
      return body[h] !== undefined ? body[h] : "";
    });
    sheet.appendRow(row);

    if (SEND_USER_CONFIRMATION) sendUserMail_(body);
    if (NOTIFY_EMAIL && !NOTIFY_EMAIL.startsWith("REPLACE_ME")) sendOrganiserMail_(body);

    return jsonOut({ ok: true });
  } catch (err) {
    return jsonOut({ ok: false, error: String(err) });
  }
}

function doGet() {
  // health check + live seat counts; safe to call from anywhere
  try {
    const sheet = openSheet_();
    const seats = {};
    for (const role of Object.keys(SEAT_CAPS)) {
      const used = countCategory_(sheet, role);
      seats[role] = { used: used, cap: SEAT_CAPS[role], available: Math.max(0, SEAT_CAPS[role] - used) };
    }
    return ContentService
      .createTextOutput(JSON.stringify({ ok: true, service: "boost-training-reg", time: new Date(), seats: seats }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: true, service: "boost-training-reg", time: new Date(), seats_error: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// Count rows where role matches AND status is not REJECTED/WAITLIST.
// CONFIRMED + REGISTERED both consume a seat.
function countCategory_(sheet, role) {
  const last = sheet.getLastRow();
  if (last < 2) return 0;
  const roleCol = HEADERS.indexOf("role") + 1;       // 1-indexed
  const statusCol = HEADERS.indexOf("status") + 1;
  const data = sheet.getRange(2, 1, last - 1, HEADERS.length).getValues();
  let n = 0;
  for (const r of data) {
    const rowRole = String(r[roleCol - 1] || "").trim();
    const rowStatus = String(r[statusCol - 1] || "").trim().toUpperCase();
    if (rowRole === role && rowStatus !== "REJECTED" && rowStatus !== "WAITLIST") n++;
  }
  return n;
}

// ---- Helpers ----
function openSheet_() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  let sh = ss.getSheetByName(SHEET_TAB);
  if (!sh) {
    sh = ss.insertSheet(SHEET_TAB);
    sh.appendRow(HEADERS);
    sh.getRange(1, 1, 1, HEADERS.length).setFontWeight("bold").setBackground("#f4d8b6");
    sh.setFrozenRows(1);
  } else if (sh.getLastRow() === 0) {
    sh.appendRow(HEADERS);
    sh.getRange(1, 1, 1, HEADERS.length).setFontWeight("bold").setBackground("#f4d8b6");
    sh.setFrozenRows(1);
  }
  return sh;
}

function jsonOut(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function sendUserMail_(body) {
  const subject = "Registration received: Belda College / Borosil Instrument Training";
  const text =
`Dear ${body.name},

Thank you for registering for the hands-on training on Kjeldahl, Soxhlet
and Dietary Fibre Estimation, organised by the Department of Nutrition,
Belda College, in collaboration with Borosil Scientific. The instruments
are supported through the WBDSTBT BOOST grant.

A final confirmation with seat number and joining details will be sent
within 24 hours.

Dates: ${TRAINING_DATES}
Venue: ${TRAINING_VENUE}
Instruments selected: ${body.instruments}

Registration fee: Rs 200 per participant. Online payment details
(UPI handle / bank transfer link) will be shared with you separately
by email and WhatsApp within 24 hours. Your seat is confirmed only
after the payment is received and verified.

Please bring a lab coat, safety goggles, a notebook, and your
College ID card on Day 1. Carry the payment confirmation /
screenshot for cross-checking at the registration desk.

If you did not initiate this registration, reply to this mail.

Warm regards,
Training Coordination Team`;

  try {
    MailApp.sendEmail({ to: body.email, subject: subject, body: text });
  } catch (err) {
    Logger.log("user mail failed: " + err);
  }
}

function sendOrganiserMail_(body) {
  const subject = "[BOOST training] New registration: " + body.name;
  const text =
`New registration received.

Name:         ${body.name}
Role:         ${body.role}
Institution:  ${body.institution}
City:         ${body.city}
Email:        ${body.email}
Phone:        ${body.phone}
Instruments:  ${body.instruments}
Experience:   ${body.experience}
Diet:         ${body.diet}
Notes:        ${body.notes || "(none)"}
Submitted:    ${body.submitted_at}

Open the Sheet to confirm the seat or mark as waitlist.`;

  try {
    MailApp.sendEmail({ to: NOTIFY_EMAIL, subject: subject, body: text });
  } catch (err) {
    Logger.log("organiser mail failed: " + err);
  }
}

/* Optional one-time setup helper:
   Run setup_() manually from the Apps Script editor to create the sheet
   with headers if it does not exist. */
function setup_() {
  const sh = openSheet_();
  Logger.log("Sheet ready with " + sh.getLastRow() + " rows.");
}
