import React from 'react';
import {useEffect, useState} from 'react';
import {Navigate} from "react-router-dom";

import { DmpApi } from '../../api';

export function useDmps() {
  const [dmps, setDmps] = useState({loading: true, unauthorized: false, data: []});

  useEffect(() => {
    let api = new DmpApi();
    const headers = new Headers()

    headers.append('Authorization', `Bearer ${localStorage.getItem('dmsp-app-jwt')}`)

    fetch(`https://${api.getApiHostName()}/dmps`, api.getOptions())
      .then(response => {
        if (response.status === 401) {
          throw new Error('You are not authorized to see this content.')
        }

        return Promise.resolve(response.json())
      })
      .then(data => {
        setDmps({loading: false, unauthorized: false, data: !data || !data.length ? [] : data});
      })
      .catch(error => {
        setDmps({loading: false, unauthorized: true, data: []})
      });
  }, []);

  return dmps;
}

export function Dmps() {
  const dmps = useDmps()

  return (
    <div className="row">
      <div className="container mt-5">
        <div className="mt-3">
          {dmps.unauthorized ? <Navigate to={`/unauthorized`}/> : ''}
          <p>DMSP list</p>
          <hr/>
          {dmps.loading ? 'Pleas wait while loading your DMSPs...' : ''}
          {dmps.data.map((_dmp, key) => {
            return <h2>{key}</h2>
          })}
        </div>
      </div>
    </div>
  )
}

export default Dmps;