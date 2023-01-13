const express = require("express");
const morgan = require("morgan");
const path = require("path");
const fs = require("fs");
const fetch = require("node-fetch");

const PORT = process.env.PORT || 8080;
const APP_URL = process.env.APP_URL || "localhost";
const API_URL = process.env.API_URL || "localhost";

const app = express();

// log all requests
app.use(morgan("dev"));

app.get("/health", (req, res) => {
  res.status(200).json({
    health: "ok",
  });
});

app.get("/authConfig.js", function (req, res) {
  fs.readFile(
    path.join(__dirname, "static", "authConfig.js"),
    "utf8",
    function (err, data) {
      if (err) {
        res.sendStatus(404);
      } else {
        let result;
        result = data.replace(/<APP_URL>/g, APP_URL);
        res.send(result);
      }
    }
  );
});

app.get("/api", function (req, res) {
  fetch(API_URL, {
    method: "GET",
    headers: { Authorization: req.headers["authorization"] },
  })
    .then((resp) => {
      console.log(resp);
      return resp.json();
    })
    .then((json) => {
      res.status(200).send(json);
    })
    .catch((err) => {
      console.log(err);
      res.sendStatus(500).end();
    });
});

// static files
app.use(express.static("static"));

// wildcard route for index.html
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "static", "/index.html"));
});

app.listen(PORT, () => {
  console.log("Listening on port " + PORT);
});

console.log(`SECRET = ${process.env.SECRET}`);

module.exports = app;
