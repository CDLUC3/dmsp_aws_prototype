
import { DmptoolLink, Link } from '../../components/link/link';
import Footer from "../../components/footer/footer";

import Dmps from "../../components/dmps/dmps";

import "./dashboard.scss";

function Dashboard(props) {
  return (
    <div id="Dashboard">
      <header className="t_step__landing-header">
        <div className="dmptool-logo">
          <DmptoolLink withLogo='true'/>
        </div>
      </header>

      <div className="t-step__landing-title">
        <div>
          <h1 className="red">Future home of a cool dashboard.</h1>

          <p>We're not there yet, but stay tuned!</p>

          <Dmps />

          <ul>
            <li><Link href='https://dmptool.org' label='Return to the DMPTool website' remote='false'/></li>
            <li><Link href='https://dmptool.org/contact-us' label='Contact the DMPTool helpdesk' remote='false'/></li>
          </ul>
        </div>
      </div>

      <Footer/>
    </div>
  );
}

export default Dashboard;
