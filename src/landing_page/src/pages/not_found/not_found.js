import { DmptoolLink, Link } from '../../components/link/link';

import Footer from "../../components/footer/footer";

import "./not_found.scss";

function PageNotFound(props) {
  return (
    <div id="Dashboard">
      <header className="t_step__landing-header">
        <div className="dmptool-logo">
          <DmptoolLink withLogo='true'/>
        </div>
      </header>

      <div className="t-step__landing-title">
        <div>
          <h1 className="red">The DMP ID you were looking for could not be found!</h1>

          <p>This is the DMPTool's DMP ID registry. The registry hosts DMP ID metadata and provides landing pages for DMP IDs. If you are here then something must have gone wrong with your request.</p>
          <p>Please use the links below to return to the DMPTool or to contact us for assistance.</p>

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

export default PageNotFound;
