// Static renderer for the design canvas artboards (*.dc.html) on GitHub Pages.
//
// The canvas on claude.ai runs these files in its own editor runtime. This small stand-in renders
// a read-only snapshot: it runs the artboard's `Component.renderVals()` once and expands
// `{{holes}}`, `<sc-for>` and `<sc-if>`. Event handlers, state updates and child imports are not
// supported; edit the designs on the canvas (link in docs/DESIGN.md).
class DCLogic {
  constructor(props) {
    this.props = props || {};
    this.state = {};
  }

  setState(next) {
    Object.assign(this.state, next);
  }
}
window.DCLogic = DCLogic;

document.addEventListener('DOMContentLoaded', () => {
  const host = document.querySelector('x-dc');
  const script = document.querySelector('script[data-dc-script]');
  if (!host || !script) return;

  const Component = new Function('DCLogic', `${script.textContent}\nreturn Component;`)(DCLogic);
  const values = new Component({}).renderVals();

  const lookup = (path, scope) => {
    const trimmed = path.trim();
    if (trimmed === 'true') return true;
    if (trimmed === 'false') return false;
    return trimmed.split('.').reduce((value, key) => (value == null ? undefined : value[key]), scope);
  };
  const hole = /\{\{\s*([^}]+?)\s*\}\}/g;
  const fill = (text, scope) =>
    text.replace(hole, (_, path) => {
      const value = lookup(path, scope);
      return value == null || typeof value === 'function' ? '' : String(value);
    });
  const holeIn = (element, attribute) => element.getAttribute(attribute)?.match(/\{\{\s*([^}]+?)\s*\}\}/)?.[1];

  const walk = (node, scope) => {
    for (const child of Array.from(node.childNodes)) {
      if (child.nodeType === Node.TEXT_NODE) {
        child.textContent = fill(child.textContent, scope);
        continue;
      }
      if (child.nodeType !== Node.ELEMENT_NODE) continue;
      const tag = child.tagName.toLowerCase();

      if (tag === 'sc-for') {
        const list = lookup(holeIn(child, 'list') ?? '', scope) || [];
        const name = child.getAttribute('as');
        const fragment = document.createDocumentFragment();
        list.forEach((item, index) => {
          const template = document.createElement('template');
          template.innerHTML = child.innerHTML;
          walk(template.content, { ...scope, [name]: item, $index: index });
          fragment.append(template.content);
        });
        child.replaceWith(fragment);
        continue;
      }

      if (tag === 'sc-if') {
        if (lookup(holeIn(child, 'value') ?? '', scope)) {
          walk(child, scope);
          child.replaceWith(...Array.from(child.childNodes));
        } else {
          child.remove();
        }
        continue;
      }

      for (const attribute of Array.from(child.attributes)) {
        if (!attribute.value.includes('{{')) continue;
        if (attribute.name === 'ref' || attribute.name.startsWith('on')) {
          child.removeAttribute(attribute.name);
        } else if (attribute.name === 'checked') {
          child.toggleAttribute('checked', fill(attribute.value, scope) === 'true');
        } else {
          child.setAttribute(attribute.name, fill(attribute.value, scope));
        }
      }
      walk(child, scope);
    }
  };

  const helmet = host.querySelector('helmet');
  if (helmet) {
    document.head.insertAdjacentHTML('beforeend', helmet.innerHTML);
    helmet.remove();
  }
  walk(host, values);
});
