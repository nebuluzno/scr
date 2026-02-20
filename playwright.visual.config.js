module.exports = {
  testDir: "./visual_tests",
  timeout: 60_000,
  retries: 0,
  reporter: [["list"], ["html", {open: "never", outputFolder: "playwright-report"}]],
  snapshotPathTemplate: "{testDir}/snapshots/{arg}{ext}",
  use: {
    baseURL: "http://127.0.0.1:4000",
    viewport: {width: 1440, height: 900},
    deviceScaleFactor: 1,
    colorScheme: "dark",
    locale: "en-US",
    timezoneId: "UTC",
    animations: "disabled"
  },
  webServer: {
    command: "MIX_ENV=test mix phx.server",
    url: "http://127.0.0.1:4000",
    reuseExistingServer: true,
    timeout: 120_000
  }
};
