// A center-detented DJ-style filter: LPF left, bypass center, HPF right.
const MIN_HZ = 40;
const MAX_HZ = 18000;
const DEADBAND = 0.025;
const LOG_RANGE = Math.log(MAX_HZ / MIN_HZ);

export function filterFromPosition(position) {
  const p = Math.max(-1, Math.min(1, Number.isFinite(position) ? position : 0));
  const amount = (Math.abs(p) - DEADBAND) / (1 - DEADBAND);
  if (amount <= 0) return { type: 0, hz: 1200 };
  return p < 0
    ? { type: 1, hz: MAX_HZ * Math.exp(-LOG_RANGE * amount) }
    : { type: 3, hz: MIN_HZ * Math.exp(LOG_RANGE * amount) };
}

export function positionFromFilter(type, cutoff) {
  const hz = Math.max(MIN_HZ, Math.min(MAX_HZ, Number.isFinite(cutoff) ? cutoff : 1200));
  if (type === 1) return -(DEADBAND + (1 - DEADBAND) * Math.log(MAX_HZ / hz) / LOG_RANGE);
  if (type === 3) return DEADBAND + (1 - DEADBAND) * Math.log(hz / MIN_HZ) / LOG_RANGE;
  return 0;
}

// Summarize the original and enabled part envelopes into the same simple bars.
// This is a visual estimate, not a reconstruction of the mixed PCM waveform.
export function waveformBars(original, parts, mask, count = 32) {
  if (!original?.length || count < 1) return [];
  return Array.from({ length: count }, (_, bar) => {
    const index = Math.min(original.length - 1, Math.floor(bar * original.length / count));
    const full = Math.max(0, Math.min(1, original[index] || 0));
    const enabled = mask === 15 || !parts || parts.length !== 4 ? full : Math.min(1, Math.sqrt(parts.reduce((sum, lane, part) => {
      const value = mask & (1 << part) ? (lane[index] || 0) : 0;
      return sum + value * value;
    }, 0)));
    return { full, enabled };
  });
}
