"use strict";

/**
 * Checks whether a window rectangle has a meaningful visible intersection with
 * at least one active display's workArea (or bounds fallback).
 */
function isRectVisibleOnDisplays(rect, displays, minVisibleWidth = 64, minVisibleHeight = 40) {
  if (
    !rect ||
    !Number.isFinite(rect.x) ||
    !Number.isFinite(rect.y) ||
    !Number.isFinite(rect.width) ||
    !Number.isFinite(rect.height) ||
    rect.width <= 0 ||
    rect.height <= 0
  ) {
    return false;
  }

  if (!Array.isArray(displays) || displays.length === 0) {
    return false;
  }

  const reqW = Math.min(rect.width, minVisibleWidth);
  const reqH = Math.min(rect.height, minVisibleHeight);

  return displays.some((display) => {
    const area = display && (display.workArea || display.bounds);
    if (
      !area ||
      !Number.isFinite(area.x) ||
      !Number.isFinite(area.y) ||
      !Number.isFinite(area.width) ||
      !Number.isFinite(area.height)
    ) {
      return false;
    }

    const overlapX =
      Math.min(rect.x + rect.width, area.x + area.width) -
      Math.max(rect.x, area.x);
    const overlapY =
      Math.min(rect.y + rect.height, area.y + area.height) -
      Math.max(rect.y, area.y);

    return overlapX >= reqW && overlapY >= reqH;
  });
}

/**
 * Computes the default top-right position on the primary display workArea.
 */
function getDefaultWindowPosition(width, height, primaryDisplay) {
  const workArea = (primaryDisplay && (primaryDisplay.workArea || primaryDisplay.bounds)) || {
    x: 0,
    y: 0,
    width: 1440,
    height: 900,
  };

  const maxX = workArea.x + Math.max(0, workArea.width - width);
  const maxY = workArea.y + Math.max(0, workArea.height - height);

  const defaultX = Math.max(workArea.x, Math.min(workArea.x + workArea.width - width - 28, maxX));
  const defaultY = Math.max(workArea.y, Math.min(workArea.y + 40, maxY));

  return { x: Math.round(defaultX), y: Math.round(defaultY) };
}

/**
 * Validates saved (x, y) against all active displays and falls back to the
 * primary display's default position when off-screen or invalid.
 */
function resolveWindowPosition({
  savedX,
  savedY,
  width,
  height,
  displays,
  primaryDisplay,
}) {
  if (
    Number.isFinite(savedX) &&
    Number.isFinite(savedY) &&
    isRectVisibleOnDisplays({ x: savedX, y: savedY, width, height }, displays)
  ) {
    return { x: Math.round(savedX), y: Math.round(savedY), wasReset: false };
  }

  const fallback = getDefaultWindowPosition(width, height, primaryDisplay);
  return { x: fallback.x, y: fallback.y, wasReset: true };
}

module.exports = {
  isRectVisibleOnDisplays,
  getDefaultWindowPosition,
  resolveWindowPosition,
};
