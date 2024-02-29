import * as sanitizeHtml from 'sanitize-html';

const defaultOptions = {
  allowedTags: [ 'b', 'i', 'em', 'strong', 'a', 'p', 'ul', 'ol', 'li', 'br', 'table', 'th', 'tr', 'td' ],
  allowedAttributes: {
    'a': [ 'href' ]
  },
};

const sanitize = (dirty, options) => ({
  __html: sanitizeHtml(
    dirty,
    defaultOptions,
  )
});

export const SanitizeHTML = ({ html, options }) => (
  <div dangerouslySetInnerHTML={sanitize(html, options)} />
);

export function inDevMode() {
  return window.location.hostname === 'localhost';
}
