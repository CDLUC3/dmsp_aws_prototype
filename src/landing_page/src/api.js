import { inDevMode } from "./utils";

export class DmpApi {

  getApiHostName() {
    return inDevMode() ? 'api.dmphub.uc3dev.cdlib.net' : `api.${window.location.hostname}`;
  }

  getUrl() {
    let version = window.location.search !== undefined ? window.location.search : '';
    version = version.replace('?', '%3F').replace('=', '%3D')
    return `https://${this.getApiHostName()}${window.location.pathname}${version}`;
  }

  getHeaders(extra_headers) {
    // NOTE: This just creates "common" headers required for the API.
    // The returned headers object can be customized further if needed by the
    // caller.
    let headers = new Headers();
    // headers.append('Content-Type', "application/x-www-form-urlencoded");
    headers.append('Accept', "application/json");
    return headers;
  }

  getOptions(options) {
    // NOTE: Returns common options required for every request. We can
    // still override any of them as required.
    let _headers = this.getHeaders();
    let _options = Object.assign({
      method: 'get',
      mode: 'cors',
      cache: 'no-cache',
      headers: _headers,
    }, options);

    return _options;
  }

  /* Use this method to deal with the API response. We'll mostly
   * use this to handle any required error logging, but we can add some
   * other common code here if needed.
   */
  handleResponse(resp) {
    switch (resp.status) {
      case 400:
      case 404:
        // TODO:: Error handling
        // TODO:: Log and report errors to a logging services
        // TODO:: Message to display to the user?
        console.log('Error fetching from API');
        console.log(resp);
        break;
      default:
        break;
    }
  }
}
