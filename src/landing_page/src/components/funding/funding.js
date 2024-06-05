import { Link } from '../../components/link/link';

function Funding(props) {
  let FunderLink = props?.funder_link;
  let award_id = props?.award_id;
  let opportunity_number = props?.opportunity_number;
  let funding_status = props?.funding_status;

  return (
    <div className="t-step__content">
      <h2>Funding status and sources for this project</h2>

      <ul className="landing-list">
        <li><strong>Status:</strong> {funding_status === 'funded' ? 'Awarded' : (funding_status === 'rejected' ? 'Denied' : 'Planned')}</li>
        <li><strong>Funder:</strong> <FunderLink/></li>
        {opportunity_number !== undefined &&
          <li>
            <strong>Funding opportunity number:</strong>
            {opportunity_number.startsWith('http') &&
              <Link href={opportunity_number} remote='true' />
            }
            {!opportunity_number.startsWith('http') &&
              opportunity_number
            }
          </li>
        }
        {award_id !== '' &&
          <li>
            <strong>Grant:</strong>
            {award_id.startsWith('http') &&
              <Link href={award_id} remote='true' />
            }
            {!award_id.startsWith('http') &&
              award_id
            }
          </li>
        }
      </ul>
    </div>
  );
}

export default Funding;
