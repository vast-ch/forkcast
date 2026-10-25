import Route from '@ember/routing/route';

/**
 * The changelog (the repository's CHANGELOG.md) as HTML. It and the Markdown
 * renderer load only when the page is opened. The page has its own heading,
 * so the file's is left out, and so is an Unreleased section with nothing in
 * it yet.
 */
export default class ChangelogRoute extends Route {
  async model(): Promise<string> {
    const [{ marked }, { default: text }] = await Promise.all([
      import('marked'),
      import('/CHANGELOG.md?raw'),
    ]);
    const body = text
      .replace(/^# .*\n/, '')
      .replace(/^## Unreleased\s*(?=^## )/m, '');
    return marked.parse(body, { async: false });
  }
}
