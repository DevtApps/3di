// Arquivos da IDE: abrir, salvar e exportar no disco.
//  - Seletores de arquivo do navegador (File System Access API: Chrome/Edge, inclusive no app 3DI).
//  - Arquivo passado na linha de comando do app (#file=...): lido e salvo pelo servidor local,
//    com o token de #token=... (sem ele, nenhum site consegue ler/escrever disco via localhost).
//  - Sem nenhum dos dois: abrir por <input type=file> e salvar como download.

const hash = new URLSearchParams(location.hash.slice(1));
const token = hash.get('token');

const TYPES_3DI = [{ description: 'Cena 3DI', accept: { 'text/plain': ['.3di'] } }];
const canPick = typeof window.showOpenFilePicker === 'function';

function download(blob, name) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

async function serverRead(path) {
  const r = await fetch(`/fs/read?path=${encodeURIComponent(path)}`, { headers: { 'X-3DI-Token': token } });
  if (!r.ok) throw new Error(await r.text());
  return r.text();
}

async function serverWrite(path, body) {
  const r = await fetch(`/fs/write?path=${encodeURIComponent(path)}`, { method: 'POST', headers: { 'X-3DI-Token': token }, body });
  if (!r.ok) throw new Error(await r.text());
}

/**
 * getText/setText: conteúdo do editor; onState({ name, dirty, where }) atualiza título e status.
 */
export function createFiles({ getText, setText, onState = () => {}, onOpen = () => {}, template = '', desktop = window.desktop3di }) {
  const st = { name: 'sem título.3di', handle: null, path: null, dirty: false, saved: '' };
  const emit = () => {
    document.title = `${st.dirty ? '• ' : ''}${st.name} — 3DI`;
    desktop?.state(st.dirty);
    onState({ name: st.name, dirty: st.dirty, where: st.path ?? (st.handle ? 'disco' : null) });
  };
  const confirmDiscard = () => !st.dirty || confirm(`Descartar as alterações em ${st.name}?`);

  const setFile = ({ name, handle = null, path = null, text }) => {
    Object.assign(st, { name, handle, path, saved: text, dirty: false });
    setText(text);
    emit();
  };

  const write = async (text) => {
    if (desktop) {
      const saved = await desktop.save(text, st.name, false);
      if (!saved) return false;
      Object.assign(st, { path: saved.path, handle: null, name: saved.name, saved: text, dirty: false });
    } else if (st.handle) {
      const w = await st.handle.createWritable();
      await w.write(text);
      await w.close();
    } else if (st.path && token) {
      await serverWrite(st.path, text);
    } else {
      return false;
    }
    st.saved = text;
    st.dirty = false;
    emit();
    return true;
  };

  const api = {
    state: () => ({ ...st }),
    changed() {
      const d = getText() !== st.saved;
      if (d !== st.dirty) { st.dirty = d; emit(); }
    },
    async open() {
      if (desktop) {
        const file = await desktop.open();
        if (file) setFile(file);
        return;
      }
      if (!confirmDiscard()) return;
      if (canPick) {
        let handle;
        try { [handle] = await window.showOpenFilePicker({ types: TYPES_3DI, excludeAcceptAllOption: false }); } catch { return; }
        const file = await handle.getFile();
        setFile({ name: file.name, handle, text: await file.text() });
        return;
      }
      const input = Object.assign(document.createElement('input'), { type: 'file', accept: '.3di,text/plain' });
      input.onchange = async () => {
        const f = input.files[0];
        if (f) setFile({ name: f.name, text: await f.text() });
      };
      input.click();
    },
    async save() {
      if (!(await write(getText()))) return api.saveAs();
      return st.name;
    },
    async saveAs() {
      const text = getText();
      if (desktop) {
        const saved = await desktop.save(text, st.name, true);
        if (!saved) return null;
        Object.assign(st, { path: saved.path, handle: null, name: saved.name, saved: text, dirty: false });
        emit();
        return st.name;
      }
      if (canPick) {
        let handle;
        try { handle = await window.showSaveFilePicker({ suggestedName: st.name, types: TYPES_3DI }); } catch { return null; }
        Object.assign(st, { handle, path: null, name: handle.name });
        await write(text);
        return st.name;
      }
      download(new Blob([text], { type: 'text/plain' }), st.name);
      st.saved = text;
      st.dirty = false;
      emit();
      return st.name;
    },
    async newFile() {
      if (!confirmDiscard()) return;
      if (desktop) await desktop.reset();
      setFile({ name: 'sem título.3di', text: template });
    },
    loadFile(file) { setFile(file); },
    detach() {
      Object.assign(st, { path: null, handle: null, saved: '', dirty: getText() !== '' });
      emit();
    },
    // exemplo ou texto sem arquivo ligado (salvar pede um lugar)
    loadUntitled(name, text) { setFile({ name, text }); },
    // PNG / GLB: seletor de "salvar como" quando houver, senão download
    async saveBinary(blob, suggestedName, description, ext, mime) {
      if (desktop) return desktop.export(new Uint8Array(await blob.arrayBuffer()), suggestedName, ext);
      if (canPick) {
        let handle;
        try { handle = await window.showSaveFilePicker({ suggestedName, types: [{ description, accept: { [mime]: [ext] } }] }); } catch { return null; }
        const w = await handle.createWritable();
        await w.write(blob);
        await w.close();
        return handle.name;
      }
      download(blob, suggestedName);
      return suggestedName;
    },
    // abre o arquivo pedido na linha de comando do app (#file=/caminho/cena.3di)
    async openFromHash() {
      if (desktop) {
        desktop.onOpen((opened) => { setFile(opened); onOpen(opened); });
        const file = await desktop.initialFile();
        if (!file) return false;
        setFile(file);
        return true;
      }
      const path = hash.get('file');
      if (!path || !token) return false;
      try {
        setFile({ name: path.split('/').pop(), path, text: await serverRead(path) });
        return true;
      } catch (e) {
        console.warn(`não abriu ${path}: ${e.message}`);
        return false;
      }
    },
  };
  return api;
}
