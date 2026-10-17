import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('desktop3di', {
  workspace: () => ipcRenderer.invoke('3di:workspace'),
  reset: () => ipcRenderer.invoke('3di:reset'),
  open: () => ipcRenderer.invoke('3di:open'),
  save: (text: string, name: string, saveAs: boolean) => ipcRenderer.invoke('3di:save', { text, name, saveAs }),
  export: (bytes: Uint8Array, name: string, ext: string) => ipcRenderer.invoke('3di:export', { bytes, name, ext }),
  newProject: () => ipcRenderer.invoke('3di:newProject'),
  initialFile: () => ipcRenderer.invoke('3di:initialFile'),
  state: (dirty: boolean) => ipcRenderer.send('3di:dirty', dirty),
  onOpen: (callback: (file: unknown) => void) => { ipcRenderer.on('3di:opened', (_event, file) => callback(file)); },
});
