// Suporte à linguagem 3DI no Monaco: cores, indentação, autocomplete, assinaturas,
// documentação ao passar o mouse, snippets e marcação de erros.

const SNIPPETS = [
  ['cena', 'Cena básica com chão, objeto e câmera', [
    'chao = plane().color("${1:lightgray}")',
    '${2:objeto} = ${3:box(1, round=0.05)}.color("${4:red}").ground().name("${2:objeto}")',
    '',
    'show(chao, ${2:objeto})',
    'camera(pos=(${5:3}, ${6:2}, ${7:4}))',
  ]],
  ['def forma', 'Função que monta um objeto reutilizável', [
    'def ${1:objeto}(${2:tamanho=1}):',
    '    ${3:base} = ${4:box(tamanho, 0.1, tamanho)}.place()',
    '    $0',
    '    return group(${3:base})',
  ]],
  ['sobre', 'Apoia um objeto em cima de outro', ['${1:obj} = ${2:sphere(0.2)}.on(${3:alvo}, x=${4:0}, z=${5:0})']],
  ['ao lado', 'Encosta um objeto ao lado de outro', ['${1:obj} = ${2:box(0.5)}.beside(${3:alvo}, side="${4|right,left,front,back|}", gap=${5:0.1})']],
  ['pernas', 'Uma perna espelhada nos 4 cantos (mirror)', [
    'perna = ${1:cylinder(0.03, 0.7)}.place(${2:0.5}, 0, ${3:0.3}).mirror("xz")',
  ]],
  ['grade', 'Cópias em grade com repeat (não custa primitivas)', ['${1:item}.repeat(x=${2:5}, z=${3:1}, spacing=${4:1})']],
  ['recorte', 'Subtração que atravessa a superfície', [
    '${1:parede} = ${2:box(4, 3, 0.3)}.place()',
    '${3:janela} = box(${4:1}, ${5:1.2}, 0.3 + 0.2).place(${6:0}, ${7:1}, 0)',
    '${1:parede} = ${1:parede} - ${3:janela}',
  ]],
  ['for', 'Laço for', ['for ${1:i} in range(${2:10}):', '    $0']],
  ['lista', 'Compreensão de lista com formas', ['[${1:sphere(0.1)}.at(${2:i} * ${3:0.3}, 0, 0) for ${2:i} in range(${4:5})]']],
  ['if', 'Condição', ['if ${1:condicao}:', '    $0']],
  ['madeira', 'Textura de madeira', ['.color("${1:#b07a45}").texture("wood", axis="${2|x,y,z|}")']],
  ['metal', 'Material metálico', ['.material(color="${1:silver}", metal=1, rough=${2:0.25})']],
  ['gira', 'Animação: girar com o tempo', ['.rotate(${1|y,x,z|}=time * ${2:45})']],
  ['oscila', 'Animação: ir e voltar', ['.move(y=osc(${1:0}, ${2:0.3}, period=${3:2}))']],
  ['rig', 'Esqueleto com um osso e uma parte presa a ele', [
    'esq = skeleton("${1:rig}")',
    '${2:raiz} = esq.bone("${2:raiz}", head=(0, ${3:1}, 0))',
    '${4:braco} = esq.bone("${4:braco}", head=(${5:0.2}, ${3:1}, 0), parent=${2:raiz})',
    '${6:parte} = segment((${5:0.2}, ${3:1}, 0), (${7:0.5}, ${3:1}, 0), 0.05).bind(${4:braco})',
    '${4:braco}.rotate(z=sin(time * 2) * 30)',
  ]],
  ['animação glTF', 'Duração do ciclo exportado', ['animation(duration=${1:4}, fps=${2:30})']],
];

const tokenizer = (catalog) => ({
  defaultToken: '',
  keywords: catalog.keywords,
  builtins: [...catalog.functions.map((f) => f.name), ...catalog.constants.map((c) => c.name)],
  tokenizer: {
    root: [
      [/#.*$/, 'comment'],
      [/[fF]?"""/, 'string', '@tstring'],
      [/[fF]?"/, 'string', '@dstring'],
      [/[fF]?'/, 'string', '@sstring'],
      [/\d[\d_]*\.?[\d_]*([eE][+-]?\d+)?|\.\d+/, 'number'],
      [/\.([a-zA-Z_]\w*)/, 'method'],
      [/[a-zA-Z_À-ÿ][\wÀ-ÿ]*/, { cases: { '@keywords': 'keyword', '@builtins': 'predefined', '@default': 'identifier' } }],
      [/[()[\]{}]/, '@brackets'],
      [/[+\-*/%=<>!&|^~@]+/, 'operator'],
    ],
    dstring: [[/[^"\\]+/, 'string'], [/\\./, 'string.escape'], [/"/, 'string', '@pop']],
    sstring: [[/[^'\\]+/, 'string'], [/\\./, 'string.escape'], [/'/, 'string', '@pop']],
    tstring: [[/"""/, 'string', '@pop'], [/./, 'string']],
  },
});

// descobre variáveis e funções do script (para sugerir os nomes do usuário)
function userNames(text) {
  const names = new Map();
  for (const m of text.matchAll(/^\s*def\s+([A-Za-z_]\w*)\s*\(([^)]*)\)/gm)) names.set(m[1], { kind: 'function', detail: `def ${m[1]}(${m[2]})` });
  for (const m of text.matchAll(/^\s*([A-Za-z_][\w, ]*)=(?!=)/gm)) {
    for (const n of m[1].split(',').map((s) => s.trim()).filter(Boolean)) if (!names.has(n)) names.set(n, { kind: 'variable', detail: 'variável' });
  }
  for (const m of text.matchAll(/^\s*for\s+([\w, ()]+)\s+in\b/gm)) {
    for (const n of m[1].replace(/[()]/g, '').split(',').map((s) => s.trim()).filter(Boolean)) if (!names.has(n)) names.set(n, { kind: 'variable', detail: 'variável do for' });
  }
  return names;
}

// tipo provável de um nome: esqueleto, osso ou forma
function receiverKind(text, name) {
  if (new RegExp(`^\\s*${name}\\s*=\\s*skeleton\\(`, 'm').test(text)) return 'skeleton';
  if (new RegExp(`^\\s*${name}\\s*=\\s*\\w+\\.(bone|get)\\(`, 'm').test(text)) return 'bone';
  return 'shape';
}

// nome da função e índice do argumento na chamada que contém o cursor
function enclosingCall(textBefore) {
  let depth = 0, arg = 0, kw = null;
  for (let i = textBefore.length - 1; i >= 0; i--) {
    const ch = textBefore[i];
    if (ch === ')' || ch === ']' || ch === '}') depth++;
    else if (ch === '[' || ch === '{') { if (depth === 0) return null; depth--; }
    else if (ch === '(') {
      if (depth === 0) {
        const m = /(\.)?([A-Za-z_]\w*)\s*$/.exec(textBefore.slice(0, i));
        return m ? { name: m[2], method: !!m[1], arg, kw } : null;
      }
      depth--;
    } else if (ch === ',' && depth === 0) arg++;
    else if (ch === '=' && depth === 0 && arg === 0 && kw === null && textBefore[i - 1] !== '=' && textBefore[i + 1] !== '=') {
      const m = /([A-Za-z_]\w*)\s*$/.exec(textBefore.slice(0, i));
      if (m) kw = m[1];
    }
  }
  return null;
}

export function register3di(monaco, catalog) {
  const L = monaco.languages;
  L.register({ id: '3di', extensions: ['.3di'], aliases: ['3DI'] });
  L.setMonarchTokensProvider('3di', tokenizer(catalog));
  L.setLanguageConfiguration('3di', {
    comments: { lineComment: '#' },
    brackets: [['(', ')'], ['[', ']'], ['{', '}']],
    autoClosingPairs: [
      { open: '(', close: ')' }, { open: '[', close: ']' }, { open: '{', close: '}' },
      { open: '"', close: '"', notIn: ['string'] }, { open: "'", close: "'", notIn: ['string'] },
    ],
    surroundingPairs: [{ open: '(', close: ')' }, { open: '[', close: ']' }, { open: '"', close: '"' }],
    onEnterRules: [{ beforeText: /:\s*(#.*)?$/, action: { indentAction: L.IndentAction.Indent } }],
    indentationRules: { increaseIndentPattern: /:\s*(#.*)?$/, decreaseIndentPattern: /^\s*(elif|else)\b/ },
  });

  const fnByName = new Map(catalog.functions.map((f) => [f.name, f]));
  const methodByName = new Map(catalog.methods.map((m) => [m.name, m]));
  const rigByName = new Map([...catalog.rig.skeleton, ...catalog.rig.bone].map((m) => [m.name, m]));
  const K = L.CompletionItemKind;
  const doc = (d) => (d ? { value: d } : undefined);

  L.registerCompletionItemProvider('3di', {
    triggerCharacters: ['.', '"', "'", '('],
    provideCompletionItems(model, position) {
      const line = model.getLineContent(position.lineNumber);
      const before = line.slice(0, position.column - 1);
      const word = model.getWordUntilPosition(position);
      const range = { startLineNumber: position.lineNumber, endLineNumber: position.lineNumber, startColumn: word.startColumn, endColumn: word.endColumn };
      const text = model.getValue();

      // dentro de um texto: cores, texturas, lados, eixos
      const str = /(["'])([\w#À-ÿ]*)$/.exec(before);
      if (str && (before.split(str[1]).length - 1) % 2 === 1) {
        const call = enclosingCall(before.slice(0, before.length - str[0].length));
        const key = call?.kw ?? call?.name;
        let list = null, kind = K.Value;
        if (['color', 'color2', 'sky'].includes(key) || (call?.name === 'material' && call.kw === 'color')) { list = catalog.colors; kind = K.Color; }
        else if (key === 'texture' || key === 'kind') list = catalog.textures;
        else if (key === 'side' || (call?.name === 'beside' && call.arg === 1)) list = catalog.sides;
        else if (key === 'axis' || key === 'axes' || key === 'mirror') list = call.name === 'mirror' ? ['x', 'z', 'xz', 'y', 'xyz'] : ['x', 'y', 'z'];
        if (!list) return { suggestions: [] };
        return { suggestions: list.map((v) => ({ label: v, kind, insertText: v, range })) };
      }

      // depois de um ponto: métodos do objeto
      const dot = /([A-Za-z_]\w*|\))\s*\.\s*\w*$/.exec(before);
      if (dot) {
        const rk = dot[1] === ')' ? 'shape' : receiverKind(text, dot[1]);
        if (rk !== 'shape') {
          return {
            suggestions: catalog.rig[rk].map((m) => ({
              label: m.name, kind: m.property ? K.Property : K.Method, detail: m.signature, documentation: doc(m.doc),
              insertText: m.property ? m.name : `${m.name}($0)`, insertTextRules: L.CompletionItemInsertTextRule.InsertAsSnippet, range,
            })),
          };
        }
        return {
          suggestions: [
            ...catalog.methods.map((m) => ({
              label: m.name, kind: K.Method, detail: `.${m.signature}`, documentation: doc(m.doc),
              insertText: `${m.name}($0)`, insertTextRules: L.CompletionItemInsertTextRule.InsertAsSnippet, range,
              command: { id: 'editor.action.triggerParameterHints' },
            })),
            ...catalog.properties.map((p) => ({ label: p.name, kind: K.Property, detail: 'propriedade', documentation: doc(p.doc), insertText: p.name, range })),
            ...['append', 'extend', 'pop', 'insert'].map((n) => ({ label: n, kind: K.Method, detail: 'lista', insertText: `${n}($0)`, insertTextRules: L.CompletionItemInsertTextRule.InsertAsSnippet, range, sortText: 'z' })),
          ],
        };
      }

      // dentro de uma chamada: nomes dos parâmetros (ex: round=, smooth=)
      const suggestions = [];
      const call = enclosingCall(before);
      if (call) {
        const info = call.method ? methodByName.get(call.name) ?? rigByName.get(call.name) : fnByName.get(call.name);
        for (const p of info?.params ?? []) {
          suggestions.push({ label: `${p}=`, kind: K.Field, detail: info.signature, insertText: `${p}=`, range, sortText: '0' });
        }
      }

      const user = userNames(text);
      for (const [name, u] of user) {
        suggestions.push({ label: name, kind: u.kind === 'function' ? K.Function : K.Variable, detail: u.detail, insertText: u.kind === 'function' ? `${name}($0)` : name, insertTextRules: L.CompletionItemInsertTextRule.InsertAsSnippet, range, sortText: '1' });
      }
      for (const f of catalog.functions) {
        suggestions.push({
          label: f.name, kind: K.Function, detail: f.signature, documentation: doc(f.doc),
          insertText: f.params.length || f.star ? `${f.name}($0)` : `${f.name}()`, insertTextRules: L.CompletionItemInsertTextRule.InsertAsSnippet, range,
          command: { id: 'editor.action.triggerParameterHints' }, sortText: f.category === 'python' ? '3' : '2',
        });
      }
      for (const c of catalog.constants) suggestions.push({ label: c.name, kind: K.Constant, detail: c.doc, insertText: c.name, range, sortText: '2' });
      for (const k of catalog.keywords) suggestions.push({ label: k, kind: K.Keyword, insertText: k, range, sortText: '4' });
      for (const [label, desc, body] of SNIPPETS) {
        suggestions.push({ label, kind: K.Snippet, detail: desc, documentation: { value: '```\n' + body.join('\n') + '\n```' }, insertText: body.join('\n'), insertTextRules: L.CompletionItemInsertTextRule.InsertAsSnippet, range, sortText: '5' });
      }
      return { suggestions };
    },
  });

  L.registerSignatureHelpProvider('3di', {
    signatureHelpTriggerCharacters: ['(', ','],
    signatureHelpRetriggerCharacters: [','],
    provideSignatureHelp(model, position) {
      const before = model.getValueInRange({ startLineNumber: Math.max(1, position.lineNumber - 10), startColumn: 1, endLineNumber: position.lineNumber, endColumn: position.column });
      const call = enclosingCall(before);
      if (!call) return null;
      const info = call.method ? methodByName.get(call.name) ?? rigByName.get(call.name) : fnByName.get(call.name);
      if (!info?.params) return null;
      const label = call.method ? `.${info.signature}` : info.signature;
      const inside = label.slice(label.indexOf('(') + 1, label.lastIndexOf(')'));
      const params = inside ? inside.split(', ').map((p) => ({ label: p })) : [];
      let active = call.kw ? params.findIndex((p) => p.label.split('=')[0] === call.kw) : Math.min(call.arg, params.length - 1);
      if (active < 0) active = 0;
      return {
        value: { signatures: [{ label, documentation: info.doc, parameters: params }], activeSignature: 0, activeParameter: active },
        dispose() {},
      };
    },
  });

  L.registerHoverProvider('3di', {
    provideHover(model, position) {
      const w = model.getWordAtPosition(position);
      if (!w) return null;
      const line = model.getLineContent(position.lineNumber);
      const isMethod = line[w.startColumn - 2] === '.';
      const info = isMethod ? methodByName.get(w.word) ?? rigByName.get(w.word) ?? catalog.properties.find((p) => p.name === w.word)
        : fnByName.get(w.word) ?? catalog.constants.find((c) => c.name === w.word);
      if (!info) return null;
      const sig = info.signature ? (isMethod ? `.${info.signature}` : info.signature) : info.name;
      return { contents: [{ value: '```python\n' + sig + '\n```' }, ...(info.doc ? [{ value: info.doc }] : [])] };
    },
  });
}

// marca o erro do script no editor (linha + dica)
export function setScriptError(monaco, model, error) {
  if (!error) { monaco.editor.setModelMarkers(model, '3di', []); return; }
  const line = Math.min(Math.max(1, error.line ?? 1), model.getLineCount());
  monaco.editor.setModelMarkers(model, '3di', [{
    severity: monaco.MarkerSeverity.Error,
    message: error.message + (error.hint ? `\ndica: ${error.hint}` : ''),
    startLineNumber: line, endLineNumber: line, startColumn: model.getLineFirstNonWhitespaceColumn(line) || 1, endColumn: model.getLineMaxColumn(line),
  }]);
}
