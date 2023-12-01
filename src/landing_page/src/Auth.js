import React from 'react';
import {useEffect, useState} from 'react';
import {Navigate} from "react-router-dom";
import {jwtDecode} from 'jwt-decode';

import { DmpApi } from './api';

export function Authenticate() {
  const token = useToken()

  return (
    <div className="row">
      <div className="container mt-5">
        <div className="mt-3">
          <p>Authentication</p>
          <hr/>
          {token.querying ? 'Please wait while authenticating...' : ''}
          {token.authed ? <Navigate to={`/dashboard`}/> : ''}
          {!token.querying && !token.authed ? 'Sorry, but we were unable to proceed to your authentication.' : ''}
        </div>
      </div>
    </div>
  )
}

export function Logout() {
  localStorage.removeItem('dmsp-app-jwt')

  return (
    <div className="row">
      <div className="container mt-5">
        <div className="mt-3">
          <p>Log-out</p>
          <hr/>
          You have been disconnected from the app.
        </div>
      </div>
    </div>
  )
}

export function Unauthorized() {
  return (
    <div className="row">
      <div className="container mt-5">
        <p>Access Forbidden</p>
        <hr/>
        <div className="mt-3">You are not authorized to be here.</div>
      </div>
    </div>
  )
}

export function useToken() {
  const [token, setToken] = useState({querying: true, authed: false});

  useEffect(() => {
    const authResult = new URLSearchParams(window.location.search);
    const code = authResult.get('code')
    let api = new DmpApi();

    fetch(`https://${api.getApiHostName()}/oauth_callback?code=${code}`, api.getOptions())
      .then(response => {
        api.handleResponse(response);
        return Promise.resolve(response.json())
      })
      .then(data => {
        let json = JSON.parse(data);

        // TODO: Figure out what to do with the `id_token` and `refresh_token`
        if (json && json?.access_token) {
          localStorage.setItem('dmsp-app-jwt', json?.access_token)
          setToken({querying: false, authed: true})
        } else {
          setToken({querying: false, authed: false})
        }
      })
  }, [])

  return token;
}

export function useAuth() {
    const [authenticated, setAuthenticated] = useState(false);

    useEffect(() => {
        const jwtToken = localStorage.getItem('dmsp-app-jwt')

        let isExpired = false

        if (jwtToken) {
            const decodedToken = jwtDecode(jwtToken, {complete: true});

            if (decodedToken) {
                isExpired = decodedToken.exp < new Date().getTime()
            }
        }

        setAuthenticated(isExpired)

    }, [])

    return authenticated
}
