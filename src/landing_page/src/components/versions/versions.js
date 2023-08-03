import { inDevMode } from '../../utils';
import DisplayDate from '../displayDate/displayDate';

function versionHostname(url, latest) {
  let target = inDevMode() ? url?.replace('https://dmphub.uc3dev.cdlib.net', 'http://localhost:3000') : url
  target = target.replace(`?version=${latest}`, '')
  return target;
}

function Versions(props) {
  let versions = props?.versions || [];
  let current = props?.currentVersion;

  // Filter out the current version number and then sort descending
  versions = versions.filter((obj) => obj?.timestamp !== current)
                     .sort((a, b) => a?.timestamp > b?.timestamp ? -1 : (a?.timestamp < b?.timestamp ? 1 : 0) );

  let latest = current > versions[0]?.timestamp ? current : versions[0]?.timestamp;

  if (current !== '') {
    if (Array.isArray(versions) && versions.length > 0) {
      return (
        <li>
          <div className="dropdown">
            <strong>Version:</strong> <button className="dropbtn">{DisplayDate(current, true)} <span className="arrow down"></span></button>
            <div className="dropdown-content">
              {versions.map((version, idx) => (
                <a href={versionHostname(version?.url, latest)} key={'ver' + idx}>{DisplayDate(version?.timestamp, true)}</a>
              ))}
            </div>
          </div>
        </li>
      );
    } else {
      return (
        <li><strong>Version:</strong> {DisplayDate(current)}</li>
      );
    }
  }
}

export default Versions;
