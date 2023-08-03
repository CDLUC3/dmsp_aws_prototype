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

export function getValue(obj, path, defaultNone) {
  if (typeof defaultNone === 'undefined') defaultNone = "";
  if (typeof path === 'string') path = path.split(".");

  if (path.length === 0) throw "Path Length is Zero";
  if (path.length === 1) return obj[path[0]];

  if (!obj[path[0]]) return defaultNone;
  return getValue(obj[path[0]], path.slice(1));
};

export function inDevMode() {
  return window.location.hostname === 'localhost';
}
