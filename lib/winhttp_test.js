// WinHTTP request with full certificate validation, like SchILD_DBConfig's REST test.
// Usage (inside the bottle): cscript //nologo winhttp_test.js [port]
var port = WScript.Arguments.length > 0 ? WScript.Arguments(0) : "8443";
var url = "https://localhost:" + port + "/status/alive";
try {
  var r = new ActiveXObject("WinHttp.WinHttpRequest.5.1");
  r.SetTimeouts(5000, 5000, 5000, 5000);
  r.Open("GET", url, false);
  r.Send();
  WScript.Echo(url + " -> " + r.Status + " " + r.ResponseText);
} catch (e) {
  // 12157 = TLS/certificate failure, 12029 = cannot connect, 997 = broken runner (soda-11.0-10)
  WScript.Echo(url + " -> ERR " + (e.number & 0xFFFF));
}
