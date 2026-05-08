// Tiny duration parser supporting jwt-style strings: "1h", "30d", "15m", "10s".
// Returns milliseconds. Falls back to numeric input as ms.

const RE = /^(\d+)\s*(ms|s|m|h|d|w|y)?$/i;
const UNITS = {
  ms: 1,
  s: 1000,
  m: 60_000,
  h: 3_600_000,
  d: 86_400_000,
  w: 604_800_000,
  y: 31_557_600_000,
};

function ms(input) {
  if (typeof input === 'number') return input;
  if (typeof input !== 'string') throw new TypeError('ms() expects string or number');
  const m = RE.exec(input.trim());
  if (!m) throw new Error(`Invalid duration: ${input}`);
  const n = Number(m[1]);
  const unit = (m[2] || 'ms').toLowerCase();
  return n * UNITS[unit];
}

module.exports = ms;
