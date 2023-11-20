import DisplayDate from '../../components/displayDate/displayDate';
import { Link } from '../../components/link/link';

function ResearchDomains(props) {
  let datasets = props?.datasets;

  if (Array.isArray(datasets) && datasets.length > 0) {
    let keywords = datasets.map((item) => item?.keyword);
    if (keywords[0] !== undefined) {
      keywords = keywords.flat().map((item) => item?.replace(/^[\d.]+\s+-\s+/i, ''));
      keywords = [...new Set(keywords)];

      return (
        <li className="comma-separated">
          <strong>Research domain:</strong>
          {keywords.map((keyword, index) => <span key={'rd' + index}>{keyword.charAt(0).toUpperCase()}{keyword.slice(1)}</span>)}
        </li>
      );
    }
  }
}

function Project(props) {
  let datasets = props?.datasets || [];
  let ethicalIssues = props?.ethical_issues_exist || 'unknown';

  return (
    <div className="t-step__content">
      <h2>Project details</h2>

      <ul className="landing-list">
        <ResearchDomains datasets={datasets}/>
        {props?.project_start &&
          <li><strong>Project Start:</strong> <span>{DisplayDate(props.project_start)}</span></li>
        }
        {props?.project_end &&
          <li><strong>Project End:</strong> <span>{DisplayDate(props.project_end)}</span></li>
        }
        {props?.created &&
          <li><strong>Created:</strong> <span>{DisplayDate(props.created, true)}</span></li>
        }
        {props?.modified &&
          <li><strong>Modified:</strong> <span>{DisplayDate(props.modified, true)}</span></li>
        }
        <li>
          <strong>Ethical issues related to data that this DMP describes?</strong>
          <span>{ethicalIssues}</span>
          {props?.ethical_issues_report &&
            <span><Link href={props.ethical_issues_report} remote='true'/></span>
          }
        </li>
      </ul>
    </div>
  );
}

export default Project;
