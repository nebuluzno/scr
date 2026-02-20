const {test, expect} = require("playwright/test");

const pages = [
  {path: "/", snapshot: "dashboard.png"},
  {path: "/tasks/new", snapshot: "tasks-new.png"},
  {path: "/metrics", snapshot: "metrics.png"},
  {path: "/tools", snapshot: "tools.png"}
];

for (const pageConfig of pages) {
  test(`visual snapshot ${pageConfig.path}`, async ({page}) => {
    await page.goto(pageConfig.path, {waitUntil: "domcontentloaded"});
    await page.waitForTimeout(1200);

    await expect(page).toHaveScreenshot(pageConfig.snapshot, {
      fullPage: false,
      // Keep CI stable across Linux/macOS font rendering differences.
      maxDiffPixelRatio: 0.05
    });
  });
}
