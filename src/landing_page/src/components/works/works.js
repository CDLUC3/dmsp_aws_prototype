import { Link } from '../../components/link/link';

function groupByType(works) {
  let grouped = {};
  works.forEach((work) => {
    if (!(work.work_type.toString() in grouped)) {
      grouped[work.work_type.toString()] = [];
    }
    grouped[work.work_type].push(work);
  });
  return grouped;
}

function Work(props) {
  let work = props?.work;
  let idx = props?.index;

  return (
    <li key={idx + 'li'}>
      <Link href={work.identifier} remote='true' key={idx + 'li a'}/>
    </li>
  );
}

function Works(props) {
  let works = props?.works || [];

  if (Array.isArray(works) && works.length > 0) {
    works = groupByType(works);

    return (
      <div className="t-step__content">
        <h2>Other works associated with this research project</h2>

        {Object.keys(works).map((category, idx) => (
          <div key={'work-cat' + idx}>
            <h3 key={'work-cat' + idx + 'h3'}>{category[0].toUpperCase() + category.slice(1).replace('_', ' ')}</h3>
            <ul className="landing-list" key={'work-cat' + idx + 'ul'}>
              {works[category].map((work, idx2) => (
                <Work work={work} index={'work-cat' + idx + idx2}/>
              ))}
            </ul>
          </div>
        ))}
      </div>
    );
  }
}

export default Works;
