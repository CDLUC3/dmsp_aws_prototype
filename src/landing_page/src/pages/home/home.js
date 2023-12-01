import React from 'react'
import {NavLink} from "react-router-dom";

import {useAuth} from "../../Auth";
import { DmptoolLink, Link } from '../../components/link/link';
import Footer from "../../components/footer/footer";

import {APP_CLIENT_ID, APP_REDIRECT_URI, COGNITO_BASE_URL} from "../../tmp";

import "./home.scss";

function Home() {
    const authenticated = useAuth()
    const link = `${COGNITO_BASE_URL}/login?response_type=code&client_id=${APP_CLIENT_ID}&redirect_uri=${APP_REDIRECT_URI}`

    return (
      <div id="Dashboard">
        <header className="t_step__landing-header">
          <div className="dmptool-logo">
            <DmptoolLink withLogo='true'/>
          </div>
        </header>

        <div className="t-step__landing-title">
          <div>
            <h1 className="red">Future homepage of the DMSP Prototype.</h1>

            <p>Welcome to the new experimental DMSP Prototype {authenticated ?
                  <NavLink to={`logout`}>(logout)</NavLink> : ''}</p>
              <hr/>
              {!authenticated ? <a href={link} target="_blank">Log in</a> : <ul>
                  <li>Go to: <NavLink to="/dashboard">Dashboard</NavLink>.</li>
              </ul>}
            <ul>
              <li><Link href='https://dmptool.org' label='Return to the DMPTool website' remote='false'/></li>
              <li><Link href='https://dmptool.org/contact-us' label='Contact the DMPTool helpdesk' remote='false'/></li>
            </ul>
          </div>
        </div>

        <Footer/>
      </div>
    )
}

export default Home