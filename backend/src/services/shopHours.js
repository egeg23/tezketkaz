// Phase 6.4 — pure functions for evaluating shop working hours.
//
// Inputs are fully resolved (the route loads shop + workingHours) so this
// module never touches the DB. That makes it cheap to unit-test and lets us
// reuse it from anywhere — order create, estimate, listings.
//
// Tashkent is UTC+5 year-round (no DST). We treat startsAt/endsAt as local
// HH:MM in Tashkent and compute via a fixed offset; if Uzbekistan ever
// adopts DST we'll switch to a tz-aware library.

const TASHKENT_OFFSET_MINUTES = 5 * 60;
const MS_PER_MINUTE = 60 * 1000;
const MS_PER_DAY = 24 * 60 * MS_PER_MINUTE;

// Convert a UTC Date → { year, month, day, dow, minutes } in Tashkent local
// time. `dow` matches JS Date.getDay(): 0=Sunday..6=Saturday. `minutes` is
// minutes since local 00:00.
function toTashkent(date) {
  const t = new Date(date.getTime() + TASHKENT_OFFSET_MINUTES * MS_PER_MINUTE);
  return {
    // Use getUTC* on the shifted date — that gives us the components as if
    // they were local Tashkent time.
    year: t.getUTCFullYear(),
    month: t.getUTCMonth(),
    day: t.getUTCDate(),
    dow: t.getUTCDay(),
    minutes: t.getUTCHours() * 60 + t.getUTCMinutes(),
  };
}

// Parse an "HH:MM" string into total minutes since 00:00. Returns null on
// invalid input.
function parseHHMM(s) {
  if (typeof s !== 'string') return null;
  const m = /^(\d{1,2}):(\d{1,2})$/.exec(s.trim());
  if (!m) return null;
  const hh = parseInt(m[1], 10);
  const mm = parseInt(m[2], 10);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  if (hh < 0 || hh > 24 || mm < 0 || mm > 59) return null;
  return hh * 60 + mm;
}

// Build a Date corresponding to a Tashkent-local civil date+time.
//   y, m, d are calendar values; minutes is offset from 00:00 local.
function tashkentLocalToUtc(y, m, d, minutes) {
  // Tashkent 00:00 on (y,m,d) corresponds to UTC (y,m,d,minute = -offset).
  // We construct via UTC components then subtract the offset.
  const utcMs = Date.UTC(y, m, d, 0, 0, 0, 0) + (minutes - TASHKENT_OFFSET_MINUTES) * MS_PER_MINUTE;
  return new Date(utcMs);
}

// Internal: does the row cover this Tashkent-local minute?
function rowCoversMinute(row, minutes) {
  if (!row) return false;
  if (row.isClosed) return false;
  const s = parseHHMM(row.startsAt);
  const e = parseHHMM(row.endsAt);
  if (s == null || e == null) return false;

  if (e === s) {
    // Treat zero-length window as closed to avoid surprising "open all day"
    // semantics if someone enters identical times.
    return false;
  }
  if (e > s) {
    // Same-day window — half-open [s, e).
    return minutes >= s && minutes < e;
  }
  // Cross-midnight: only the early-morning slice belongs to *next* day; this
  // function checks the same-day late slice (s..end-of-day).
  return minutes >= s;
}

// Internal: for a cross-midnight row from the *previous* day, does it cover
// `minutes` of today?
function prevDayRowCoversMinute(row, minutes) {
  if (!row) return false;
  if (row.isClosed) return false;
  const s = parseHHMM(row.startsAt);
  const e = parseHHMM(row.endsAt);
  if (s == null || e == null) return false;
  if (e >= s) return false; // same-day rows don't bleed into next day.
  return minutes < e;
}

function rowsForDow(workingHours, dow) {
  return (workingHours || []).filter((r) => r && r.dayOfWeek === dow);
}

/**
 * Is the shop open at the given instant?
 *
 * @param {{id?: string, workingHours: Array<{dayOfWeek:number, startsAt:string, endsAt:string, isClosed?:boolean}>}} shopWithHours
 * @param {Date} [at]  Defaults to now.
 * @returns {boolean}
 */
function isOpenNow(shopWithHours, at = new Date()) {
  if (!shopWithHours) return true;
  // No schedule rows yet (legacy shops, freshly seeded test fixtures) — treat
  // as always open so we don't break the legacy flow. Once the shop sets
  // hours, those become authoritative.
  if (!Array.isArray(shopWithHours.workingHours) || shopWithHours.workingHours.length === 0) {
    return true;
  }
  const hours = shopWithHours.workingHours;

  const here = toTashkent(at);
  const todayRows = rowsForDow(hours, here.dow);
  for (const r of todayRows) {
    if (rowCoversMinute(r, here.minutes)) return true;
  }
  // Previous Tashkent day might wrap past midnight into our current minute.
  const prevDow = (here.dow + 6) % 7;
  const prevRows = rowsForDow(hours, prevDow);
  for (const r of prevRows) {
    if (prevDayRowCoversMinute(r, here.minutes)) return true;
  }
  return false;
}

/**
 * Date of next opening, scanning up to 7 days ahead (one full cycle).
 *
 * @param {object} shopWithHours
 * @param {Date} [fromDate]
 * @returns {Date|null}  null if no working hours rows are defined (caller
 *   should treat as "no schedule yet" — UI can show "schedule TBD").
 */
function nextOpenAt(shopWithHours, fromDate = new Date()) {
  if (!shopWithHours || !Array.isArray(shopWithHours.workingHours)) return null;
  const hours = shopWithHours.workingHours;
  if (hours.length === 0) return null;

  const start = toTashkent(fromDate);

  // Scan today first (skipping any window that already ended), then up to
  // 7 days ahead.
  for (let offset = 0; offset <= 7; offset++) {
    // Compute the Tashkent calendar date for "today + offset".
    const baseUtcMs = Date.UTC(start.year, start.month, start.day) + offset * MS_PER_DAY;
    const baseDate = new Date(baseUtcMs);
    // dow for that date — getUTCDay on a UTC-midnight value gives the local
    // Tashkent dow (since we constructed it from Tashkent components).
    const dow = baseDate.getUTCDay();
    const rows = rowsForDow(hours, dow);

    // Sort earliest-start first so we pick the first opening of the day.
    const sorted = rows
      .map((r) => ({ row: r, start: parseHHMM(r.startsAt) }))
      .filter((x) => x.row && !x.row.isClosed && x.start != null)
      .sort((a, b) => a.start - b.start);

    for (const { row, start: s } of sorted) {
      const candidate = tashkentLocalToUtc(start.year, start.month, start.day + offset, s);
      if (candidate.getTime() > fromDate.getTime()) {
        return candidate;
      }
    }
  }
  return null;
}

module.exports = {
  isOpenNow,
  nextOpenAt,
  TASHKENT_OFFSET_MINUTES,
  // Exposed for tests + future reuse.
  parseHHMM,
};
