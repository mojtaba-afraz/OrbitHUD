"use strict";

const assert = require("node:assert/strict");
const { QuotaAlertEvaluator, THRESHOLD_PRESETS } = require("../src/quotaAlerts");

function makeGroup(pct, resetIso = "2026-11-26T15:00:00Z") {
  return {
    id: "antigravity::gemini",
    providerId: "antigravity",
    displayName: "Gemini Models",
    buckets: [
      {
        id: "gemini-5h",
        window: "5h",
        windowLabel: "5h limit",
        remainingPercentage: pct,
        remainingFraction: pct / 100,
        resetTime: resetIso,
      },
    ],
  };
}

console.log("Running Smart Quota Alerts tests...");

// 1. Threshold presets
assert.deepEqual(THRESHOLD_PRESETS, [20, 15, 10, 5]);

// 2. Baseline seeding does not fire on first snapshot, but crossing down fires once per cycle
{
  const evaluator = new QuotaAlertEvaluator();
  const cfg = { enabled: true, lowThresholdPercent: 20, notifyOnReset: true };
  const now = Date.parse("2026-11-26T12:00:00Z");

  // Seed at 50% -> no alert
  assert.equal(evaluator.evaluate([makeGroup(50)], cfg, now).length, 0);

  // Drop to 18% -> fires lowQuota once
  const low1 = evaluator.evaluate([makeGroup(18)], cfg, now);
  assert.equal(low1.length, 1);
  assert.equal(low1[0].kind, "lowQuota");
  assert.match(low1[0].title, /Low Quota: Gemini Models/);
  assert.match(low1[0].body, /18% remaining/);

  // Further drops in same cycle (12%, 5%, 0%) -> deduplicated (no spam)
  assert.equal(evaluator.evaluate([makeGroup(12)], cfg, now).length, 0);
  assert.equal(evaluator.evaluate([makeGroup(5)], cfg, now).length, 0);
  assert.equal(evaluator.evaluate([makeGroup(0)], cfg, now).length, 0);

  // Reset back to 100% -> fires quotaReset once
  const resetEv = evaluator.evaluate([makeGroup(100, "2026-11-26T20:00:00Z")], cfg, now);
  assert.equal(resetEv.length, 1);
  assert.equal(resetEv[0].kind, "quotaReset");
  assert.match(resetEv[0].title, /Quota Reset: Gemini Models/);

  // Staying at 100% -> no duplicate reset alert
  assert.equal(evaluator.evaluate([makeGroup(100, "2026-11-26T20:00:00Z")], cfg, now).length, 0);

  // Dropping again in new cycle -> fires lowQuota again
  const low2 = evaluator.evaluate([makeGroup(15, "2026-11-26T20:00:00Z")], cfg, now);
  assert.equal(low2.length, 1);
  assert.equal(low2[0].kind, "lowQuota");
}
console.log("  ✓ Low-quota threshold crossing, deduplication, and reset cycle passed");

// 3. Starting already low on launch does not spam low alert, but DOES fire reset when it recovers to 100%
{
  const evaluator = new QuotaAlertEvaluator();
  const cfg = { enabled: true, lowThresholdPercent: 20, notifyOnReset: true };

  assert.equal(evaluator.evaluate([makeGroup(8)], cfg).length, 0);
  const resetEv = evaluator.evaluate([makeGroup(100)], cfg);
  assert.equal(resetEv.length, 1);
  assert.equal(resetEv[0].kind, "quotaReset");
}
console.log("  ✓ Launch-while-low suppression and subsequent reset alert passed");

// 4. Disabled alerts and notifyOnReset=false flags respected
{
  const evaluator = new QuotaAlertEvaluator();
  const disabledCfg = { enabled: false, lowThresholdPercent: 20, notifyOnReset: true };

  assert.equal(evaluator.evaluate([makeGroup(60)], disabledCfg).length, 0);
  assert.equal(evaluator.evaluate([makeGroup(10)], disabledCfg).length, 0);
  assert.equal(evaluator.evaluate([makeGroup(100)], disabledCfg).length, 0);

  const noResetCfg = { enabled: true, lowThresholdPercent: 20, notifyOnReset: false };
  assert.equal(evaluator.evaluate([makeGroup(10)], noResetCfg).length, 1);
  assert.equal(evaluator.evaluate([makeGroup(100)], noResetCfg).length, 0);
}
console.log("  ✓ Opt-in enabled & notifyOnReset toggles passed");

console.log("✅ All Smart Quota Alerts tests passed!");
