// Editor de código da IDE: Monaco (cópia local em node_modules, ou CDN) com a linguagem 3DI;
// sem Monaco (offline sem npm install), cai no textarea simples com números de linha.
import { register3di, setScriptError } from './monaco3di.js';
import { languageCatalog } from '../langinfo.js';

const MONACO_SOURCES = [
  'node_modules/monaco-editor/min/vs',
  'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs',
];

function loadScript(src) {
  return new Promise((res, rej) => {
    const s = document.createElement('script');
    s.src = src;
    s.onload = res;
    s.onerror = () => rej(new Error(`não carregou ${src}`));
    document.head.appendChild(s);
  });
}

async function loadMonaco() {
  for (const base of MONACO_SOURCES) {
    try {
      await loadScript(`${base}/loader.js`);
      const abs = new URL(base, location.href).href;
      // workers do Monaco a partir da mesma origem/CDN
      window.MonacoEnvironment = {
        getWorkerUrl: () => `data:text/javascript;charset=utf-8,${encodeURIComponent(
          `self.MonacoEnvironment = { baseUrl: '${abs}/../' }; importScripts('${abs}/base/worker/workerMain.js');`)}`,
      };
      window.require.config({ paths: { vs: abs } });
      return await new Promise((res, rej) => window.require(['vs/editor/editor.main'], () => res(window.monaco), rej));
    } catch (e) {
      console.warn(e.message);
      delete window.require;
    }
  }
  return null;
}

/**
 * Cria o editor dentro de wrap. Devolve { kind, getValue, setValue, setError, focus, onChange, addAction }.
 * keys: { save, saveAs, open, newFile, run } -> callbacks dos atalhos.
 */
export async function createEditor({ wrap, textarea, gutter, keys = {} }) {
  const listeners = [];
  const changed = () => listeners.forEach((f) => f());
  const monaco = await Promise.race([loadMonaco(), new Promise((r) => setTimeout(() => r(null), 8000))]);

  if (monaco) {
    register3di(monaco, languageCatalog());
    monaco.editor.defineTheme('3di-escuro', {
      base: 'vs-dark',
      inherit: true,
      rules: [
        { token: 'predefined', foreground: '6aa6ff' },
        { token: 'method', foreground: 'e5c07b' },
        { token: 'keyword', foreground: 'c678dd' },
        { token: 'number', foreground: 'd19a66' },
        { token: 'string', foreground: '98c379' },
        { token: 'comment', foreground: '6b7280', fontStyle: 'italic' },
      ],
      colors: { 'editor.background': '#15171c', 'editorGutter.background': '#15171c', 'editor.lineHighlightBackground': '#1c1f26' },
    });
    textarea.hidden = true;
    gutter.hidden = true;
    const host = document.createElement('div');
    host.style.cssText = 'position:absolute; inset:0;';
    wrap.appendChild(host);
    const ed = monaco.editor.create(host, {
      value: textarea.value,
      language: '3di',
      theme: '3di-escuro',
      automaticLayout: true,
      fontSize: 13,
      tabSize: 4,
      insertSpaces: true,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      renderWhitespace: 'boundary',
      suggest: { showWords: false, preview: true },
      quickSuggestionsDelay: 80,
      fixedOverflowWidgets: true,
    });
    const model = ed.getModel();
    model.onDidChangeContent(changed);
    const K = monaco.KeyMod, C = monaco.KeyCode;
    const bind = (id, label, key, fn) => fn && ed.addAction({ id, label, keybindings: [key], run: fn });
    bind('3di.save', 'Salvar', K.CtrlCmd | C.KeyS, keys.save);
    bind('3di.saveAs', 'Salvar como…', K.CtrlCmd | K.Shift | C.KeyS, keys.saveAs);
    bind('3di.open', 'Abrir…', K.CtrlCmd | C.KeyO, keys.open);
    bind('3di.new', 'Novo arquivo', K.CtrlCmd | K.Alt | C.KeyN, keys.newFile);
    bind('3di.run', 'Compilar agora', K.CtrlCmd | C.Enter, keys.run);
    return {
      kind: 'monaco',
      getValue: () => model.getValue(),
      // pushEditOperations mantém o desfazer (Ctrl+Z) funcionando depois de trocar o texto
      setValue: (v) => { if (v !== model.getValue()) model.pushEditOperations([], [{ range: model.getFullModelRange(), text: v }], () => null); },
      setError: (err) => setScriptError(monaco, model, err),
      focus: () => ed.focus(),
      onChange: (f) => listeners.push(f),
      reveal: (line) => { ed.revealLineInCenter(line); ed.setPosition({ lineNumber: line, column: 1 }); },
    };
  }

  // ---------- textarea simples ----------
  const updateGutter = () => {
    const n = textarea.value.split('\n').length;
    if (gutter.children.length !== n) gutter.innerHTML = Array.from({ length: n }, (_, i) => `<div>${i + 1}</div>`).join('');
    gutter.scrollTop = textarea.scrollTop;
  };
  const insert = (text) => {
    if (!document.execCommand('insertText', false, text)) textarea.setRangeText(text, textarea.selectionStart, textarea.selectionEnd, 'end');
  };
  textarea.addEventListener('input', () => { updateGutter(); changed(); });
  textarea.addEventListener('scroll', () => { gutter.scrollTop = textarea.scrollTop; });
  textarea.addEventListener('keydown', (e) => {
    const v = textarea.value;
    const s = textarea.selectionStart, end = textarea.selectionEnd;
    const lineStart = v.lastIndexOf('\n', s - 1) + 1;
    const mod = e.ctrlKey || e.metaKey;
    if (e.key === 'Tab') {
      e.preventDefault();
      const multi = v.slice(s, end).includes('\n');
      if (!multi && !e.shiftKey) { insert('    '); return; }
      const blockEnd = v.indexOf('\n', end - 1) < 0 ? v.length : v.indexOf('\n', Math.max(end - 1, s));
      const lines = v.slice(lineStart, blockEnd).split('\n');
      const out = lines.map((l) => (e.shiftKey ? l.replace(/^ {1,4}/, '') : '    ' + l)).join('\n');
      textarea.setSelectionRange(lineStart, blockEnd);
      insert(out);
      textarea.setSelectionRange(lineStart, lineStart + out.length);
    } else if (e.key === 'Enter' && !mod) {
      e.preventDefault();
      let indent = /^ */.exec(v.slice(lineStart, s))[0];
      if (/:\s*(#.*)?$/.test(v.slice(lineStart, s))) indent += '    ';
      insert('\n' + indent);
    } else if (mod && e.key.toLowerCase() === 's') {
      e.preventDefault();
      (e.shiftKey ? keys.saveAs : keys.save)?.();
    } else if (mod && e.key.toLowerCase() === 'o') {
      e.preventDefault();
      keys.open?.();
    } else if (mod && e.key === 'Enter') {
      e.preventDefault();
      keys.run?.();
    }
  });
  updateGutter();
  return {
    kind: 'textarea',
    getValue: () => textarea.value,
    setValue: (v) => { textarea.value = v; updateGutter(); },
    setError: (err) => [...gutter.children].forEach((d, i) => d.classList.toggle('err', i + 1 === err?.line)),
    focus: () => textarea.focus(),
    onChange: (f) => listeners.push(f),
    reveal: () => {},
  };
}
