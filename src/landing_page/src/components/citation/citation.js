import { Link } from '../../components/link/link';

const INVESTIGATOR_ROLE_REGEX = /https?:\/\/credit\.niso\.org\/contributor-roles\/investigation/i;

function currentYear() {
  new Date().getFullYear();
}

function investigatorNames(persons) {
  let names = persons.filter((item) => item?.role?.some((e) => INVESTIGATOR_ROLE_REGEX.test(e))).map((item) => item.name);
  return names.join(', ')
}

function Citation(props) {
  let dmp_id = props?.dmp_id || {};
  let title = props?.title;
  let created = props?.created;
  let persons = props?.persons || [];
  let dmptoolName = props?.dmptoolName || 'DMPTool';

  let year = created === undefined ? currentYear() : new Date(Date.parse(created))?.toDateString()?.split(' ')[3];

  if (dmp_id !== undefined && title !== undefined && year !== undefined && Array.isArray(persons) && persons.length > 0) {
    let investigators = investigatorNames(persons);

    if (investigators.length > 0) {
      return (
        <div className="t-step__content">
          <h2>Citation</h2>

          <ul className="landing-list citation">
            <li><strong>When citing this DMP use:</strong></li>
            <li className="margin10 period-separated">
              <span>{investigators}</span>
              <span>({year})</span>
              <span>"{title}"</span>
              <span>[Data Management Plan]</span>
              <span>{dmptoolName}</span>
              <Link href={dmp_id}/>
            </li>
          </ul>
          <ul className="landing-list">
            <li>
              <strong>When connecting to this DMP to related project outputs (such as datasets) use the ID:</strong><br/>
              <Link href={dmp_id}/>
            </li>
          </ul>
        </div>
      );
    }
  }
}

export default Citation;
