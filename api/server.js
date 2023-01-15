const express = require("express");
const morgan = require("morgan");
const passport = require("passport");
const BearerStrategy = require("passport-azure-ad").BearerStrategy;
const config = require("./config");

const PORT = process.env.PORT || 5000;

// API scope required to access /api endpoint (app registration)
const SCOPES = ["access_as_user"];

const options = {
  identityMetadata: `https://${config.metadata.authority}/${config.credentials.tenantID}/${config.metadata.version}/${config.metadata.discovery}`,
  clientID: config.credentials.clientID,
  issuer: `https://${config.metadata.authority}/${config.credentials.tenantID}/${config.metadata.version}`,
  validateIssuer: config.settings.validateIssuer,
  audience: config.credentials.audience,
  passReqToCallback: config.settings.passReqToCallback,
  loggingLevel: config.settings.loggingLevel,
  loggingNOPII: config.settings.loggingNOPII,
  scope: SCOPES,
};

const bearerStrategy = new BearerStrategy(options, function (token, done) {
  console.log("verifying token:", token);
  return done(null, {}, token);
});

passport.use(bearerStrategy);

const app = express();

// log all requests
app.use(morgan("dev"));

app.use(passport.initialize());

// enable CORS
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header(
    "Access-Control-Allow-Headers",
    "Authorization, Origin, X-Requested-With, Content-Type, Accept"
  );
  next();
});

app.get("/health", (req, res) => {
  res.status(200).json({
    health: "ok",
  });
});

app.get(
  "/api",
  passport.authenticate("oauth-bearer", { session: false }),
  (req, res) => {
    // service relies on the name claim
    res.status(200).json({
      name: req.authInfo["name"],
      "issued-by": req.authInfo["iss"],
      "issued-for": req.authInfo["aud"],
      scope: req.authInfo["scp"],
    });
  }
);

app.listen(PORT, () => {
  console.log("Listening on port " + PORT);
});

module.exports = app;
