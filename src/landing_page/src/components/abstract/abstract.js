import { SanitizeHTML } from '../../utils';

function Abstract(props) {
  let abstract = props?.project_abstract || props.description

  return (
    <div className="t-step__content">
      <h2>Project description</h2>

      <ul className="landing-list abstract">
        <li>
          <span><SanitizeHTML html={abstract}/></span>
        </li>
      </ul>
    </div>
  );
}

export default Abstract;
