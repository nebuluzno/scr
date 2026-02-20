const baseConfig = require("./playwright.visual.config");

const {webServer, ...ciConfig} = baseConfig;

module.exports = ciConfig;
