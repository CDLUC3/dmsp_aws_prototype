import { Link } from '../link/link';

function Footer() {
  const year = new Date().getFullYear();
  const uc3Url = 'https://uc3.cdlib.org/';
  const cdlUrl = 'http://www.cdlib.org';

  return (
    <footer>
      <nav></nav>

      <p>
        This product is a service of the <Link href={uc3Url} remote='true' label='University of California Curation Center'/> of the <Link href={cdlUrl} target='true' label='California Digital Library'/>
      </p>
      <p>Copyright 2010-{year} The Regents of the University of California.</p>
    </footer>
  );
}

export default Footer;