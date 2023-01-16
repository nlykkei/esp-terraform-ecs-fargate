function callApi(endpoint, token) {
  const headers = new Headers();
  const bearer = `Bearer ${token}`;

  headers.append("Authorization", bearer);

  const options = {
    method: "GET",
    headers: headers,
  };

  response.replaceChildren();

  logMessage("Calling API...");

  fetch(endpoint, options)
    .then((resp) => {
      console.log(resp);
      return resp.json();
    })
    .then((resp) => {
      if (resp) {
        logMessage(
          "API response: " + "\n\n" + JSON.stringify(resp, undefined, 0) + "\n"
        );
      }
      return resp;
    })
    .catch((err) => {
      logMessage("API failed");
      console.error(err);
    });
}
