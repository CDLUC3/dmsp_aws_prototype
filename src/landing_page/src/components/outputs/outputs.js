import { SanitizeHTML } from '../../utils';
import DisplayDate from '../../components/displayDate/displayDate';
import { Link } from '../../components/link/link';

function calculateSize(distributions) {
  let size = 0;

  if (Array.isArray(distributions) && distributions.length > 0) {
    // Get the largest size
    size = Math.max.apply(null, distributions.map((obj) => { return obj?.byte_size || 0; }));
  }
  if (isNaN(size) || size === 0 || size > Number.MAX_VALUE) {
    return 'unspecified';
  } else if (size >= 1125899906842624) {
    return `${Math.round(size / 1125899906842624)} PB`;
  } else if (size >= 1099511627776) {
    return `${Math.round(size / 1099511627776)} TB`;
  } else if (size >= 1073741824) {
    return `${Math.round(size / 1073741824)} GB`;
  } else if (size >= 1048576) {
    return `${Math.round(size / 1048576)} MB`;
  } else if (size >= 1024) {
    return `${Math.round(size / 1024)} KB`;
  } else {
    return `${size} bytes`;
  }
}

function MetadataStandardLink(props) {
  let standards = props?.standards || [];
  let idx = props?.index;

  return (
    <span key={idx + 'attr-meta-s'}>
      {standards.map((standard, index) => (
        <Link href={standard?.metadata_standard_id?.identifier} label={standard?.description?.split(' - ')[0]}
              remote='true' key={idx + 'attr-meta-s' + index}/>
      ))}
    </span>
  );
}

function HostLink(props) {
  let hosts = props?.hosts || [];
  let idx = props?.index;

  return (
    <span key={idx + 'attr-host-s'}>
      {hosts.map((host, index) => (
        <Link href={host?.url} label={host?.title} remote='true' key={idx + 'attr-host-s' + index}/>
      ))}
    </span>
  );
}

function LicenseLink(props) {
  let licenses = props?.licenses || [];
  let idx = props?.index;

  return (
    <span key={idx + 'attr-license-s'}>
      {licenses.map((license, index) => (
        <Link href={license?.license_ref} label={license?.license_ref?.split('/').at(-1).replace('.json', '')}
              remote='true' key={idx + 'attr-license-s' + index}/>
      ))}
    </span>
  );
}

function Output(props) {
  let idx = props?.index;
  let output = props?.output;
  let standards = output?.metadata || [];
  let distributions = props?.output?.distribution || [];
  let hosts = Array.isArray(distributions) && distributions.length > 0 ? distributions.map((obj) => { return obj?.host }) : [];
  let licenses = Array.isArray(distributions) && distributions.length > 0 ? distributions.map((obj) => { return obj?.license }) : [];
  let byteSize = calculateSize(distributions);

  if (output !== undefined) {
    return (
      <li key={idx + 'li'}>
        <h3 key={idx + 'title'}>{output.title}</h3>
        <div className="text-block" key={idx + 'descr'}><SanitizeHTML html={output.description}/></div>
        <ul className="landing-list" key={idx + 'attrs'}>
          {output.type !== undefined &&
            <li key={idx + 'attr-type'}>
              <strong key={idx + 'attr-type-b'}>Format:</strong>
              <span key={idx + 'attr-type-s'}>{output.type[0].toUpperCase() + output.type.slice(1)?.replace('_', ' ')}</span>
            </li>
          }
          {Array.isArray(standards) && standards.length > 0 &&
            <li key={idx + 'attr-meta'}>
              <strong key={idx + 'attr-meta-b'}>Metadata Standard(s):</strong>
              <MetadataStandardLink standards={standards} index={idx + 'attr-meta-a'}/>
            </li>
          }
          {byteSize !== undefined &&
            <li key={idx + 'attr-size'}>
              <strong key={idx + 'attr-size-b'}>Anticipated volume:</strong>
              <span key={idx + 'attr-size-s'}>{byteSize}</span>
            </li>
          }
          {output.issued !== undefined &&
            <li key={idx + 'attr-issue'}>
              <strong key={idx + 'attr-issue-b'}>Release timeline:</strong>
              <span key={idx + 'attr-issue-s'}>{DisplayDate(output.issued)}</span>
            </li>
          }
          {Array.isArray(hosts) && hosts.length > 0 &&
            <li key={idx + 'attr-host'}>
              <strong key={idx + 'attr-host-b'}>Intended repository:</strong>
              <HostLink hosts={hosts} index={idx + 'attr-host-a'}/>
            </li>
          }
          {Array.isArray(licenses) && licenses.length > 0 &&
            <li key={idx + 'attr-license'}>
              <strong key={idx + 'attr-license-b'}>License for reuse:</strong>
              <LicenseLink licenses={licenses.flat()} index={idx + 'attr-license-a'}/>
            </li>
          }
        </ul>
      </li>
    );
  }
}

function Outputs(props) {
  let outputs = props?.outputs || [];

  if (Array.isArray(outputs) && outputs.length > 0) {
    return (
      <div className="t-step__content">
        <h2>Planned outputs</h2>

        <ul className="landing-list">
          {outputs.map((output, idx) => (
            <Output output={output} index={'output' + idx}/>
          ))}
        </ul>
      </div>
    );
  }
}

export default Outputs;