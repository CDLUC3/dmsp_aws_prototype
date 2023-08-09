import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

import { getValue } from "../../utils";
import { DmpApi } from "../../api";

import { DmptoolLink, Link } from '../../components/link/link';

import Abstract from "../../components/abstract/abstract";
import Citation from "../../components/citation/citation";
import Contributors from "../../components/contributors/contributors";
import Footer from "../../components/footer/footer";
import Funding from "../../components/funding/funding";
import Outputs from "../../components/outputs/outputs";
import Project from "../../components/project/project";
import Versions from "../../components/versions/versions";
import Works from "../../components/works/works";

import narrativeLogo from '../../assets/u153.svg';
import "./landing.scss";

function Landing() {
  const [formData, setFormData] = useState({
    title: "Loading ...",
    description: "",
    dmp_id: "",
    privacy: "private",
    modified: "",

    funder_name: "",
    funder_id: "",
    award_id: "",
    opportunity_number: "",

    project_title: "",
    project_abstract: "",
    project_start: "",
    project_end: "",

    contact: {},
    contributors: [],
    datasets: [],
    related_identifiers: [],
    versions: [],
  });

  const navigate = useNavigate();

  useEffect(() => {
    // Fetch the DMP ID metadata from the DMPHub
    let api = new DmpApi();

    fetch(api.getUrl(), api.getOptions())
      .then((resp) => {
        api.handleResponse(resp);
        return resp.json();
      })
      .then((data) => {
        // console.log(data.items[0].dmp);
        if (Array.isArray(data?.items) && data?.items[0] !== null) {
          let dmp = data.items[0].dmp;
          //console.log(dmp);

          setFormData({
            json_url: api.getUrl(),
            title: getValue(dmp, "title", ""),
            description: getValue(dmp, "description", ""),
            dmp_id: getValue(dmp, "dmp_id.identifier", ""),
            privacy: getValue(dmp, "dmproadmap_privacy", "private"),
            created: getValue(dmp, "created", ""),
            modified: getValue(dmp, "modified", ""),
            ethical_issues_exist: getValue(dmp, "ethical_issues_exits", "unknown"),
            ethical_issues_report: getValue(dmp, "ethical_issues_report", ""),

            funder_name: getValue(dmp, "project.0.funding.0.name", ""),
            funder_id: getValue(dmp, "project.0.funding.0.funder_id.identifier", ""),
            award_id: getValue(dmp, "project.0.funding.0.grant_id.identifier", ""),
            opportunity_number: getValue(dmp, "project.0.funding.0.dmproadmap_funding_opportunity_id.identifier", ""),

            project_title: getValue(dmp, "project.0.title", ""),
            project_abstract: getValue(dmp, "project.0.description", ""),
            project_start: getValue(dmp, "project.0.start", ""),
            project_end: getValue(dmp, "project.0.end", ""),

            contact: getValue(dmp, "contact", {}),
            contributors: getValue(dmp, "contributor", []),
            datasets: getValue(dmp, "dataset", []),
            related_identifiers: filterWorks(getValue(dmp, "dmproadmap_related_identifiers", [])),
            versions: getValue(dmp, "dmphub_versions", []),
          });
        } else {
          navigate('/not_found');
        }
      });
  }, [navigate]);

  function dmpIdWithoutAddress() {
    return formData.dmp_id?.replace('https://doi.org/', '');
  }
  function FunderLink() {
    let nameUrlRegex = /\s+\(.*\)\s?/i;
    if (formData.funder_id !== '') {
      return (<Link href={formData.funder_id} label={formData.funder_name.replace(nameUrlRegex, '')} remote='true'/> );
    } else {
      return formData.funder_name;
    }
  }
  function isPublic() {
    return formData.privacy === 'public';
  }
  function narrativeUrl() {
    if (Array.isArray(formData.related_identifiers)) {
      let id = formData.related_identifiers.find(id => id.descriptor === 'is_metadata_for' && id.work_type === 'output_management_plan');
      return id?.identifier
    } else {
      return '';
    }
  }
  function filterWorks(works) {
    return works.filter((work) => work?.work_type !== 'output_management_plan' );
  }

  return (
    <div id="Dashboard">
      <header className="t_step__landing-header">
        <div className="dmptool-logo">
          <DmptoolLink withLogo='true'/>
        </div>
        <div className="dmp-menu">
          <ul>
            <li><strong>DMP ID:</strong> {dmpIdWithoutAddress()}</li>
            <Versions versions={formData.versions} currentVersion={formData.modified} />
          </ul>
        </div>
      </header>

      <div className="t-step__landing-title">
        <div className={isPublic() ? 'dmp-title' : 'dmp-title-wide'}>
          <p>This page describes a data management plan written for the <FunderLink/> using the <DmptoolLink/>.
             You can access this infomation as <Link href={formData.json_url} label='json here.' remote='true'/></p>
          <h1>{formData.title === '' ? formData.project_title : formData.title}</h1>
        </div>
        {isPublic() && narrativeUrl() && (
          <div className="dmp-pdf">
            <Link href={narrativeUrl()} remote='true' label={<img src={narrativeLogo} alt='PDF icon' aria-hidden='true'/>}/>
            <Link href={narrativeUrl()} remote='true' label='Read the data management plan'/>
          </div>
        )}
      </div>

      {formData.contributors && formData.contributors.length > 0 &&
        <Contributors persons={formData.contributors}
                      primary={formData.contact}/>
      }

      {formData.created !== undefined &&
        <Project datasets={formData.datasets}
                created={formData.created}
                modified={formData.modified}
                project_start={formData.project_start}
                project_end={formData.project_end}
                ethical_issues_exist={formData.ethical_issues_exist}/>
      }

      {formData.created !== undefined &&
        <Citation dmp_id={formData.dmp_id}
                  title={formData.title}
                  created={formData.created}
                  persons={formData.contributors}
                  dmptoolName='DMPTool'/>
      }

      {formData.funder_name !== '' &&
        <Funding funder_link={FunderLink}
                  award_id={formData.award_id}
                  opportunity_number={formData.opportunity_number} />
      }

      {((formData.project_abstract && formData.project_abstract !== '') || (formData.description && formData.description !== '')) &&
        <Abstract project_abstract={formData.project_abstract}
                  description={formData.description}/>
      }

      {(formData.datasets && formData.datasets.length > 0) &&
        <Outputs outputs={formData.datasets}/>
      }

      {(formData.related_identifiers && formData.related_identifiers.length > 0) &&
        <Works works={formData.related_identifiers}/>
      }

      <Footer/>
    </div>
  );
}

export default Landing;
