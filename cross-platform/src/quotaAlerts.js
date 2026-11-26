"use strict";

const THRESHOLD_PRESETS = [20, 15, 10, 5];

function clampThreshold(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 20;
  return Math.min(Math.max(Math.round(n), 1), 99);
}

function parseResetTimeMs(resetTime) {
  if (!resetTime) return null;
  if (typeof resetTime === "number" && Number.isFinite(resetTime)) {
    return resetTime;
  }
  const ms = Date.parse(String(resetTime));
  return Number.isFinite(ms) ? ms : null;
}

function formatResetDuration(resetTimeMs, nowMs) {
  if (!resetTimeMs) return null;
  const totalSeconds = Math.floor((resetTimeMs - nowMs) / 1000);
  if (totalSeconds <= 0) return "soon";
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  if (days > 0) return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
  if (hours > 0) return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  return `${Math.max(minutes, 1)}m`;
}

function resolveWindowLabel(bucket) {
  if (bucket && typeof bucket.windowLabel === "string" && bucket.windowLabel.trim()) {
    return bucket.windowLabel.trim();
  }
  const w = String(bucket?.window || "").toLowerCase();
  if (w === "weekly") return "Weekly limit";
  if (w === "5h" || w === "5hr" || w === "five_hour") return "5h limit";
  if (w === "daily") return "Daily limit";
  return bucket?.window ? `${bucket.window} limit` : bucket?.displayName || "Quota";
}

function resolveRemainingPercent(bucket) {
  if (typeof bucket?.remainingPercentage === "number" && Number.isFinite(bucket.remainingPercentage)) {
    return Math.min(Math.max(Math.round(bucket.remainingPercentage), 0), 100);
  }
  if (typeof bucket?.remainingFraction === "number" && Number.isFinite(bucket.remainingFraction)) {
    return Math.min(Math.max(Math.round(bucket.remainingFraction * 100), 0), 100);
  }
  return 100;
}

/**
 * Pure, deterministic quota alert evaluator with baseline seeding and per-reset-cycle deduplication.
 * Mirrors `Sources/Core/QuotaAlertEvaluator.swift` for 100% cross-platform parity.
 */
class QuotaAlertEvaluator {
  constructor() {
    this.states = new Map();
  }

  reset() {
    this.states.clear();
  }

  /**
   * @param {Array} groups Visible & enabled quota groups
   * @param {{ enabled?: boolean, lowThresholdPercent?: number, notifyOnReset?: boolean }} config
   * @param {number} [nowMs]
   * @returns {Array<{ id: string, kind: "lowQuota" | "quotaReset", groupId: string, bucketId: string, title: string, body: string }>}
   */
  evaluate(groups, config = {}, nowMs = Date.now()) {
    const events = [];
    const enabled = Boolean(config.enabled);
    const threshold = clampThreshold(config.lowThresholdPercent ?? 20);
    const notifyOnReset = config.notifyOnReset !== false;

    if (!Array.isArray(groups)) return events;

    for (const group of groups) {
      if (!group || !Array.isArray(group.buckets)) continue;
      for (const bucket of group.buckets) {
        if (!bucket) continue;
        const groupId = String(group.id || group.displayName || "group");
        const bucketId = String(bucket.id || bucket.window || "bucket");
        const key = `${groupId}::${bucketId}`;
        const pct = resolveRemainingPercent(bucket);
        const resetMs = parseResetTimeMs(bucket.resetTime);

        const prev = this.states.get(key);
        if (!prev) {
          // Seed baseline without firing a launch alert; preserve wasLowOrExhausted for reset alerts
          this.states.set(key, {
            lastPercentage: pct,
            lastResetMs: resetMs,
            hasAlertedLowInCycle: pct <= threshold,
            wasLowOrExhausted: pct <= threshold,
          });
          continue;
        }

        const cycleAdvanced =
          prev.lastResetMs !== null &&
          resetMs !== null &&
          resetMs - prev.lastResetMs > 600 * 1000;

        if (cycleAdvanced) {
          prev.hasAlertedLowInCycle = false;
        }

        const windowLabel = resolveWindowLabel(bucket);

        // 1. Check Reset-to-100% notification
        if (pct >= 100) {
          if (enabled && notifyOnReset && prev.wasLowOrExhausted && prev.lastPercentage < 100) {
            events.push({
              id: `reset::${key}::${Math.floor(nowMs / 1000)}`,
              kind: "quotaReset",
              groupId,
              bucketId,
              title: `Quota Reset: ${group.displayName || groupId}`,
              body: `${windowLabel} is back to 100% remaining.`,
            });
          }
          prev.hasAlertedLowInCycle = false;
          prev.wasLowOrExhausted = false;
        } else if (pct <= threshold) {
          // 2. Check Low-Quota notification (deduplicated per cycle)
          const crossedDown = prev.lastPercentage > threshold || cycleAdvanced;
          if (enabled && !prev.hasAlertedLowInCycle && crossedDown) {
            const dur = formatResetDuration(resetMs, nowMs);
            const resetSuffix = dur ? ` · Resets in ${dur}` : "";
            events.push({
              id: `low::${key}::${Math.floor(nowMs / 1000)}`,
              kind: "lowQuota",
              groupId,
              bucketId,
              title: `Low Quota: ${group.displayName || groupId}`,
              body: `${windowLabel} is at ${pct}% remaining${resetSuffix}`,
            });
            prev.hasAlertedLowInCycle = true;
          }
          prev.wasLowOrExhausted = true;
        }

        prev.lastPercentage = pct;
        if (resetMs !== null) {
          prev.lastResetMs = resetMs;
        }
        this.states.set(key, prev);
      }
    }

    return events;
  }
}

module.exports = {
  THRESHOLD_PRESETS,
  QuotaAlertEvaluator,
};
