import { Link } from '../../components/link/link';

function Funding(props) {
  let FunderLink = props?.funder_link;
  let award_id = props?.award_id;
  let opportunity_number = props.opportunity_number;

  return (
    <div className="t-step__content">
      <h2>Funding status and sources for this project</h2>

      <ul className="landing-list">
        <li><strong>Status:</strong> {award_id === '' ? 'Planned' : 'Approved'}</li>
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
          <li><strong>Grant:</strong> {award_id} <Link href={award_id} remote='true'/></li>
        }
      </ul>
    </div>
  );
}

export default Funding;
