import { Link } from '../../components/link/link';

const ROLE_PREFIX_REGEX = /^https?:\/\/credit\.niso\.org\/contributor-roles\//i;
const CURATION_ROLE = 'https://credit.niso.org/contributor-roles/data-curation'

function removeDuplicateRoles(roles) {
  return roles.filter((item, index) => roles.indexOf(item) === index);
}

function addPrimary(persons, primary) {
  persons = Array.isArray(persons) ? persons : [];

  if (primary !== undefined) {
    let existing = persons.filter((item, index) => item?.name === primary?.name);
    if (persons.length === 0 || (Array.isArray(existing) && existing[0] === undefined)) {
      primary.role = [CURATION_ROLE];
      persons.push(primary);
    } else {
      persons.forEach((item) => {
        if (item?.name === existing.name) {
          item.roles += [CURATION_ROLE];
        }
      });
    }
    return persons;
  }
}

function OrgLink(props) {
  let org = props?.org;
  let idx = props?.key || "";
  let nameUrlRegex = /\s+\(.*\)\s?/i;

  if (org !== undefined) {
    if (org.affiliation_id !== '') {
      return (
        <Link href={org.affiliation_id} label={org.name.replace(nameUrlRegex, '')} remote='true' index={idx + 'aid'}/>
      );
    } else {
      return org.name;
    }
  }
}
function OrcidLink(props) {
  let person = props?.person;
  let idx = props?.index || "";
  if (person !== undefined) {
    if ('contributor_id' in person || 'contact_id' in person) {
      let orcid = 'contributor_id' in person ? person.contributor_id : person.contact_id
      if ('identifier' in orcid) {
        return (
          <Link href={orcid.identifier} label={orcid.identifier.replace(/https?:\/\/orcid.org\//i, '')}
                remote='true' index={idx + 'oid'} className="c-orcid"/>
        );
      }
    }
  }
}
function RoleLink(props) {
  let role = props?.role;
  let idx = props?.index;

  if (role !== undefined && idx !== undefined){
    let displayRole = role.toString().replace(ROLE_PREFIX_REGEX, '');
    if (displayRole.length > 0) {
      displayRole = displayRole.replace('-', ' ').charAt(0).toUpperCase() + displayRole.slice(1);
      return (
        <Link href={role} label={displayRole} remote='true' index={'a' + idx}/>
      );
    }
  }
}

function RoleLinks(props) {
  let person = props?.person;
  let index = props?.index;
  if (person !== undefined && index !== undefined) {
    if ('role' in person && Array.isArray(person.role) && person.role.length > 0) {
      let roles = removeDuplicateRoles(person.role); // [...new Set(contributor.role)];

      return roles.map((role, idx) => (
        <RoleLink role={role} index={index} key={index + 'role' + idx}/>
      ));
    }
  }
}
function Contributor(props) {
  let person = props?.person;
  let idx = props?.index;
  if (person !== undefined && idx !== undefined) {
    if ('name' in person) {
      return (
        <li className="comma-separated" key={'li' + idx}>
          <strong key={'strong' + idx}>{person.name}:</strong>
          <RoleLinks person={person} index={'rl' + idx}/>
          <OrgLink org={person.dmproadmap_affiliation} index={'org' + idx}/>
          <OrcidLink person={person} index={'orcid' + idx}/>
        </li>
      );
    }
  }
}

function Contributors(props) {
  let primary = props?.primary;
  let persons = props?.persons || [];

  persons = addPrimary(persons, primary);
  if (Array.isArray(persons) && persons.length > 0) {
    return (
      <div className="t-step__content">
        <h2>Contributors to this project</h2>

        <ul className="landing-list">
          {persons.map((person, idx) => (
            <Contributor person={person} index={'contrib' + idx}/>
          ))}
        </ul>
      </div>
    );
  }
}

export default Contributors;
